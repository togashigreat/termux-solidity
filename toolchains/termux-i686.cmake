set(TERMUX_ARCH_NAME "i686")
set(CMAKE_ANDROID_ARCH_ABI "x86")
set(NDK_TARGET_TRIPLE "i686-linux-android24")
set(BOOST_ARCH_TAG "-x32")
set(EXTRA_COMPILE_FLAGS "")
# No 16KB page-size requirement on 32-bit ABIs.
set(EXTRA_LINKER_FLAGS "")

include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

