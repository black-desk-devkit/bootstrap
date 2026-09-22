#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/seed-packages.tsv"
CHANNEL="$ROOT/channels/seed"

for tool in curl sha256sum rattler-index; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "$tool" >&2
    exit 1
  fi
done

if [[ ! -f "$MANIFEST" ]]; then
  printf 'error: missing seed manifest: %s\n' "$MANIFEST" >&2
  exit 1
fi

mapfile -t manifest_rows < "$MANIFEST"
if ((${#manifest_rows[@]} == 0)); then
  printf 'error: seed manifest is empty: %s\n' "$MANIFEST" >&2
  exit 1
fi

mkdir -p "$CHANNEL/linux-64" "$CHANNEL/noarch"

for row in "${manifest_rows[@]}"; do
  IFS=$'\t' read -r subdir fn url expected_sha256 expected_size <<<"$row"
  if [[ -z "$subdir" || -z "$fn" || -z "$url" || -z "$expected_sha256" || -z "$expected_size" ]]; then
    printf 'error: malformed manifest row: %s\n' "$row" >&2
    exit 1
  fi
  if [[ "$subdir" != linux-64 && "$subdir" != noarch ]]; then
    printf 'error: unsupported subdir in manifest: %s\n' "$subdir" >&2
    exit 1
  fi

  destination="$CHANNEL/$subdir/$fn"
  partial="$destination.part"

  verify_archive() {
    local actual_sha256 actual_size
    actual_sha256="$(sha256sum -- "$destination" | awk '{print $1}')"
    actual_size="$(stat -c %s -- "$destination")"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
      printf 'error: SHA-256 mismatch for %s/%s\n' "$subdir" "$fn" >&2
      printf '  expected: %s\n  actual:   %s\n' "$expected_sha256" "$actual_sha256" >&2
      return 1
    fi
    if [[ "$actual_size" != "$expected_size" ]]; then
      printf 'error: size mismatch for %s/%s\n' "$subdir" "$fn" >&2
      printf '  expected: %s\n  actual:   %s\n' "$expected_size" "$actual_size" >&2
      return 1
    fi
  }

  if [[ -f "$destination" ]]; then
    verify_archive
    printf 'verified  %s/%s\n' "$subdir" "$fn"
  else
    rm -f -- "$partial"
    if ! curl --fail --location --retry 3 --silent --show-error \
      --output "$partial" "$url"; then
      rm -f -- "$partial"
      printf 'error: download failed for %s\n' "$url" >&2
      exit 1
    fi
    mv -- "$partial" "$destination"
    verify_archive
    printf 'downloaded %s/%s\n' "$subdir" "$fn"
  fi
done

rattler-index fs "$CHANNEL" --target-platform linux-64
rattler-index fs "$CHANNEL" --target-platform noarch
printf 'seed channel ready: %s\n' "$CHANNEL"
