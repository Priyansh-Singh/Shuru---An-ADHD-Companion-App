#!/usr/bin/env python3
"""Writes source.json, the SideStore / AltStore source for Shuru.

Run by the build workflow after Shuru.ipa is packaged. Every build gets a new
build number (the workflow run number), so SideStore sees it as an update.
"""
import datetime
import json
import os
import plistlib
import re
import sys
import zipfile

repo = os.environ["GITHUB_REPOSITORY"]
build = os.environ["BUILD_NUMBER"]
ipa = sys.argv[1] if len(sys.argv) > 1 else "Shuru.ipa"
notes = os.environ.get("RELEASE_NOTES", "").strip().splitlines()

# Every build gets its own version (0.1.<build>), not only its own build number,
# because some SideStore versions only compare the version string for updates.
version = os.environ.get("APP_VERSION", "").strip()
if not version:
    with open("project.yml", encoding="utf-8") as f:
        m = re.search(r'MARKETING_VERSION:\s*"?([0-9]+)\.([0-9]+)', f.read())
    version = f"{m.group(1)}.{m.group(2)}.{build}" if m else f"0.1.{build}"

# Declare the app's privacy permissions (e.g. location) so SideStore shows them and doesn't refuse the install.
privacy = {}
with zipfile.ZipFile(ipa) as z:
    plist_name = next((n for n in z.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)), None)
    if plist_name:
        info = plistlib.loads(z.read(plist_name))
        privacy = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}

base = f"https://github.com/{repo}"
raw = f"https://raw.githubusercontent.com/{repo}/main"
icon = f"{raw}/Shuru/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png"
tint = "#F0784A"

description = (
    "A to-do app for ADHD brains, built around one idea: starting is the hard part.\n\n"
    "• Now shows one next thing over a slowly moving orb. Hold it to finish.\n"
    "• Routines are if–then chains: “When I get home → bath → dinner → study”.\n"
    "• Calendar shows what you did on past days and what’s planned ahead.\n"
    "• Hours makes time visible: log what each hour went to.\n"
    "• Brain dump, tokens and rewards, and a pause before scrolling Instagram.\n\n"
    "Everything stays on your phone. No account, no server."
)

source = {
    "name": "Shuru",
    "identifier": "io.github.priyanshsingh.shuru.source",
    "subtitle": "One thing at a time.",
    "description": "Builds of Shuru (शुरू), straight from GitHub.",
    "iconURL": icon,
    "website": base,
    "tintColor": tint,
    "apps": [
        {
            "name": "Shuru",
            "bundleIdentifier": "io.github.priyanshsingh.shuru",
            "developerName": "Priyansh Singh",
            "subtitle": "A one-thing-at-a-time to-do app for ADHD.",
            "localizedDescription": description,
            "iconURL": icon,
            "tintColor": tint,
            "category": "utilities",
            "versions": [
                {
                    "version": version,
                    "buildVersion": build,
                    "marketingVersion": f"{version} ({build})",
                    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "localizedDescription": notes[0] if notes else "New build.",
                    "downloadURL": f"{base}/releases/download/latest/Shuru.ipa",
                    "size": os.path.getsize(ipa),
                    "minOSVersion": "17.0",
                }
            ],
            "appPermissions": {
                "entitlements": [],
                "privacy": privacy,
            },
        }
    ],
    "news": [],
}

with open("source.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(f"source.json: Shuru {version} ({build}), {os.path.getsize(ipa)} bytes")
