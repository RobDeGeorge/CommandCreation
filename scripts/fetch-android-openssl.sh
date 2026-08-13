#!/usr/bin/env bash
#
# Fetch the prebuilt OpenSSL that the Android package has to carry.
#
#   ./scripts/fetch-android-openssl.sh [abi]     default: arm64-v8a
#
# Qt for Android does not ship OpenSSL and Android has not offered a system
# copy since API 24. Qt's TLS backend plugin — which androiddeployqt *does*
# package, which is what makes this so easy to miss — dlopen()s libssl_3.so and
# libcrypto_3.so at runtime. If they are not in the .apk it finds nothing,
# QSslSocket::supportsSsl() is false, and every https:// request fails before a
# packet is sent. See the block in CMakeLists.txt that consumes these.
#
# The binaries come from KDAB's android_openssl, which is the source Qt's own
# documentation points at. Pinned to a commit and checked against a hash
# recorded here rather than tracking a branch: this is a binary being dropped
# into a package that gets signed with a release key, so it should not be able
# to change underneath a build without this file changing too.
#
# Only the two .so files are downloaded, not the 207 MB repository they live
# in — hence raw.githubusercontent.com and no git clone.
#
# Re-running is free: anything already present with the right hash is left
# alone, so build-android.sh can call this unconditionally.
set -euo pipefail

# KDAB/android_openssl, "Update binaries with correct symver values" (#76).
# To move this: bump the SHA, run the script, and replace the hashes below with
# what it prints when it rejects the new files.
PIN=b71f1470962019bd89534a2919f5925f93bc5779

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI="${1:-arm64-v8a}"
DEST="$ROOT/third_party/android_openssl/ssl_3/$ABI"

# sha256 of each file as of the pinned commit. Qt 6.5 and later want the 3.x
# series; the 1.1 libraries in the same repository are for older kits and are
# deliberately not an option here.
sha_for() {
    case "$1" in
        arm64-v8a/libssl_3.so)      echo 01d2bd0baac626efd3309f35f99c4b826dd9b885a7e4d14d5b12b3603d3a407f ;;
        arm64-v8a/libcrypto_3.so)   echo 1e6c12ae0c2dadfe9d178d7f80f0ab248a1877a234066098bf5594e5205e5740 ;;
        armeabi-v7a/libssl_3.so)    echo a1a9fda0b13d93a30cf103f993c080eafc6e1dee249e1a29d68cd7616dc052a4 ;;
        armeabi-v7a/libcrypto_3.so) echo a9d5352e52600e1c1c05d12e3112a479af7a2a3287760e3fcde432a423266b19 ;;
        x86/libssl_3.so)            echo 5ed7b9c925755af7a0e163b244c535d283869270e55c77777d1cec7cfcfe88d3 ;;
        x86/libcrypto_3.so)         echo 420507adf9896267252d93e6bbf5eae5d8555a7693c026019980babf51065f3d ;;
        x86_64/libssl_3.so)         echo 2af32571317adf90fb7a007756a17dd15cd2469da9ebbd4e973883f8753369c1 ;;
        x86_64/libcrypto_3.so)      echo bc4bdd31835659e639c2dc8f0a722342f51230074c23ee3dd6d1fa2353d72db1 ;;
        *) return 1 ;;
    esac
}

# Named up front rather than left to a 404 forty lines later, since a typo here
# and an ABI the upstream repository genuinely lacks look identical by then.
case "$ABI" in
    arm64-v8a|armeabi-v7a|x86|x86_64) ;;
    *) echo "unknown Android ABI: $ABI" >&2
       echo "one of: arm64-v8a armeabi-v7a x86 x86_64" >&2
       exit 2 ;;
esac

mkdir -p "$DEST"

for lib in libssl_3.so libcrypto_3.so; do
    want=$(sha_for "$ABI/$lib")
    out="$DEST/$lib"

    # Already here and intact — the common case on every build after the first.
    if [[ -f "$out" ]] && [[ "$(sha256sum "$out" | cut -d' ' -f1)" == "$want" ]]; then
        continue
    fi

    url="https://raw.githubusercontent.com/KDAB/android_openssl/$PIN/ssl_3/$ABI/$lib"
    echo "fetching $ABI/$lib"
    # To a temporary name first: a half-written .so that happens to survive a
    # dropped connection is worse than no file, because the hash check below is
    # the only thing that would ever look at it again.
    curl -sSLf --retry 3 -o "$out.part" "$url" || {
        echo "could not download $url" >&2
        rm -f "$out.part"
        exit 1
    }

    got=$(sha256sum "$out.part" | cut -d' ' -f1)
    if [[ "$got" != "$want" ]]; then
        echo "$lib does not match the hash recorded in $(basename "${BASH_SOURCE[0]}")" >&2
        echo "  expected $want" >&2
        echo "  got      $got" >&2
        echo "Refusing to package it. If you moved PIN on purpose, this is the" >&2
        echo "new hash to record; otherwise do not build from this." >&2
        rm -f "$out.part"
        exit 1
    fi
    mv "$out.part" "$out"
done

echo "OpenSSL for $ABI: $DEST"
