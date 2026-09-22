#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="$ROOT/channels/seed"
for tool in mamba jq; do command -v "$tool" >/dev/null || { echo "error: required tool not found: $tool" >&2; exit 1; }; done
for subdir in linux-64 noarch; do [[ -f "$CHANNEL/$subdir/repodata.json" ]] || { echo "error: missing $subdir repodata" >&2; exit 1; }; done
expected_count="$(grep -c '^' "$ROOT/seed-packages.tsv")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CONDA_PKGS_DIRS="$tmp/pkgs" mamba create --prefix "$tmp/prefix" --dry-run --json --offline --override-channels --channel "file://$CHANNEL" --platform linux-64 gcc gxx binutils sysroot_linux-64 make gnuconfig >"$tmp/result.json"
jq -e '.success == true' "$tmp/result.json" >/dev/null || { echo 'error: offline local-channel solve failed' >&2; exit 1; }
resolved_count="$(jq '.actions.LINK | length' "$tmp/result.json")"
[[ "$resolved_count" == "$expected_count" ]] || { echo "error: expected $expected_count packages, resolved $resolved_count" >&2; exit 1; }
declare -A required=([gcc]=1 [gxx]=1 [binutils]=1 [sysroot_linux-64]=1 [make]=1 [gnuconfig]=1)
while IFS= read -r name; do unset 'required[$name]'; done < <(jq -r '.actions.LINK[].name' "$tmp/result.json")
if ((${#required[@]})); then echo "error: missing required packages: ${!required[*]}" >&2; exit 1; fi
while IFS= read -r url; do [[ "$url" == "file://$CHANNEL/"* ]] || { echo "error: package came from outside local channel: $url" >&2; exit 1; }; done < <(jq -r '.actions.LINK[].url // ""' "$tmp/result.json")
echo "offline local-channel solve: OK ($resolved_count packages)"
