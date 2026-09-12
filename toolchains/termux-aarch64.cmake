set(TERMUX_ARCH_NAME "aarch64")
set(CMAKE_ANDROID_ARCH_ABI "arm64-v8a")
set(NDK_TARGET_TRIPLE "aarch64-linux-android24")
set(BOOST_ARCH_TAG "-a64")
set(EXTRA_COMPILE_FLAGS "")
# Google requires 16KB page-size support for 64-bit ABIs targeting newer
# Android API levels; irrelevant/unsupported on 32-bit ABIs.
set(EXTRA_LINKER_FLAGS "-Wl,-z,max-page-size=16384")

include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

