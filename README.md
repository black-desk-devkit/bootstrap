# GCC bootstrap workspace

This repository records a reproducible, `linux-64` GCC toolchain bootstrap. Its
goal is a local result channel containing a self-hosted compiler closure that
no longer needs conda-forge or the imported seed channel.

## Plan and current status

1. **Seed:** recreate the fixed conda-forge-derived compiler, binutils, and
   sysroot interfaces using `seed-packages.tsv`.
2. **Dirty toolchain:** build the GCC carrier against seed interfaces, expose it
   through `gcc`/`gxx`, then build the native binutils carrier with those
   interfaces. Publish all dirty-stage packages together.
3. **Result sysroot:** build the Rocky Linux 8.10-derived `sysroot_linux-64`
   package with the result variant. It installs under the result target
   triplet (`x86_64-pc-linux-gnu/sysroot`) and supplies the glibc 2.28
   deployment baseline. Its `tzdata` runtime dependency is pre-published into
   the result channel before any result package is built.
4. **Result toolchain:** run the same GCC, binutils, GNU Make, and gnuconfig
   recipes against the earlier stage interfaces and the published result
   sysroot. Strict channel priority selects dirty `gcc`, `gxx`, and `binutils`
   for the result carrier.

The seed is complete and verified. The GCC carrier, compiler aliases,
single-output native binutils, GNU Make, and gnuconfig have all been built and
tested end-to-end. Installing `gcc gxx binutils make gnuconfig
sysroot_linux-64` from the result channel resolves eight local packages,
including `tzdata`. A full fixed-point GCC rebuild against the
result interfaces has passed its native tests, and a result-only installation
compiles both C and C++ without an embedded GCC or linker sysroot. Renders now
confirm that every non-sysroot build input for GCC, binutils, and make comes
from the result channel.

The current seed contains 22 packages, principally:

- GCC and G++ 14.4.0 (the stage-0 compiler for the dirty build)
- binutils and ld 2.46.1
- glibc 2.28 bootstrap sysroot (the dirty and result stages share this ABI
  baseline; result uses the local Rocky 8.10-derived package)
- Linux 6.12 kernel headers
- GNU make 4.4.1
- gnuconfig

Exact archive URLs, sizes, and SHA-256 hashes are recorded in
`seed-packages.tsv`.

## Layout

```text
channels/
  seed/              Conda-forge-derived bootstrap seed
  dirty/             Dirty carrier and compiler-interface aliases
  result/            Self-hosted carrier and compiler-interface aliases
recipes/
  gcc-toolchain/     Coarse single-package GCC/G++ compiler carrier
  gcc-aliases/       gcc and gxx metapackages for a built carrier
  binutils/          Single-output native binutils carrier
scripts/
  fetch-seed.sh      Download, verify archive hashes, and index the seed
  check-seed.sh      Check offline solvability of the local seed channel
  check-result.sh    Check the result-only compiler and build-tool interface
  bootstrap.sh       Run seed, dirty, and result stages in order
  pixi.toml          Reproducible environment for the bootstrap tools
  pixi.lock          Locked bootstrap-tool versions
output/              Per-run package output and source caches
seed-packages.tsv    Fixed seed archive manifest
```

Seed archives, generated channel indexes, and staging output are intentionally
not committed. They can be recreated from the committed recipes and manifest.

## Recreating and checking the seed

To run the complete bootstrap in one command (including seed verification and
channel publication):

```bash
./scripts/bootstrap.sh
```

Set `RATTLER_BUILD` to select a particular rattler-build executable. The script
publishes each intermediate stage before resolving the next one, and leaves
build artifacts under `output/`.

`rattler-build` is an external build-time prerequisite; it is not produced by
the bootstrap channel itself. Install it separately or point `RATTLER_BUILD`
at a checked-out or locally built executable. The script does not assume any
particular directory layout outside this repository.

The repository provides a Pixi environment for the complete tool set. After
installing Pixi, initialize it and run the bootstrap with:

```bash
pixi install
pixi run bootstrap
```

`pixi.toml` and `pixi.lock` pin the build tools independently from the target
packages produced by this workspace.

## GitHub Actions

The complete bootstrap runs in GitHub Actions on pushes to `main`, pull
requests, and manual workflow dispatches. The workflow uses the locked Pixi
environment and executes the same canonical command as a local run:

```text
pixi run bootstrap
```

You can start a run from the repository's **Actions → GCC bootstrap → Run
workflow** menu.

Fetching the seed requires Bash, curl, coreutils, and `rattler-index`
command:

```bash
./scripts/fetch-seed.sh
```

The script downloads missing archives, checks every size and SHA-256 against
`seed-packages.tsv`, and regenerates `linux-64` and `noarch` repodata. This is
an archive-integrity check; it does not attempt to solve the channel.

To check offline solvability with mamba:

```bash
./scripts/check-seed.sh
```

The check uses `--offline --override-channels` with only:

```text
file://<repository>/channels/seed
```

To check the result-only compiler and build-tool interface:

```bash
./scripts/check-result.sh
```

Local channels passed to rattler-build should include an explicit `./` prefix,
for example `./channels/seed`. A bare `channels/seed` can be interpreted as a
named remote channel instead of a relative path.

## Building a bootstrap stage

The examples below use clean staging output directories under `./output/`.
The canonical end-to-end command is `pixi run bootstrap`; it cleans generated
channels and output before running seed, dirty, result, and result-selfhost
stages. Manual commands should use the same channel boundaries and output
layout.

### Dirty stage

The dirty stage consumes the seed sysroot at the conda-forge-compatible
triplet. Pass the matching variant configuration to every hermetic recipe:

```text
--variant-config ./variants/dirty.yaml
```

Build the GCC carrier from the seed interfaces:

```bash
rattler-build build \
  --recipe ./recipes/gcc-toolchain/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-toolchain
```

Publish and index the GCC carrier into `channels/dirty`, then expose it as
`gcc` and `gxx`:

```bash
rattler-build build \
  --recipe ./recipes/gcc-aliases/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --output-dir ./output/dirty-aliases
```

Publish and index the aliases into `channels/dirty`, then build native binutils
with the dirty compiler interface:

```bash
rattler-build build \
  --recipe ./recipes/binutils/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-binutils
```

Build local gnuconfig first, then use it with the dirty compiler and binutils
interfaces to build GNU Make after publishing the compiler, alias, and binutils
outputs into `channels/dirty`. Publish and index gnuconfig there before the
Make build as well:

```bash
rattler-build build \
  --recipe ./recipes/gnuconfig/recipe.yaml \
  --target-platform linux-64 \
  --output-dir ./output/dirty-gnuconfig
```

```bash
rattler-build build \
  --recipe ./recipes/make/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-make
```

Publish and index the dirty channel:

```bash
mkdir -p ./channels/dirty/linux-64 ./channels/dirty/noarch
cp ./output/dirty-toolchain/linux-64/*.conda ./channels/dirty/linux-64/
cp ./output/dirty-aliases/linux-64/*.conda ./channels/dirty/linux-64/
cp ./output/dirty-binutils/linux-64/*.conda ./channels/dirty/linux-64/
cp ./output/dirty-make/linux-64/*.conda ./channels/dirty/linux-64/
cp ./output/dirty-gnuconfig/noarch/*.conda ./channels/dirty/noarch/
rattler-index fs ./channels/dirty --target-platform linux-64
rattler-index fs ./channels/dirty --target-platform noarch
```

### Result stage

Build and publish the local Rocky 8.10 sysroot before the result compiler and
build tools. The result variant changes only the relative sysroot layout; it
does not add a default sysroot to the installed compiler:

```bash
rattler-build build \
  --recipe ./recipes/sysroot/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-sysroot
```

Publish and index that package in `channels/result` before building the result
compiler. The result stage must not use the seed channel: it uses the dirty
channel for bootstrap interfaces and the result channel for the target sysroot
and already-built result packages. All result-stage hermetic recipes use:

```text
--variant-config ./variants/result.yaml
```

Run the same carrier recipes against dirty first. Do not add `channels/seed` to
these result-stage solves; a missing result dependency is an error rather than
an invitation to fall back to seed.

```bash
rattler-build build \
  --recipe ./recipes/gcc-toolchain/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/result \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-toolchain
```

Publish and index the result GCC package into `channels/result` before
building the aliases and remaining result packages.

```bash
rattler-build build \
  --recipe ./recipes/gcc-aliases/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --output-dir ./output/result-aliases
```

Publish and index the aliases into `channels/result` before building binutils.

```bash
rattler-build build \
  --recipe ./recipes/binutils/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-binutils
```

Build local gnuconfig first, then use it with the result compiler interface to
build GNU Make. Publish and index the binutils and gnuconfig packages into
`channels/result` before this step:

```bash
rattler-build build \
  --recipe ./recipes/gnuconfig/recipe.yaml \
  --target-platform linux-64 \
  --output-dir ./output/result-gnuconfig
```

```bash
rattler-build build \
  --recipe ./recipes/make/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-make
```

Publish each result package into `channels/result` immediately after it is
built and index it as shown for dirty. Finally, rerun all result
recipes with `channels/result` as the only dependency channel, using fresh
`./output/result-selfhost/` directories, and publish those rebuilt artifacts
back into `channels/result`. This is the result self-host verification stage
performed by `pixi run bootstrap`.

## Package roles

- `gcc-toolchain` is the coarse compiler carrier. It owns the complete GCC/G++
  installation, including compiler runtime libraries, unversioned development
  symlinks, and both compiler drivers.
- `gcc` and `gxx` are empty interface aliases. They select the carrier, allowing
  the same carrier recipe to run against seed, dirty, or a later self-hosted
  channel.
- `binutils` is a single-output native carrier. It owns the assembler, linker,
  and binary inspection tools, provides ordinary and
  `x86_64-pc-linux-gnu-*` command names, and has no embedded conda sysroot.
- `make` is a native build-tool carrier built with the self-hosted compiler.
- `gnuconfig` is a noarch generic carrier containing the pinned GNU
  `config.guess` and `config.sub` scripts.
- Make and gnuconfig are build tools, not compiler runtime components, and are
  intentionally not `gcc`/`gxx` run dependencies.

## Build string convention

Content-bearing packages use the conventional `h` hash marker followed by the
variant hash and build number. Metadata-only interface packages add a `meta_`
prefix before that hash form. This intentionally distinguishes only two roles:
real packages and metapackages while keeping same-variant rebuilds visible in
the package filename.

## Compiler modes and triplet policy

The toolchain has two intentional modes.

### Default host-integrating mode

After installation, `gcc` and `g++` behave like a newer distribution-provided
compiler. They do **not** embed a conda sysroot. They search the host's native
glibc and kernel header paths, including host `/usr/local` installation paths,
and can link against libraries already installed by the distribution or the
user.

The native target triplet is:

```text
x86_64-pc-linux-gnu
```

The vendor field (`pc`) does not change the x86_64 Linux/glibc ABI. It avoids
the conda-forge-specific `x86_64-conda-linux-gnu` namespace, whose compiler,
binutils, and sysroot are deliberately tied together as a hermetic cross-target
toolchain.

### Explicit channel-build mode

Recipes building packages for this channel, including the GCC recipe itself,
explicitly select the channel environment. There is deliberately no
`gcc-buildenv` wrapper package. Each recipe declares its sysroot and tool
dependencies and sets flags such as:

```bash
SYSROOT="${BUILD_PREFIX}/${sysroot_triplet}/sysroot"

export CFLAGS="--sysroot=${SYSROOT} -I${PREFIX}/include"
export CXXFLAGS="--sysroot=${SYSROOT} -I${PREFIX}/include"
export CPPFLAGS="--sysroot=${SYSROOT} -I${PREFIX}/include"
export LDFLAGS="--sysroot=${SYSROOT} -L${PREFIX}/lib"
```

Recipes must also put the intended assembler and linker ahead of host tools in
`PATH` or pass an equivalent `-B` prefix. This keeps ordinary interactive use
host-native while making channel builds explicit and auditable.

### Runtime dependency consequence

`sysroot_linux-64` must not be a direct run dependency of `gcc-toolchain`,
`gcc`, `gxx`, or `binutils`; it belongs in the build requirements of recipes
that choose channel-build mode. The compiler and binutils must not use a
sysroot unless `--sysroot` is explicitly passed.

## Old-distribution deployment constraints

The current glibc 2.28 seed is suitable for bootstrap experimentation, and it
is not a deployment baseline for old distributions. If the result toolchain is
intended to run on older systems, the bootstrap seed must be rebuilt against an
explicit minimum glibc version (for example 2.17 or 2.28). The chosen baseline
must be used both when linking the compiler carrier and when building its
runtime libraries.

The bundled GCC libstdc++ must also be discoverable on hosts whose system
libstdc++ is older than the compiler requires. The final runtime strategy
(rpath, static runtime linking for tools, or an explicit runtime package) is
still pending.

## Binutils design

The local `binutils` package intentionally does not reproduce conda-forge's
`ld_impl` / `binutils_impl` / activation split. It is one native output built
for the same target as GCC:

```text
x86_64-pc-linux-gnu
```

It installs ordinary command names for host-integrating use and
`x86_64-pc-linux-gnu-*` names for GCC's target-tool lookup. It is configured
without a default sysroot and tests that both `ld` and the target-prefixed
`ld` print an empty sysroot.

The seed includes conda-forge's generic `binutils` package as the initial
assembler/linker interface. The same local `binutils` recipe can then run
against seed for the dirty build and against dirty/result interfaces for later
builds. The result channel needs only the local `binutils` name; it does not
need a `binutils_impl_linux-64` package.

The two binutils fixes carried by the conda-forge recipe were checked against
the GNU 2.46.1 release tarball and are already present upstream, so the local
recipe applies no source patches.
