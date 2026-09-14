from pathlib import Path
import json, re, plistlib
from PIL import Image
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
files = list((root / 'submodules/SettingsUI/Sources/SecretGram').glob('SecretGramPlugin*.swift'))
files += [root / 'tests/secretgram-plugins/main.swift']
for path in files:
    tree = parser.parse(path.read_bytes())
    assert not tree.root_node.has_error, f'Swift syntax error: {path}'
    print('Swift syntax:', path.relative_to(root))

count = 0
for base in ['Telegram', 'submodules']:
    for path in (root / base).rglob('*'):
        if not path.is_file() or path.suffix not in ('.swift', '.m', '.h', '.strings', '.plist'):
            continue
        if re.search(b'jerkgram', path.read_bytes(), re.I):
            raise AssertionError(f'Old branding: {path}')
        count += 1
print('Branding scan:', count, 'source/resource files')

build_source = (root / 'Telegram/BUILD').read_text(encoding='utf-8')
main_plist = build_source.split('name = "TelegramInfoPlist",', 1)[1].split('</plist>', 1)[0]
for key in ['CFBundleDisplayName', 'CFBundleName']:
    assert re.search(r'<key>' + key + r'</key>\s*<string>SecretGram</string>', main_plist), key

for name in ['Info.plist', 'InfoBazel.plist']:
    data = plistlib.loads((root / 'Telegram/Telegram-iOS' / name).read_bytes())
    assert data['CFBundleDisplayName'] == 'SecretGram'
    assert data['CFBundleName'] == 'SecretGram'
for path in (root / 'Telegram').rglob('Contents.json'):
    for entry in json.loads(path.read_bytes()).get('images', []):
        if 'filename' in entry:
            assert (path.parent / entry['filename']).exists(), str(path)
for path in (root / 'Telegram/Telegram-iOS').glob('SecretGram*.icon/icon.json'):
    config = json.loads(path.read_bytes())
    for group in config['groups']:
        for layer in group['layers']:
            png = path.parent / 'Assets' / layer['image-name']
            with Image.open(png) as image:
                assert image.size == (1024, 1024) and image.mode == 'RGB'
for path in (root / 'submodules').rglob('BUILD'):
    for module in re.findall(r'//submodules/(SecretGram[^/:]+)', path.read_text(encoding='utf-8')):
        assert (root / 'submodules' / module / 'BUILD').exists(), str(path)
assert 'secretgramPluginsController(context: context)' in (root / 'submodules/SettingsUI/Sources/GhostBase/GhostBaseSettingsController.swift').read_text(encoding='utf-8')
assert 'cronusk1809.workers.dev' not in (root / 'submodules/TelegramUI/Sources/AppDelegate.swift').read_text(encoding='utf-8')
print('Plists, icon references/dimensions, renamed module paths and plugin navigation: OK')
print('This is static validation only; Xcode build and Swift runtime tests require a Mac.')
