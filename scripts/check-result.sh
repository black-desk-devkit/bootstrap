#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="$ROOT/channels/result"
for tool in mamba jq; do command -v "$tool" >/dev/null || { echo "error: required tool not found: $tool" >&2; exit 1; }; done
for subdir in linux-64 noarch; do [[ -f "$CHANNEL/$subdir/repodata.json" ]] || { echo "error: missing $subdir repodata" >&2; exit 1; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CONDA_PKGS_DIRS="$tmp/pkgs" mamba create --prefix "$tmp/prefix" --dry-run --json --offline --override-channels --channel "file://$CHANNEL" --strict-channel-priority --platform linux-64 sysroot_linux-64 gcc gxx binutils make gnuconfig >"$tmp/result.json"
jq -e '.success == true' "$tmp/result.json" >/dev/null || { echo 'error: result-only solve failed' >&2; exit 1; }
expected_names=$'binutils\ngcc\ngcc-toolchain\ngnuconfig\ngxx\nmake\nsysroot_linux-64\ntzdata'
actual_names="$(jq -r '.actions.LINK[].name' "$tmp/result.json" | sort -u)"
[[ "$actual_names" == "$expected_names" ]] || { echo "error: expected package set [$expected_names], got [$actual_names]" >&2; exit 1; }
while IFS=$'\t' read -r name channel_url; do channel_url="${channel_url%/}"; [[ "$channel_url" == "file://$CHANNEL" ]] || { echo "error: $name came from outside result channel: $channel_url" >&2; exit 1; }; done < <(jq -r '.actions.LINK[] | [.name, (.channel // .url // "")] | @tsv' "$tmp/result.json")
echo "result-only tool interface solve: OK ($(jq '.actions.LINK | length' "$tmp/result.json") packages)"
