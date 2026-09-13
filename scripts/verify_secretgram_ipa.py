"""Verify a device IPA before it is eligible for release; no signing claim."""
import argparse
import hashlib
import plistlib
import struct
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
args = parser.parse_args()
with zipfile.ZipFile(args.ipa) as archive:
    if archive.testzip() is not None:
        raise SystemExit('Corrupt IPA')
    names = archive.namelist()
    roots = [p for p in names if p.startswith('Payload/') and p.count('/') == 2 and p.endswith('.app/Info.plist')]
    if len(roots) != 1:
        raise SystemExit('Expected exactly one main .app under Payload/')
    plist = plistlib.loads(archive.read(roots[0]))
    if plist.get('CFBundleDisplayName') != 'SecretGram' or plist.get('CFBundleIdentifier') != 'app.secretgram.ios':
        raise SystemExit('Unexpected application identity')
    if 'iPhoneOS' not in plist.get('CFBundleSupportedPlatforms', []):
        raise SystemExit('Not a device IPA')
    executable = roots[0].removesuffix('Info.plist') + plist['CFBundleExecutable']
    header = archive.read(executable)[:32]
    if len(header) < 32 or struct.unpack('<II', header[:8]) != (0xfeedfacf, 0x0100000c):
        raise SystemExit('Expected an arm64 Mach-O executable')
    if any(p.endswith('embedded.mobileprovision') for p in names):
        raise SystemExit('Unsigned release must not contain a provisioning profile')
    print('Verified: SecretGram, iPhoneOS, arm64, no embedded provisioning profiles.')
with args.ipa.open('rb') as f:
    checksum = hashlib.file_digest(f, 'sha256').hexdigest()
args.ipa.with_suffix('.ipa.sha256').write_text(checksum + '  ' + args.ipa.name + '\n')
