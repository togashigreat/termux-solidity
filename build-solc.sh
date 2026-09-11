#!/bin/bash
set -euo pipefail

TARGET_VERSION="${1:-0.8.18}"
TARGET_ARCH="${2:-aarch64}"

case "${TARGET_ARCH}" in
    aarch64|arm|i686|x86_64) ;;
    *)
        echo "ERROR: unsupported arch '${TARGET_ARCH}'. Expected one of: aarch64 arm i686 x86_64" >&2
        exit 1
        ;;
esac

TOOLCHAIN_FILE="/workdir/toolchains/termux-${TARGET_ARCH}.cmake"
if [ ! -f "${TOOLCHAIN_FILE}" ]; then
    echo "ERROR: toolchain file ${TOOLCHAIN_FILE} not found" >&2
    exit 1
fi

# Strip leading 'v' if entered by user (e.g. v0.8.18 -> 0.8.18)
VERSION="${TARGET_VERSION#v}"
TAG="v${VERSION}"

echo "Building Solidity ${TAG} for Termux arch: ${TARGET_ARCH}"

rm -rf /workdir/solidity
git clone --recurse-submodules --depth 1 --branch "${TAG}" https://github.com/argotorg/solidity.git /workdir/solidity
cd /workdir/solidity

# --- Version metadata fix ---
# Without these two files, Solidity's cmake/scripts/buildinfo.cmake falls
# back to generating its own version string: it appends "-develop.<today's
# date>" as the prerelease tag (since prerelease.txt is missing), and appends
# ".mod" to the commit hash (since `git diff HEAD` is non-empty once we patch
# the source below). Both files are normally bundled into Solidity's official
# *release* source tarballs by their own release CI, but a plain `git clone`
# never has them. Writing them ourselves — before any patch below touches the
# tree — reproduces a clean official-style version string, e.g.
# "0.8.18+commit.87f61d96.Android.clang" instead of
# "0.8.18-develop.2026.9.9+commit.87f61d96.mod.Android.clang".
git rev-parse HEAD > commit_hash.txt
: > prerelease.txt   # empty file = "this is a final release", not a prerelease

# --- Apply Termux Source Patches ---

# Boost.System has been header-only since Boost 1.69, and modern Boost
# releases (Termux currently ships 1.91.0) no longer build a compiled
# libboost_system at all. Solidity's cmake/EthDependencies.cmake still does:
#
#   set(BOOST_COMPONENTS "filesystem;unit_test_framework;program_options;system")
#   find_package(Boost 1.65.0 QUIET REQUIRED COMPONENTS ${BOOST_COMPONENTS})
#
# which fails to configure because there's no compiled "system" lib to find.
# We also drop "unit_test_framework" since it's only used by test/ (excluded
# below via -DTESTS=OFF) and don't need to require it just to build solc.
#
# NOTE: this line-replace targets the `set(BOOST_COMPONENTS "...")` line
# specifically (not the find_package call itself, which only references the
# variable) — that mismatch was the actual bug in earlier attempts at this
# patch: the sed matched nothing and silently did not apply.
if [ -f cmake/EthDependencies.cmake ]; then
    sed -i -E 's/^([[:space:]]*set\(BOOST_COMPONENTS ").*("\))$/\1filesystem;program_options\2/' cmake/EthDependencies.cmake
fi

# Because "system" is no longer requested above, CMake never defines a
# Boost::system imported target — but libsolutil/CMakeLists.txt still links
# against Boost::system directly. Define a stand-in empty INTERFACE target
# right after EthDependencies is included so that link line still resolves.
# `include(EthDependencies)` is a stable, version-spanning anchor line in
# Solidity's top-level CMakeLists.txt, which is why we anchor the insert here.
if [ -f CMakeLists.txt ]; then
    sed -i '/include(EthDependencies)/a if(NOT TARGET Boost::system)\n  add_library(Boost::system INTERFACE IMPORTED)\nendif()' CMakeLists.txt
fi

# In Solidity >= 0.8.27 with IGNORE_VENDORED_DEPENDENCIES=ON, fmtlib must be included
# unconditionally rather than skipped inside the vendored check.
if printf '%s\n0.8.27\n' "${VERSION}" | sort -V -C; then
    sed -i '/include(EthDependencies)/a include(fmtlib)' CMakeLists.txt
    sed -i '/if *(NOT IGNORE_VENDORED_DEPENDENCIES)/{n;/include(fmtlib)/d}' CMakeLists.txt
fi

# Solidity >= 0.8.31: drop header-only targets (range-v3, nlohmann_json) and old Boost_SYSTEM_LIBRARY
# Solidity >= 0.8.27: range-v3 and nlohmann-json are header-only, drop from solutil link line
if printf '%s\n0.8.27\n' "${VERSION}" | sort -V -C; then
    if [ -f libsolutil/CMakeLists.txt ]; then
        sed -i -E 's/target_link_libraries\([[:space:]]*solutil[[:space:]]+PUBLIC[[:space:]]+Boost::boost[[:space:]]+Boost::filesystem([[:space:]]+\$\{Boost_SYSTEM_LIBRARY\})?[[:space:]]+range-v3[[:space:]]+fmt::fmt-header-only[[:space:]]+nlohmann_json::nlohmann_json\)/target_link_libraries(solutil PUBLIC Boost::boost Boost::filesystem fmt::fmt-header-only)/' libsolutil/CMakeLists.txt
    fi
fi

# Fix CMake CMP0144 policy warning for modern CMake
sed -i '1s/^/cmake_policy(SET CMP0144 NEW)\n/' CMakeLists.txt

# Since Boost 1.86, <boost/process.hpp> pulls in the new Process v2 API by
# default; old free functions/types like boost::process::search_path(),
# ::ipstream, ::child, ::std_out only exist under the boost::process::v1
# namespace now. Termux ships a recent Boost (currently 1.91.0), so any file
# that does `#include <boost/process.hpp>` and then uses the flat
# boost::process:: API no longer compiles as written (hit so far in
# libsolidity/formal/ModelChecker.cpp and libsolidity/interface/SMTSolverCommand.cpp).
# Rather than patch files by name (fragile across versions), patch every file
# in the tree using this include pattern: prefer the v1 header (re-exposed
# under boost::process via a using-directive) when available, falling back
# to the old flat include unchanged on older Boost with no v1/v2 split.
mapfile -t BOOST_PROCESS_FILES < <(grep -rl '#include <boost/process.hpp>' --include='*.cpp' --include='*.h' . 2>/dev/null || true)
if [ "${#BOOST_PROCESS_FILES[@]}" -gt 0 ]; then
    python3 - "${BOOST_PROCESS_FILES[@]}" << 'PYEOF'
import sys
old = "#include <boost/process.hpp>"
new = (
    "#if __has_include(<boost/process/v1.hpp>)\n"
    "#include <boost/process/v1.hpp>\n"
    "namespace boost { namespace process { using namespace v1; } }\n"
    "#else\n"
    "#include <boost/process.hpp>\n"
    "#endif"
)
for path in sys.argv[1:]:
    with open(path) as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new, 1)
        with open(path, "w") as f:
            f.write(content)
        print(f"Patched {path} for Boost.Process v1/v2 compatibility")
    else:
        print(f"WARNING: expected include line not found in {path}, skipping")
PYEOF
else
    echo "NOTE: no files found using the flat boost/process.hpp include, skipping boost::process patch"
fi

mkdir build && cd build

cmake -G Ninja .. \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_INSTALL_PREFIX="/data/data/com.termux/files/usr" \
    -DCMAKE_BUILD_TYPE=Release \
    -DIGNORE_VENDORED_DEPENDENCIES=ON \
    -DSTRICT_NLOHMANN_JSON_VERSION=OFF \
    -DUSE_Z3=OFF \
    -DUSE_CVC4=OFF \
    -DTESTS=OFF \
    -DSTRICT_Z3_VERSION=OFF \
    -DPEDANTIC=OFF \
    -DUSE_LD_GOLD=OFF

ninja solc

# Verify binary architecture
/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf -h solc/solc

