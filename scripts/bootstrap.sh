#!/usr/bin/env bash
set -euo pipefail

# Run the complete bootstrap:
#   seed -> dirty toolchain -> result toolchain -> result self-host rebuild
#
# The script deliberately publishes each stage into its channel before the
# next stage resolves dependencies.  This keeps the dependency graph the same
# as a clean invocation of rattler-build rather than relying on stale output
# directories as implicit channels.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/output"
export XDG_CACHE_HOME="$ROOT/output/cache"

reset_generated_state() {
  # These directories contain only downloaded/generated bootstrap state. The
  # seed manifest and all recipes remain outside this reset set.
  rm -rf -- "$ROOT/channels/seed" "$ROOT/channels/dirty" \
    "$ROOT/channels/result" "$ROOT/output"
  mkdir -p "$ROOT/channels/seed" "$ROOT/channels/dirty" \
    "$ROOT/channels/result" "$ROOT/output" "$XDG_CACHE_HOME"
  touch "$ROOT/channels/seed/.gitkeep" "$ROOT/channels/dirty/.gitkeep" \
    "$ROOT/channels/result/.gitkeep"
}

reset_generated_state

if [[ -n "${RATTLER_BUILD:-}" ]]; then
  RBT="$RATTLER_BUILD"
elif command -v rattler-build >/dev/null 2>&1; then
  RBT="$(command -v rattler-build)"
else
  printf 'error: rattler-build not found in PATH; set RATTLER_BUILD to its absolute path\n' >&2
  exit 1
fi

for tool in "$RBT" rattler-index mamba jq; do
  if [[ "$tool" == */* ]]; then
    [[ -x "$tool" ]] || { printf 'error: executable not found: %s\n' "$tool" >&2; exit 1; }
  elif ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "$tool" >&2
    exit 1
  fi
done

build() {
  local recipe="$1" variant="$2" output="$3"
  shift 3
  local -a variant_args=()
  [[ -z "$variant" ]] || variant_args=(--variant-config "$ROOT/variants/$variant.yaml")
  "$RBT" build \
    --recipe "$ROOT/recipes/$recipe/recipe.yaml" \
    --target-platform linux-64 \
    --channel-priority strict \
    "${variant_args[@]}" \
    --output-dir "$BUILD_ROOT/$output" \
    "$@"
}

publish() {
  local output="$1" channel="$2"
  mkdir -p "$ROOT/channels/$channel/linux-64" "$ROOT/channels/$channel/noarch"
  compgen -G "$BUILD_ROOT/$output/linux-64/*.conda" >/dev/null && \
    cp "$BUILD_ROOT/$output"/linux-64/*.conda "$ROOT/channels/$channel/linux-64/"
  compgen -G "$BUILD_ROOT/$output/noarch/*.conda" >/dev/null && \
    cp "$BUILD_ROOT/$output"/noarch/*.conda "$ROOT/channels/$channel/noarch/"
  rattler-index fs "$ROOT/channels/$channel" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/$channel" --target-platform noarch >/dev/null
}

publish_seed_tzdata() {
  local -a archives
  mapfile -t archives < <(compgen -G "$ROOT/channels/seed/noarch/tzdata-*.conda" || true)
  ((${#archives[@]} == 1)) || {
    printf 'error: seed channel does not contain tzdata\n' >&2
    exit 1
  }
  mkdir -p "$ROOT/channels/dirty/noarch" "$ROOT/channels/result/noarch"
  cp "${archives[0]}" "$ROOT/channels/dirty/noarch/"
  cp "${archives[0]}" "$ROOT/channels/result/noarch/"
  rattler-index fs "$ROOT/channels/dirty" --target-platform noarch >/dev/null
  rattler-index fs "$ROOT/channels/result" --target-platform noarch >/dev/null
}

"$ROOT/scripts/fetch-seed.sh"
"$ROOT/scripts/check-seed.sh"
publish_seed_tzdata

# Dirty stage: seed sysroot and seed compiler interfaces.
build gcc-toolchain dirty dirty/gcc-toolchain --channel "$ROOT/channels/seed"
publish dirty/gcc-toolchain dirty
build gcc-aliases '' dirty/gcc-aliases --channel "$ROOT/channels/dirty" --channel "$ROOT/channels/seed"
publish dirty/gcc-aliases dirty
build binutils dirty dirty/binutils --channel "$ROOT/channels/dirty" --channel "$ROOT/channels/seed"
publish dirty/binutils dirty
build gnuconfig '' dirty/gnuconfig
publish dirty/gnuconfig dirty
build make dirty dirty/make --channel "$ROOT/channels/dirty" --channel "$ROOT/channels/seed"
publish dirty/make dirty

# Result stage: first create and publish the Rocky 8.10 sysroot, then rebuild
# the toolchain against dirty interfaces and the result sysroot.  The seed
# channel is deliberately not available here: result must not silently fall
# back to seed packages.
build sysroot result result/sysroot --channel "$ROOT/channels/result"
publish result/sysroot result
build gcc-toolchain result result/gcc-toolchain --channel "$ROOT/channels/dirty" --channel "$ROOT/channels/result"
publish result/gcc-toolchain result
build gcc-aliases '' result/gcc-aliases --channel "$ROOT/channels/result" --channel "$ROOT/channels/dirty"
publish result/gcc-aliases result
build binutils result result/binutils --channel "$ROOT/channels/result" --channel "$ROOT/channels/dirty"
publish result/binutils result
build gnuconfig '' result/gnuconfig
publish result/gnuconfig result
build make result result/make --channel "$ROOT/channels/result" --channel "$ROOT/channels/dirty"
publish result/make result

"$ROOT/scripts/check-result.sh"

# Self-host stage: rebuild every result package using result as the bootstrap
# channel.  Each package is published back into result immediately so later
# packages consume the newly rebuilt interfaces.  No dirty or seed channel is
# visible in this stage.
build sysroot result result-selfhost/sysroot --channel "$ROOT/channels/result"
publish result-selfhost/sysroot result
build gcc-toolchain result result-selfhost/gcc-toolchain --channel "$ROOT/channels/result"
publish result-selfhost/gcc-toolchain result
build gcc-aliases '' result-selfhost/gcc-aliases --channel "$ROOT/channels/result"
publish result-selfhost/gcc-aliases result
build binutils result result-selfhost/binutils --channel "$ROOT/channels/result"
publish result-selfhost/binutils result
build gnuconfig '' result-selfhost/gnuconfig
publish result-selfhost/gnuconfig result
build make result result-selfhost/make --channel "$ROOT/channels/result"
publish result-selfhost/make result

"$ROOT/scripts/check-result.sh"
printf 'bootstrap complete: %s\n' "$ROOT/channels/result"
