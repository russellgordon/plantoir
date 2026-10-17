# Runnable Swift (#493): the image that compiles a course's ```swift run
# blocks to WebAssembly. NOT the website builder's image: a second one,
# `teaching-quartz-swift:src-<hash>` (the hash covers this folder only), built
# by the launcher the first time a preview has a Swift block to compile - a
# teacher who never writes Swift never downloads it. It runs one container per
# preview that has blocks to compile, with no network:
#
#   docker run --rm --network none --mount <cache>:<cache> IMAGE \
#       python3 /opt/plantoir-swift/compile.py <jobs> <cache>/<toolchain id>
#
# Recipe measured by the #493 spike (2026-10-16, Colima on an M4 Pro) and its
# corrections: contracts/toolchain.json -> swiftImage holds every pin, and
# documentation/02-docker-image.md -> "The Swift image (#493)" the reasons.
#
# The same base as the website builder's image (Debian 13), pinned by index
# digest, so its first layer is shared and costs nothing to download twice.
FROM python:3.11-slim@sha256:90744cff8f32887f075c47d747a173ff333e9e98801667af93c357fa9f5e28ff

# Runtime libraries the Linux toolchain's programs link against. No -dev
# packages, no gcc: this image only cross-compiles to wasm.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates libcurl4t64 libedit2 libncurses6 libsqlite3-0 libxml2 \
        libuuid1 zlib1g tzdata \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# BuildKit fills TARGETARCH (arm64 on Apple silicon, amd64 on an Intel Mac),
# and the downloads are chosen by it: each pair of URL and SHA-256 is pinned
# (review S7). The x86_64 pair was downloaded once to take its SHA-256 and
# check its signature; compiling on x86_64 is not measured.
ARG TARGETARCH

# Swift 6.4.0-RELEASE for Debian 13 (swift.org; GPG signatures of both
# toolchains verified against the Swift 6.x Release Signing Key
# 52BB7E3DE28A71BE22EC05FFEF80A866B47A981F), and the ONE wasm SDK bundle,
# which is platform-neutral (releases.json lists one checksum for both hosts).
#
# All in ONE layer, and trimmed in the same step, so nothing the compiler does
# not use is ever stored (#493 ruling Q2): lldb, sourcekit, the package
# manager and the Linux host's own standard libraries go - 3.5 GB of
# toolchain becomes about 1.4 GB, and every gate fragment still compiles to
# the same sizes (spike §6; verify.sh's Swift gate is the proof each time).
#
# The SDK is fetched with curl and checked with sha256sum, then installed from
# the LOCAL file: `swift sdk install <url> --checksum` crashes on Linux 6.4.0
# after its download (spike G1: FoundationNetworking, SIGABRT). Into a fixed
# folder (G3: the default is root's home). Installed BEFORE the trim, which
# removes the program that installs it.
ARG SWIFT_URL_ARM64=https://download.swift.org/swift-6.4.0-release/debian13-aarch64/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-debian13-aarch64.tar.gz
ARG SWIFT_SHA256_ARM64=c501354c2690c93676cb08243c6e3e4e5f2b2dc46e557bf9538427d51788f132
ARG SWIFT_URL_AMD64=https://download.swift.org/swift-6.4.0-release/debian13/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-debian13.tar.gz
ARG SWIFT_SHA256_AMD64=b623947404e7ea9843cfc315ed8624e85410fae571eb353339780ed222243737
ARG WASM_SDK_URL=https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz
ARG WASM_SDK_SHA256=f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
RUN set -e; \
    case "$TARGETARCH" in \
      arm64) url="$SWIFT_URL_ARM64"; sum="$SWIFT_SHA256_ARM64" ;; \
      amd64) url="$SWIFT_URL_AMD64"; sum="$SWIFT_SHA256_AMD64" ;; \
      *) echo "no Swift toolchain is pinned for $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -fsSL "$url" -o /tmp/swift.tar.gz; \
    echo "$sum  /tmp/swift.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/swift; \
    tar -xzf /tmp/swift.tar.gz -C /opt/swift --strip-components=1; \
    rm /tmp/swift.tar.gz; \
    curl -fsSL "$WASM_SDK_URL" -o /tmp/wasm-sdk.tar.gz; \
    echo "$WASM_SDK_SHA256  /tmp/wasm-sdk.tar.gz" | sha256sum -c -; \
    /opt/swift/usr/bin/swift sdk install /tmp/wasm-sdk.tar.gz --swift-sdks-path /opt/swift-sdks; \
    rm /tmp/wasm-sdk.tar.gz; \
    /opt/swift/usr/bin/swift sdk list --swift-sdks-path /opt/swift-sdks; \
    cd /opt/swift/usr; \
    rm -rf bin/lldb bin/lldb-argdumper bin/lldb-dap bin/lldb-server bin/repl_swift \
        bin/sourcekit-lsp bin/clangd bin/docc bin/swift-format bin/wasmkit bin/plutil \
        bin/swift-build bin/swift-run bin/swift-test bin/swift-package bin/swift-sdk \
        bin/swift-experimental-sdk bin/swift-package-collection bin/swift-package-registry \
        bin/swift-build-tool bin/swift-build-sdk-interfaces bin/swift-api-digester \
        bin/swift-symbolgraph-extract bin/swift-synthesize-interface bin/swift-help \
        bin/clang-cache bin/llvm-cov bin/llvm-profdata \
        lib/liblldb.so* lib/libsourcekitdInProc.so lib/libSwiftSourceKitClientPlugin.so \
        lib/libSwiftSourceKitPlugin.so lib/libclang.so* lib/libLTO.so* \
        lib/swift_static lib/swift/embedded lib/swift/pm lib/python3* \
        share/doc share/docc share/man share/sourcekit-lsp share/pm include/SourceKit; \
    /opt/swift/usr/bin/swiftc --version

# Binaryen version_133: wasm-opt only (the release binary is static). OFF
# PATH on purpose: clang runs any wasm-opt it finds on PATH by itself while
# linking, which changes the output (Phase 0 trap 1); compile.py calls it by
# its absolute path.
ARG BINARYEN_URL_ARM64=https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-aarch64-linux.tar.gz
ARG BINARYEN_SHA256_ARM64=89c07ea56faf38d0fbecf36ca8ec0721756716185f265b568e133d427f299bf8
ARG BINARYEN_URL_AMD64=https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-x86_64-linux.tar.gz
ARG BINARYEN_SHA256_AMD64=2dc9c7813f5375db93d96ead4b78222fcc3e2677bbb832297af4797782a37489
RUN set -e; \
    case "$TARGETARCH" in \
      arm64) url="$BINARYEN_URL_ARM64"; sum="$BINARYEN_SHA256_ARM64" ;; \
      amd64) url="$BINARYEN_URL_AMD64"; sum="$BINARYEN_SHA256_AMD64" ;; \
      *) echo "no binaryen is pinned for $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -fsSL "$url" -o /tmp/binaryen.tar.gz; \
    echo "$sum  /tmp/binaryen.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/binaryen/bin; \
    tar -xzf /tmp/binaryen.tar.gz -C /opt/binaryen/bin --strip-components=2 binaryen-version_133/bin/wasm-opt; \
    rm /tmp/binaryen.tar.gz; \
    /opt/binaryen/bin/wasm-opt --version

# The compile step and the readLine shim Embedded Swift needs (Phase 0 §3:
# without it every block that calls readLine() fails to link).
COPY compile.py ReadLineShim.swift /opt/plantoir-swift/

WORKDIR /tmp
