#!/usr/bin/env python3
"""The in-app update manifest (`latest.json`) of one release.

    update_manifest.py make   --version V --tag T --repo OWNER/NAME --key KEY.pem
                              --dir DIST --out latest.json
    update_manifest.py verify --manifest latest.json --pub BASE64 --version V
                              --dir DIST [--expect KEY ...]

`make` signs every self-updatable package found in DIST with the release's
Ed25519 update key (the `UPDATE_SIGNING_KEY` secret, PEM) and writes the
manifest the app reads (lib/core/update/update_manifest.dart): the version and,
per package key, the file's name, size, SHA-256, download URL and signature.

Each signature covers one line-based statement, so a signed package can't be
replayed as another version, another package kind or another file:

    cullimingo-update-v1\\n<version>\\n<key>\\n<file name>\\n<sha256 hex>\\n

`verify` re-checks a manifest against the files with the public key the app
carries (raw 32 bytes, base64) — release.yml runs it before publishing.
Signing and verifying use `openssl pkeyutl -rawin` (OpenSSL 3), so the
release runner needs nothing extra. Not code signing: the downloads stay
unsigned for the OS; this only lets the app trust what it downloads.
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile

# Package key -> file name pattern ({v} = version). The keys are what the app
# asks for (InstallKind.manifestKey); keep both sides in sync.
PACKAGES = {
    'windows-x64-nsis': 'Cullimingo_{v}_x64-setup.exe',
    'windows-x64-msi': 'Cullimingo_{v}_x64.msi',
    'macos-arm64-dmg': 'Cullimingo-arm64.dmg',
    'macos-x64-dmg': 'Cullimingo-x86_64.dmg',
    'linux-x64-appimage': 'Cullimingo-x86_64.AppImage',
}

# DER prefix of an Ed25519 SubjectPublicKeyInfo; the raw key follows.
_ED25519_SPKI_PREFIX = bytes.fromhex('302a300506032b6570032100')


def statement(version, key, name, sha256):
    return f'cullimingo-update-v1\n{version}\n{key}\n{name}\n{sha256}\n'.encode()


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def openssl(*args, data=None):
    r = subprocess.run(['openssl', *args], input=data, capture_output=True)
    return r


def sign(key_pem, message):
    with tempfile.NamedTemporaryFile(delete=False) as m:
        m.write(message)
    try:
        r = openssl('pkeyutl', '-sign', '-rawin', '-inkey', key_pem, '-in', m.name)
        if r.returncode != 0:
            sys.exit(f'signing failed: {r.stderr.decode()}')
        return base64.b64encode(r.stdout).decode()
    finally:
        os.unlink(m.name)


def verify_sig(pub_b64, message, sig_b64):
    raw = base64.b64decode(pub_b64)
    if len(raw) != 32:
        sys.exit('public key must be 32 raw bytes')
    with tempfile.TemporaryDirectory() as d:
        der = os.path.join(d, 'pub.der')
        with open(der, 'wb') as f:
            f.write(_ED25519_SPKI_PREFIX + raw)
        pem = os.path.join(d, 'pub.pem')
        if openssl('pkey', '-pubin', '-inform', 'DER', '-in', der, '-out', pem).returncode:
            sys.exit('bad public key')
        msg = os.path.join(d, 'msg')
        with open(msg, 'wb') as f:
            f.write(message)
        sig = os.path.join(d, 'sig')
        with open(sig, 'wb') as f:
            f.write(base64.b64decode(sig_b64))
        r = openssl('pkeyutl', '-verify', '-pubin', '-rawin', '-inkey', pem,
                    '-in', msg, '-sigfile', sig)
        return r.returncode == 0


def make(a):
    packages = {}
    for key, pattern in PACKAGES.items():
        name = pattern.format(v=a.version)
        path = os.path.join(a.dir, name)
        if not os.path.exists(path):
            print(f'skip {key}: no {name}')
            continue
        digest = sha256_of(path)
        packages[key] = {
            'name': name,
            'size': os.path.getsize(path),
            'sha256': digest,
            'url': f'https://github.com/{a.repo}/releases/download/{a.tag}/{name}',
            'signature': sign(a.key, statement(a.version, key, name, digest)),
        }
        print(f'signed {key}: {name}')
    if not packages:
        sys.exit('no packages to sign')
    with open(a.out, 'w') as f:
        json.dump({'format': 1, 'version': a.version, 'packages': packages}, f,
                  indent=2)
        f.write('\n')


def verify(a):
    with open(a.manifest) as f:
        m = json.load(f)
    ok = m.get('format') == 1 and m.get('version') == a.version
    if not ok:
        print(f'manifest format/version mismatch: {m.get("format")} {m.get("version")}')
    for key, p in m.get('packages', {}).items():
        expected = PACKAGES.get(key, '').format(v=a.version)
        path = os.path.join(a.dir, p['name'])
        good = (p['name'] == expected and os.path.exists(path)
                and os.path.getsize(path) == p['size']
                and sha256_of(path) == p['sha256']
                and verify_sig(a.pub, statement(a.version, key, p['name'], p['sha256']),
                               p['signature']))
        print(f'{"ok  " if good else "FAIL"} {key}: {p["name"]}')
        ok &= good
    for key in a.expect or []:
        if key not in m.get('packages', {}):
            print(f'FAIL missing {key}')
            ok = False
    sys.exit(0 if ok else 1)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    mk = sub.add_parser('make')
    for flag in ('--version', '--tag', '--repo', '--key', '--dir', '--out'):
        mk.add_argument(flag, required=True)
    vf = sub.add_parser('verify')
    for flag in ('--manifest', '--pub', '--version', '--dir'):
        vf.add_argument(flag, required=True)
    vf.add_argument('--expect', nargs='*')
    a = p.parse_args()
    make(a) if a.cmd == 'make' else verify(a)


if __name__ == '__main__':
    main()
