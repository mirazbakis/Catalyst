#!/usr/bin/env python3
"""Update source.json with the freshly built nightly IPA (size, sha256, date, version).

Usage: python3 scripts/catalyst/update_source.py --ipa Catalyst.ipa --version 0.7.0 --build 0700 --commit abc1234
"""
import argparse, datetime, hashlib, json, pathlib

p = argparse.ArgumentParser()
p.add_argument("--ipa", required=True)
p.add_argument("--version", required=True)
p.add_argument("--build", required=True)
p.add_argument("--commit", required=True)
p.add_argument("--source", default="source.json")
a = p.parse_args()

ipa = pathlib.Path(a.ipa)
sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

src_path = pathlib.Path(a.source)
src = json.loads(src_path.read_text())
app = next(x for x in src["apps"] if x["bundleIdentifier"] == "com.mirazbakis.Catalyst")

release = {
    "version": a.version,
    "buildVersion": a.build,
    "date": now,
    "localizedDescription": f"Nightly build {a.commit}.",
    "downloadURL": "https://github.com/mirazbakis/Catalyst/releases/download/nightly/Catalyst.ipa",
    "size": ipa.stat().st_size,
    "sha256": sha,
    "minOSVersion": "15.0",
}
app["releaseChannels"] = [{"track": "nightly", "releases": [release]}]
app["versions"] = [release]
src_path.write_text(json.dumps(src, indent=2, ensure_ascii=False) + "\n")
print(f"source.json -> {a.version} ({a.build}) {a.commit}, {release['size']} bytes")
