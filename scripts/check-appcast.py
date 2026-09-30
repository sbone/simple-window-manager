"""Check that the feed matches the release and verify its Sparkle signature."""
import base64
import plistlib
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

feed, archive = map(Path, sys.argv[1:])
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
info = plistlib.loads(Path("Resources/Info.plist").read_bytes())
item = ET.parse(feed).find("./channel/item")
assert item is not None, "The update feed is empty"
assert item.findtext(sparkle + "version") == info["CFBundleVersion"], "Wrong build in feed"
assert item.findtext(sparkle + "shortVersionString") == info["CFBundleShortVersionString"], "Wrong version in feed"
enclosure = item.find("enclosure")
assert enclosure is not None, "Missing update download"
assert int(enclosure.attrib["length"]) == archive.stat().st_size, "Wrong archive size"
prefix = info["SUFeedURL"].removesuffix("/latest/download/appcast.xml")
expected = f"{prefix}/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.attrib["url"] == expected, "Wrong update URL"
signature = enclosure.attrib[sparkle + "edSignature"]
assert len(base64.b64decode(signature, validate=True)) == 64, "Invalid Ed25519 signature"
public_key = subprocess.check_output([
    ".build/artifacts/sparkle/Sparkle/bin/generate_keys", "-p",
], text=True).strip()
assert public_key == info["SUPublicEDKey"], "Sparkle signing key does not match the app"
subprocess.run([
    ".build/artifacts/sparkle/Sparkle/bin/sign_update", "--verify",
    str(archive), signature,
], check=True)
print("PASS: feed version, URL, size, and Sparkle update signature.")
