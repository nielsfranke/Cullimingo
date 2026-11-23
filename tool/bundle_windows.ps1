# Packages the Windows release bundle into the three unsigned x64 downloads,
# the same set rawtonic ships (DISTRIBUTION.md, "Windows"):
#   Cullimingo_<v>_x64-setup.exe     NSIS, per user, no administrator rights
#   Cullimingo_<v>_x64.msi           WiX, per machine into Program Files
#   Cullimingo_<v>_x64-portable.zip  one Cullimingo\ folder, runs from anywhere
# plus SHA256SUMS-windows.txt (sha256sum format, LF endings).
#
# All three carry exactly the same staged folder: `flutter build windows
# --release` output + the libvips/LibRaw DLLs from libvips' official
# build-win64-mxe zip (SHA-256 pinned in windows/packaging/vips.sha256) + the
# Visual C++ runtime app-local (Flutter's engine and plugins import
# MSVCP140/VCRUNTIME140, which a PC without Visual Studio or the
# redistributable lacks).
#
#   flutter build windows --release
#   pwsh tool/bundle_windows.ps1 -VipsZip <vips-dev-x64-all-8.18.7.zip>
#
# Needs makensis (NSIS) and the WiX 5 CLI (`dotnet tool install --global wix
# --version 5.0.2`) on PATH.
param(
  [Parameter(Mandatory = $true)][string]$VipsZip,
  [string]$ReleaseDir = 'build\windows\x64\runner\Release',
  [string]$OutDir = 'build\windows\dist'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Fail([string]$message) { Write-Error $message; exit 1 }

# --- version ---------------------------------------------------------------
$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $line) { Fail 'no version: in pubspec.yaml' }
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)(-.+)?$') { Fail "unexpected version $version" }
# MSI/NSIS want a numeric x.y.z; a pre-release suffix only names the files.
$numeric = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
"Cullimingo $version (installer version $numeric)"

# --- libvips zip, pinned -----------------------------------------------------
$pin = (Get-Content windows\packaging\vips.sha256 -Raw).Trim() -split '\s+'
$zipName = Split-Path -Leaf $VipsZip
if ($zipName -ne $pin[1]) { Fail "expected $($pin[1]), got $zipName" }
$hash = (Get-FileHash $VipsZip -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $pin[0]) { Fail "$zipName SHA-256 $hash does not match the pin $($pin[0])" }
"libvips zip OK ($hash)"

# --- stage -----------------------------------------------------------------
if (-not (Test-Path "$ReleaseDir\cullimingo.exe")) { Fail "no cullimingo.exe in $ReleaseDir — run flutter build windows --release" }
$work = Join-Path $OutDir 'work'
if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null
$stage = Join-Path $work 'Cullimingo'
Copy-Item $ReleaseDir $stage -Recurse

$vips = Join-Path $work 'vips'
Expand-Archive $VipsZip -DestinationPath $vips
$vipsBin = Get-ChildItem $vips -Recurse -Directory -Filter bin | Select-Object -First 1
if (-not $vipsBin) { Fail 'no bin\ folder in the libvips zip' }
# The DLLs only; the vips-modules-* plugins (JPEG XL, ImageMagick, OpenSlide,
# Poppler) are loaders Cullimingo never uses.
Copy-Item (Join-Path $vipsBin.FullName '*.dll') $stage

# Visual C++ runtime, app-local, from the building Visual Studio.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$crt = Get-ChildItem "$vsPath\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT" -Directory -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { Fail "no VC++ redistributable folder under $vsPath\VC\Redist\MSVC" }
Copy-Item (Join-Path $crt.FullName '*.dll') $stage
"VC++ runtime from $($crt.FullName)"

foreach ($need in 'cullimingo.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\app.so',
                  'libvips-42.dll', 'libraw_r-25.dll', 'libglib-2.0-0.dll', 'libgobject-2.0-0.dll',
                  'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  if (-not (Test-Path (Join-Path $stage $need))) { Fail "the staged folder lacks $need" }
}
# Every DLL a shipped binary imports is either in the folder or part of Windows.
$dumpbin = Get-ChildItem "$vsPath\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" | Select-Object -First 1
if ($dumpbin) {
  $present = @{}
  Get-ChildItem $stage -Filter *.dll | ForEach-Object { $present[$_.Name.ToLower()] = $true }
  $missing = @()
  foreach ($bin in @(Get-ChildItem $stage -Filter *.dll) + @(Get-Item "$stage\cullimingo.exe")) {
    $deps = & $dumpbin.FullName /nologo /dependents $bin.FullName |
      Where-Object { $_ -match '^\s+(\S+\.dll)\s*$' } | ForEach-Object { $Matches[1].ToLower() }
    foreach ($d in $deps) {
      if ($present[$d]) { continue }
      if ($d -like 'api-ms-win-*' -or $d -like 'ext-ms-*') { continue }
      # The jni plugin (pulled in by a dependency, used only on Android) links
      # the JVM, which it loads only when a JVM is started — never here.
      if ($bin.Name -eq 'dartjni.dll' -and $d -eq 'jvm.dll') { continue }
      if (Test-Path (Join-Path $env:SystemRoot "System32\$d")) { continue }
      $missing += "$($bin.Name) -> $d"
    }
  }
  if ($missing) { Fail ("unresolved imports:`n" + ($missing -join "`n")) }
  'all imports resolve'
}

$dist = Join-Path $OutDir 'out'
New-Item -ItemType Directory $dist | Out-Null
$base = "Cullimingo_${version}_x64"
$icon = Resolve-Path windows\runner\resources\app_icon.ico

# --- portable zip ------------------------------------------------------------
Compress-Archive -Path $stage -DestinationPath (Join-Path $dist "$base-portable.zip") -CompressionLevel Optimal

# --- NSIS (per user) ---------------------------------------------------------
# Uninstall list: every staged file, then its folders deepest first.
$stageFull = (Resolve-Path $stage).Path
$lines = [Collections.Generic.List[string]]::new()
foreach ($f in Get-ChildItem $stageFull -Recurse -File) {
  $lines.Add("  Delete `"`$INSTDIR\$($f.FullName.Substring($stageFull.Length + 1))`"")
}
foreach ($d in Get-ChildItem $stageFull -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending) {
  $lines.Add("  RMDir `"`$INSTDIR\$($d.FullName.Substring($stageFull.Length + 1))`"")
}
$uninstallList = Join-Path (Resolve-Path $work).Path 'uninstall_files.nsh'
[IO.File]::WriteAllLines($uninstallList, $lines)
& makensis /V2 "/DVERSION=$numeric" "/DSOURCE=$stageFull" "/DICON=$icon" "/DUNINSTALL_LIST=$uninstallList" `
  "/DOUTFILE=$((Resolve-Path $dist).Path)\$base-setup.exe" windows\packaging\cullimingo.nsi
if ($LASTEXITCODE -ne 0) { Fail "makensis failed ($LASTEXITCODE)" }

# --- MSI (per machine) -------------------------------------------------------
& wix build -arch x64 -d "Version=$numeric" -d "SourceDir=$stageFull" -d "IconPath=$icon" `
  -o (Join-Path $dist "$base.msi") windows\packaging\Cullimingo.wxs
if ($LASTEXITCODE -ne 0) { Fail "wix build failed ($LASTEXITCODE)" }
Get-ChildItem $dist -Filter *.wixpdb | Remove-Item

# --- checksums ---------------------------------------------------------------
$text = ''
foreach ($f in Get-ChildItem $dist -File | Sort-Object Name) {
  $text += "{0}  {1}`n" -f (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower(), $f.Name
  '{0}: {1:N1} MB' -f $f.Name, ($f.Length / 1MB)
}
[IO.File]::WriteAllText((Join-Path (Resolve-Path $dist).Path 'SHA256SUMS-windows.txt'), $text)
$text
"downloads in $dist"
