"""Rebuild Cat Empire payloads while preserving unrelated games and embedded Fluent."""
import base64
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PAYLOADS = {
    105596644794991: {
        "raw_file": "UntitledDefense105/Main.lua",
        "default_key": 211,
    },
    79073563583903: {
        "raw_file": "ReAdventures790/Main.lua",
        "default_key": 197,
    },
    93466613073564: {
        "raw_file": "ScopedV2/Main.lua",
        "default_key": 173,
    },
}

def payload(spec):
    raw_file = spec.get("raw_file")
    if raw_file:
        return (ROOT / raw_file).read_text().encode()
    parts = []
    for name in spec["parts"]:
        parts.append("local " + name + "=(function()\n" + (ROOT / spec["folder"] / (name + ".lua")).read_text() + "\nend)()\n")
    return ("".join(parts) + spec["return"]).encode()

def crypt(data, key):
    out = bytearray()
    for byte in data:
        key = (key * 73 + 41) % 256
        out.append(byte ^ key)
    return bytes(out)

def encoded_entry(place_id, spec, key):
    encoded = base64.b64encode(crypt(payload(spec), key)).decode()
    chunks = ",".join('"' + encoded[i:i+12000] + '"' for i in range(0, len(encoded), 12000))
    return "[" + str(place_id) + "]={{" + chunks + "}," + str(key) + "}"

def replace_or_insert(source, place_id, spec):
    table_pattern = re.compile(r'(\[' + re.escape(str(place_id)) + r'\]=)\{\{(.*?)\},(\d+)\}')
    direct_pattern = re.compile(r'(a\[' + re.escape(str(place_id)) + r'\]=)\{\{(.*?)\},(\d+)\}')

    match = direct_pattern.search(source)
    if match:
        key = int(match[3])
        replacement = "a" + encoded_entry(place_id, spec, key)
        return source[:match.start()] + replacement + source[match.end():]

    match = table_pattern.search(source)
    if match:
        key = int(match[3])
        replacement = encoded_entry(place_id, spec, key)
        return source[:match.start()] + replacement + source[match.end():]

    key = spec["default_key"]
    entry = "a" + encoded_entry(place_id, spec, key)
    marker = ";local b="
    if marker not in source:
        raise ValueError("Could not find loader payload insertion point")
    return source.replace(marker, ";" + entry + marker, 1)


def build():
    path = ROOT / "Loader/Loader.lua"
    source = path.read_text()
    for place_id, spec in PAYLOADS.items():
        source = replace_or_insert(source, place_id, spec)
    path.write_text(source)

if __name__ == "__main__":
    build()
