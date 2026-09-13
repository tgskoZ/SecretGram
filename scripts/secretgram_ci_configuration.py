"""Generate the unsigned CI identity without changing the upstream sample config."""
import json
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config = json.loads((root / 'build-system/appstore-configuration.json').read_text())
api_id, api_hash = os.getenv('TELEGRAM_API_ID'), os.getenv('TELEGRAM_API_HASH')
if bool(api_id) != bool(api_hash):
    raise SystemExit('Set both TELEGRAM_API_ID and TELEGRAM_API_HASH, or neither.')
if api_id:
    if not api_id.isdecimal() or int(api_id) <= 0:
        raise SystemExit('TELEGRAM_API_ID must be a positive integer.')
    if len(api_hash) != 32 or any(c not in '0123456789abcdefABCDEF' for c in api_hash):
        raise SystemExit('TELEGRAM_API_HASH must contain 32 hexadecimal characters.')
    config.update(api_id=api_id, api_hash=api_hash)
else:
    print('Using the public Telegram API sample configuration bundled with the supplied sources.')
config.update(bundle_id='app.secretgram.ios', team_id='SECRETGRAM', app_specific_url_scheme='secretgram',
              is_internal_build='false', is_appstore_build='false', appstore_id='0',
              app_center_id='0', premium_iap_product_id='', enable_siri=False, enable_icloud=False)
destination = root / 'build-system/secretgram-configuration.json'
destination.write_text(json.dumps(config, indent=2) + '\n')
print('Generated unsigned SecretGram configuration (credentials omitted from logs).')
