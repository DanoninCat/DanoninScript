"""Rebuild only the Re Adventures payload; preserve other games and Fluent."""
import base64
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r'(\[138271828389486\]=)\{\{(.*?)\},(\d+)\}')

def payload():
    parts = []
    for name in ('Core', 'UI', 'Entry'):
        parts.append('local ' + name + '=(function()\n' + (ROOT / 'ReAdventuresV2' / (name + '.lua')).read_text() + '\nend)()\n')
    return (''.join(parts) + 'return Entry(Core,UI)').encode()

def crypt(data, key):
    out = bytearray()
    for byte in data:
        key = (key * 73 + 41) % 256
        out.append(byte ^ key)
    return bytes(out)

def build():
    path = ROOT / 'Loader/Loader.lua'
    source = path.read_text()
    matches = list(PATTERN.finditer(source))
    if len(matches) != 1:
        raise ValueError('Expected exactly one Re Adventures payload')
    match = matches[0]
    key = int(match[3])
    encoded = base64.b64encode(crypt(payload(), key)).decode()
    chunks = ','.join('"' + encoded[i:i+12000] + '"' for i in range(0, len(encoded), 12000))
    replacement = match[1] + '{{' + chunks + '},' + str(key) + '}'
    path.write_text(source[:match.start()] + replacement + source[match.end():])

if __name__ == '__main__':
    build()
