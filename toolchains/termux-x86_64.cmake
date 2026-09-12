set(TERMUX_ARCH_NAME "x86_64")
set(CMAKE_ANDROID_ARCH_ABI "x86_64")
set(NDK_TARGET_TRIPLE "x86_64-linux-android24")
set(BOOST_ARCH_TAG "-x64")
set(EXTRA_COMPILE_FLAGS "")
# Google requires 16KB page-size support for 64-bit ABIs targeting newer
# Android API levels; irrelevant/unsupported on 32-bit ABIs.
set(EXTRA_LINKER_FLAGS "-Wl,-z,max-page-size=16384")

include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

