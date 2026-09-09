# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_NDK_VERSION=r27c
ENV ANDROID_NDK_ROOT=/opt/android-ndk
ENV ANDROID_API=24

# 1. Install host build essentials
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    ninja-build \
    git \
    curl \
    unzip \
    tar \
    xz-utils \
    python3 \
    pkg-config \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 2. Download and unpack Android NDK (one NDK cross-compiles for all 4 arches)
RUN curl -sSL "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" -o ndk.zip \
 && unzip -q ndk.zip -d /opt \
 && mv /opt/android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_ROOT} \
 && rm ndk.zip

# 3. Fetch pre-built Termux dependencies for every supported architecture.
# Termux's apt repo serves each arch under its own binary-<arch> path — these
# can't share one prefix directory since they're arch-specific compiled
# libraries, so each gets its own sysroot under /opt/termux-sysroot/<arch>.
# Solidity needs boost, z3, fmt (fmt/z3 unused when USE_Z3=OFF and fmt is
# fetched from source by CMake anyway, but kept here in case that changes).
WORKDIR /tmp/deps
# Termux .deb data.tar entries are rooted at
# ./data/data/com.termux/files/usr/... (6 leading path components) — strip
# those during extraction so files land directly under our per-arch prefix.
RUN for arch in aarch64 arm i686 x86_64; do \
      prefix="/opt/termux-sysroot/${arch}"; \
      mkdir -p "${prefix}/lib" "${prefix}/include" "${prefix}/bin"; \
      packages_url="https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-${arch}/Packages"; \
      packages_list=$(curl -s "${packages_url}"); \
      for pkg in boost boost-static boost-headers z3 fmt libandroid-support libiconv; do \
        url=$(echo "${packages_list}" | \
              awk -v p="^$pkg$" '$1 == "Package:" && $2 ~ p {found=1} found && $1 == "Filename:" {print "https://packages.termux.dev/apt/termux-main/" $2; exit}'); \
        if [ -n "$url" ]; then \
          echo "[$arch] Downloading $url..."; \
          curl -sSL "$url" -o pkg.deb; \
          ar x pkg.deb; \
          tar -xf data.tar.* -C "${prefix}" --strip-components=6; \
          rm -f pkg.deb data.tar.* control.tar.* debian-binary; \
        else \
          echo "[$arch] WARNING: package $pkg not found, skipping"; \
        fi; \
      done; \
    done

WORKDIR /workdir
COPY toolchains/ /workdir/toolchains/
COPY build-solc.sh /workdir/build-solc.sh

