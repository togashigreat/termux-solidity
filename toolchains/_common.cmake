# Shared Termux/Android cross-compile toolchain logic.
# Not used directly as -DCMAKE_TOOLCHAIN_FILE — each termux-<arch>.cmake sets
# the arch-specific variables below, then include()s this file.
#
# Expected to be set before including this file:
#   TERMUX_ARCH_NAME        - Termux's own arch name: aarch64 | arm | i686 | x86_64
#   CMAKE_ANDROID_ARCH_ABI  - Android ABI name: arm64-v8a | armeabi-v7a | x86 | x86_64
#   NDK_TARGET_TRIPLE       - Full clang -target triple incl. API level,
#                             e.g. aarch64-linux-android24
#   BOOST_ARCH_TAG          - Boost auto-link arch tag: -a64 | -a32 | -x32 | -x64
#   EXTRA_COMPILE_FLAGS     - (optional) extra space-separated -m flags, e.g. NEON for arm
#   EXTRA_LINKER_FLAGS      - (optional) extra linker flags, e.g. 16k page size for 64-bit

set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 24)
set(CMAKE_ANDROID_NDK /opt/android-ndk)
set(CMAKE_ANDROID_STL_TYPE c++_shared)

# Each target arch gets its own sysroot under /opt/termux-sysroot/<arch> baked
# into the builder image (see Dockerfile) — these can't share one directory
# since they contain arch-specific compiled libraries with the same paths.
set(TERMUX_PREFIX "/opt/termux-sysroot/${TERMUX_ARCH_NAME}")

# This is where solc will actually live once installed on a real device —
# used only for the runtime rpath below, NOT for finding build-time deps.
set(TERMUX_RUNTIME_PREFIX "/data/data/com.termux/files/usr")

# Instruct CMake to search inside the arch's Termux sysroot first
set(CMAKE_SYSROOT "/opt/android-ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot")
set(CMAKE_FIND_ROOT_PATH "${TERMUX_PREFIX};${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Include paths & link directories
include_directories(SYSTEM ${TERMUX_PREFIX}/include)
link_directories(${TERMUX_PREFIX}/lib)

# Compiler flags
set(CMAKE_C_FLAGS "-target ${NDK_TARGET_TRIPLE} -isystem ${TERMUX_PREFIX}/include ${EXTRA_COMPILE_FLAGS}" CACHE STRING "")
set(CMAKE_CXX_FLAGS "-target ${NDK_TARGET_TRIPLE} -isystem ${TERMUX_PREFIX}/include ${EXTRA_COMPILE_FLAGS}" CACHE STRING "")

# Linker flags: enforce Termux rpath (the on-device path, not the build sysroot)
set(CMAKE_EXE_LINKER_FLAGS "-L${TERMUX_PREFIX}/lib -Wl,-rpath,${TERMUX_RUNTIME_PREFIX}/lib -Wl,--enable-new-dtags ${EXTRA_LINKER_FLAGS}" CACHE STRING "")

# --- Boost hints for cross-compilation ---
set(Boost_NO_BOOST_CMAKE ON CACHE BOOL "Do not use BoostConfig.cmake" FORCE)
set(Boost_NO_SYSTEM_PATHS ON CACHE BOOL "" FORCE)
set(BOOST_ROOT "${TERMUX_PREFIX}" CACHE PATH "" FORCE)
set(Boost_ROOT "${TERMUX_PREFIX}" CACHE PATH "" FORCE)
set(BOOST_INCLUDEDIR "${TERMUX_PREFIX}/include" CACHE PATH "" FORCE)
set(BOOST_LIBRARYDIR "${TERMUX_PREFIX}/lib" CACHE PATH "" FORCE)
set(Boost_ARCHITECTURE "${BOOST_ARCH_TAG}" CACHE STRING "" FORCE)

