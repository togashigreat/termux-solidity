# termux-solidity

Cross-compiles the [Solidity](https://github.com/ethereum/solidity) compiler (`solc`) for Termux/Android, across all four architectures Termux supports — `aarch64`, `arm`, `i686`, and `x86_64` — and publishes the results in a format [`svm-rs`](https://github.com/alloy-rs/svm-rs) (foundry's Solidity Version Manager) can consume directly.

Termux's own `foundry` package ships with the `svm` feature disabled, because there was previously no source of Android-compiled `solc` binaries covering all of Termux's architectures. This repo exists to fill that gap: it builds `solc` from source for each architecture, patches around a handful of upstream incompatibilities that only show up when cross-compiling against Termux's (very current) system libraries, and publishes a `list.json` + binaries layout that a patched `svm-rs` can fetch from at runtime.

## What's in this repo

```
Dockerfile              # builder image: Ubuntu 24.04 + Android NDK r27c + per-arch Termux sysroots
toolchains/
├── _common.cmake        # shared CMake cross-compile logic, parameterized per architecture
├── termux-aarch64.cmake
├── termux-arm.cmake
├── termux-i686.cmake
└── termux-x86_64.cmake
build-solc.sh            # clones a solidity tag, patches it, configures + builds with CMake/Ninja
scripts/
└── publish_solc_bin.py  # merges a freshly built binary into a cumulative svm-rs-style list.json
.github/workflows/
├── docker-publish.yml   # rebuilds the builder image when the Dockerfile/toolchains/build script change
└── build.yml            # builds all 4 architectures for a given solc version, publishes both a
                          # GitHub Release (for humans) and the `solc-bin` branch (for svm-rs)
```

Built binaries and their `list.json` release manifests live on the [`solc-bin`](../../tree/solc-bin) branch, under `android/<arch>/`. That branch is unrelated history to `main` (an orphan branch) — it exists purely as a stable hosting location, the same pattern [`alloy-rs/solc-builds`](https://github.com/alloy-rs/solc-builds).

## Usage

### Building a version

From the Actions tab, run **Build Solidity for Termux (all architectures)** with the `solc_version` input (e.g. `0.8.30`). This:

1. Builds `solc` for all four architectures in parallel, inside the pinned builder image.
2. Publishes the four binaries as assets on a GitHub Release tagged `v<version>`.
3. Updates `android/<arch>/list.json` on the `solc-bin` branch for each architecture.

Re-running the workflow for a version that's already been published overwrites that version's Release assets and `list.json` entry — safe to use for rebuilding after a pipeline fix.

### Building locally

```bash
docker build -t solc-termux-builder .
docker run --rm -v "$(pwd)/dist:/dist" solc-termux-builder bash -c \
  "/workdir/build-solc.sh 0.8.30 aarch64 && cp /workdir/solidity/build/solc/solc /dist/solc-0.8.30-aarch64"
```

Second argument to `build-solc.sh` is the target architecture: `aarch64`, `arm`, `i686`, or `x86_64`.

## Patches applied to Solidity's source

Solidity's build system predates several changes in the Boost and Android NDK ecosystems that only surface when cross-compiling against a very recent Boost (Termux currently ships 1.91.0). `build-solc.sh` applies these automatically, each guarded so it's a no-op on versions/files where the pattern doesn't apply:

| Problem | Cause | Fix |
|---|---|---|
| `Could NOT find Boost (missing: system)` | Boost.System has been header-only since Boost 1.69; recent Boost no longer ships a compiled `libboost_system` | Drop `system` from the required components list; provide a stand-in `INTERFACE` target |
| `no member named 'search_path' in namespace 'boost::process'` | Boost.Process was rewritten in Boost 1.86; the old flat API moved into `boost::process::v1` | Every file including `<boost/process.hpp>` is patched to prefer `<boost/process/v1.hpp>` when available |
| `ld.gold: ... unsupported ELF machine number 183` | Solidity defaults to the `gold` linker; the host's `gold` binary isn't built with AArch64 target support | Build with `-DUSE_LD_GOLD=OFF`, falling back to `lld` (which the NDK ships and cross-links correctly) |
| Version string shows `-develop.<date>...mod` instead of a clean release string | Official release tarballs ship `prerelease.txt` + `commit_hash.txt`; a plain `git clone` has neither, and patching the source makes `git diff` non-empty | Write both files before patching, reproducing a clean `<version>+commit.<hash>` string |

## Enabling `svm` in Termux's `foundry` package

This repo's output is consumed by two patches applied during Termux's own `foundry` package build (`svm-rs-solc-patch.diff` and `svm-rs-build-patch.diff`, applied to the vendored `svm-rs` and `svm-rs-builds` crates respectively). At a high level, they add three new `Platform` variants (`AndroidArm`, `AndroidX86`, `AndroidX8664`) alongside the upstream `AndroidAarch64`, and point all four at this repo's `solc-bin` branch instead of (or in addition to) upstream's `alloy-rs/solc-builds`.

## Known limitations

- Each new solc version needs to be built and published here manually (or scheduled) before `svm install <version>` will find it on Termux — this repo does not track upstream Solidity releases automatically.
- Only tested from Solidity `0.8.18` onward. Older versions may hit different Boost/CMake incompatibilities not yet covered by the patches above, since they predate the NDK/Boost versions this pipeline was built against.
- The `solc-bin` branch grows indefinitely as more versions are published (binaries are committed directly, not stored via Git LFS).

