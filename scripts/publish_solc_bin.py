#!/usr/bin/env python3
"""
Merge a newly-built solc binary into the cumulative, svm-rs-compatible
`list.json` for one Android architecture.

svm-rs's `Releases` struct (svm-rs/src/releases.rs) expects:
{
  "builds": [
    {"version": "0.8.18", "sha256": "0x<hex>", "path": "<filename>", "prerelease": null}
  ],
  "releases": {
    "0.8.18": "<filename>"
  }
}

This script is idempotent: re-running it for a version that's already present
just overwrites that version's entry (useful if you rebuild the same version).

Usage:
    publish_solc_bin.py --version 0.8.18 --binary path/to/solc \
        --list-json android/aarch64/list.json --commit-hash 87f61d96
"""
import argparse
import hashlib
import json
import pathlib
import sys


def sha256_hex(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return "0x" + h.hexdigest()


def load_releases(list_json: pathlib.Path) -> dict:
    if list_json.exists():
        with open(list_json) as f:
            return json.load(f)
    return {"builds": [], "releases": {}}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="solc version, e.g. 0.8.18")
    ap.add_argument("--binary", required=True, help="path to the built solc binary")
    ap.add_argument("--list-json", required=True, help="path to this arch's list.json (created if missing)")
    ap.add_argument("--commit-hash", required=True, help="short (8-char) solidity commit hash, as shown in `solc --version`")
    ap.add_argument("--artifact-name", help="override the published filename (default: solc-v<version>+commit.<hash>)")
    args = ap.parse_args()

    binary_path = pathlib.Path(args.binary)
    list_json_path = pathlib.Path(args.list_json)
    if not binary_path.is_file():
        print(f"ERROR: binary not found: {binary_path}", file=sys.stderr)
        return 1

    artifact_name = args.artifact_name or f"solc-v{args.version}+commit.{args.commit_hash}"
    checksum = sha256_hex(binary_path)

    releases = load_releases(list_json_path)

    # Drop any existing entry for this exact version (idempotent re-publish)
    releases["builds"] = [b for b in releases["builds"] if b["version"] != args.version]
    releases["builds"].append({
        "version": args.version,
        "sha256": checksum,
        "path": artifact_name,
        "prerelease": None,
    })
    # Keep builds sorted by version for readability (best-effort string sort is
    # fine here since callers publish in version order; not semver-exact).
    releases["releases"][args.version] = artifact_name

    list_json_path.parent.mkdir(parents=True, exist_ok=True)
    with open(list_json_path, "w") as f:
        json.dump(releases, f, indent=2, sort_keys=False)
        f.write("\n")

    # Copy/rename the binary next to list.json under its published name
    published_path = list_json_path.parent / artifact_name
    published_path.write_bytes(binary_path.read_bytes())
    published_path.chmod(0o755)

    print(f"Published {published_path} (sha256={checksum})")
    print(f"Updated {list_json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

