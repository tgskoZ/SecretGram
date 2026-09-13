"""Package current files, restoring original Unix modes and symlinks on Windows."""
from pathlib import Path
import argparse, copy, hashlib, re, zipfile, os

parser = argparse.ArgumentParser()
parser.add_argument('--original', required=True, type=Path, help='Original Jerkgram source ZIP')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if os.name == 'nt':
    root = Path('\\\\?\\' + str(root))
destination = root / 'dist/SecretGram-iOS-source.zip'
destination.parent.mkdir(exist_ok=True)

def renamed(value):
    return re.sub('jerkgram', lambda m: 'SECRETGRAM' if m[0].isupper() else 'secretgram' if m[0].islower() else 'SecretGram', value, flags=re.I)

seen = set()
links = 0
with zipfile.ZipFile(args.original) as original, zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as out:
    for item in original.infolist():
        relative = renamed('/'.join(item.filename.split('/')[1:]))
        if not relative:
            continue
        seen.add(relative.rstrip('/'))
        info = copy.copy(item)
        info.filename = 'SecretGram-iOS/' + relative
        if item.is_dir():
            data = b''
        elif (item.external_attr >> 16) & 0o170000 == 0o120000:
            data = original.read(item)
            links += 1
        else:
            data = (root / relative).read_bytes()
        out.writestr(info, data)
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if relative in seen or relative.startswith(('.git/', 'dist/')) or '__pycache__' in path.parts:
            continue
        if path.name in ('rebrand_secretgram.py', 'finish_secretgram.py', 'prepare_secretgram_delivery.py', 'secretgram-configuration.json'):
            continue
        info = zipfile.ZipInfo('SecretGram-iOS/' + relative)
        info.create_system = 3
        info.external_attr = (0o100755 if path.suffix == '.sh' else 0o100644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        out.writestr(info, path.read_bytes())
with zipfile.ZipFile(destination) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(set(archive.namelist()))
    assert sum(((i.external_attr >> 16) & 0o170000) == 0o120000 for i in archive.infolist()) == links
    assert 'SecretGram-iOS/submodules/SettingsUI/Sources/SecretGram/SecretGramPluginsController.swift' in archive.namelist()
digest = hashlib.file_digest(destination.open('rb'), 'sha256').hexdigest()
destination.with_suffix('.zip.sha256').write_text(digest + '  ' + destination.name + '\n')
print(f'{destination}\n{destination.stat().st_size} bytes; {links} Unix symlinks preserved\nSHA-256 {digest}')
