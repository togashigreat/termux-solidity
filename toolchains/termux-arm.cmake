set(TERMUX_ARCH_NAME "arm")
set(CMAKE_ANDROID_ARCH_ABI "armeabi-v7a")
# Note the "eabi" suffix and "androideabi" (not "android") for the 32-bit ARM triple.
set(NDK_TARGET_TRIPLE "armv7a-linux-androideabi24")
set(BOOST_ARCH_TAG "-a32")
# Matches Termux's own armv7 package builds: hard-float ABI with NEON.
set(EXTRA_COMPILE_FLAGS "-march=armv7-a -mfpu=neon -mfloat-abi=softfp")
# No 16KB page-size requirement on 32-bit ABIs.
set(EXTRA_LINKER_FLAGS "")

include("${CMAKE_CURRENT_LIST_DIR}/_common.cmake")

