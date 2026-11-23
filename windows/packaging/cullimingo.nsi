; Per-user installer for the unsigned Windows build (no administrator rights).
; Built by tool/bundle_windows.ps1, which passes:
;   /DVERSION=<x.y.z>  /DSOURCE=<staged Cullimingo folder>  /DOUTFILE=<setup.exe>
;   /DICON=<app_icon.ico>  /DUNINSTALL_LIST=<generated .nsh>
; The list holds one Delete/RMDir per staged file and folder, so the
; uninstaller removes exactly what it installed, never the whole folder a
; user may have picked.
Unicode true
SetCompressor /SOLID lzma
ManifestDPIAware true

!include "MUI2.nsh"

Name "Cullimingo"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\Cullimingo"
InstallDirRegKey HKCU "Software\Cullimingo" "InstallDir"
BrandingText "Cullimingo ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Cullimingo"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "Cullimingo installer"
VIAddVersionKey "CompanyName" "Niels Franke"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 Niels Franke"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\cullimingo.exe"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "German"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cullimingo"

Section "Cullimingo"
  SetOutPath "$INSTDIR"
  File /r "${SOURCE}\*.*"
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateShortcut "$SMPROGRAMS\Cullimingo.lnk" "$INSTDIR\cullimingo.exe"

  WriteRegStr HKCU "Software\Cullimingo" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Cullimingo"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Niels Franke"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\cullimingo.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/nielsfranke/Cullimingo"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\Cullimingo.lnk"
  !include "${UNINSTALL_LIST}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\Cullimingo"
  ; Settings, the catalog and the preview cache under %APPDATA% /
  ; %LOCALAPPDATA%\cc.nielsbox\Cullimingo stay, like on macOS and Linux.
SectionEnd
