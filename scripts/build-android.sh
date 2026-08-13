#!/usr/bin/env bash
#
# Build the Android package into build-android/.
#
#   ./scripts/build-android.sh                  debug .apk
#   ./scripts/build-android.sh --release        release .apk (unsigned)
#   ./scripts/build-android.sh --release --sign release .apk, signed with the
#                                               keystore named in the
#                                               environment — see --sign below
#   ./scripts/build-android.sh --install        build, then push it to a
#                                               connected device over adb
#
# Same sources as every other build. Nothing forks: qml/ is shared whole, and
# the one place the app knows it is on a phone is dataDir()/unpackCards() in
# src/Db.cpp — the .apk is read-only, so the packaged cards.db is unpacked to
# the app's private directory the first time it runs.
#
# Four paths have to be right, and the errors you get for each of them are not
# the errors you would expect, so they are checked up front rather than left to
# fail eighty lines into a Gradle log:
#
#   QT_ANDROID    a Qt for Android kit — the abi you are building for, e.g.
#                 ~/Qt/6.9.0/android_arm64_v8a
#   QT_HOST_PATH  a desktop Qt of *exactly* the same version. Not optional, and
#                 not the system Qt unless the versions happen to match: it is
#                 where the moc/rcc/qmltc that run on this machine come from.
#   ANDROID_SDK_ROOT / ANDROID_NDK_ROOT
#                 the SDK, and an NDK the Qt kit was built against. Qt names
#                 the NDK version it wants in its own mkspecs — see the README.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build-android"

MODE=Debug
INSTALL=no
SIGN=no
for arg in "$@"; do
    case "$arg" in
        --release) MODE=Release ;;
        --install) INSTALL=yes ;;
        --sign)    SIGN=yes ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Signing is decided when the build is *configured*, not when it runs.
# QT_ANDROID_SIGN_APK is a CMake variable that puts --sign on the
# androiddeployqt command line; the keystore itself travels in the environment,
# which is what keeps the passwords off that command line and out of any log.
#
# Setting the four environment variables without this flag does nothing at all,
# quietly, and leaves you with an unsigned .apk that cannot be installed — so
# the two halves are checked together here rather than discovered separately.
SIGN_ARGS=()
if [[ "$SIGN" == yes ]]; then
    [[ "$MODE" == Release ]] || {
        echo "--sign is for --release builds; a debug build is already signed" >&2
        exit 1; }
    for var in QT_ANDROID_KEYSTORE_PATH QT_ANDROID_KEYSTORE_ALIAS \
               QT_ANDROID_KEYSTORE_STORE_PASS QT_ANDROID_KEYSTORE_KEY_PASS; do
        [[ -n "${!var:-}" ]] || { echo "--sign needs $var set" >&2; exit 1; }
    done
    [[ -f "$QT_ANDROID_KEYSTORE_PATH" ]] || {
        echo "no keystore at $QT_ANDROID_KEYSTORE_PATH" >&2; exit 1; }
    SIGN_ARGS=(-DQT_ANDROID_SIGN_APK=ON)
fi

# What the package calls itself. CMakeLists.txt has a default, and a release
# build overrides it from the tag being built — see .github/workflows/
# release.yml. Passed through here rather than left to the caller's cmake line,
# because the caller does not have one: this script owns the configure step.
VERSION_ARGS=()
if [[ -n "${MTG_VERSION:-}" ]]; then
    VERSION_ARGS=(-DMTG_VERSION="$MTG_VERSION")
fi

need() {
    local var=$1 what=$2
    [[ -n "${!var:-}" ]] || { echo "$var is not set — $what" >&2; exit 1; }
    [[ -d "${!var}" ]] || { echo "$var points at nothing: ${!var}" >&2; exit 1; }
}
need QT_ANDROID "the Qt for Android kit, e.g. ~/Qt/6.9.0/android_arm64_v8a"
need QT_HOST_PATH "a desktop Qt of the same version, e.g. ~/Qt/6.9.0/gcc_64"
need ANDROID_SDK_ROOT "the Android SDK"
need ANDROID_NDK_ROOT "the Android NDK"

# The database is packaged at build time; there is no later chance to find it.
# CMake says this too, but saying it here costs nothing and saves a configure.
[[ -f "$ROOT/data/cards.db" ]] || {
    echo "data/cards.db is missing — build it first: python3 scripts/ingest.py" >&2
    exit 1
}

# Gradle is the fussiest thing in this toolchain about Java versions, and the
# failure it gives for a too-new JDK ("Unsupported class file major version")
# names neither Java nor the fix. JAVA_HOME wins over whatever java is on PATH.
if [[ -z "${JAVA_HOME:-}" ]]; then
    echo "note: JAVA_HOME is unset, so Gradle will use whichever java is on PATH" >&2
    echo "      ($(java -version 2>&1 | head -1)). JDK 17 or 21 if that fails." >&2
fi

# OpenSSL, which the package has to carry for any https:// request to work at
# all — see the block in CMakeLists.txt that packages it. Which ABI to fetch
# follows from the kit: qt-cmake below picks ANDROID_ABI from the same name, so
# asking here keeps the two from ever disagreeing.
#
# ANDROID_ABI in the environment overrides it, for a kit whose directory is not
# named the way Qt's own are.
if [[ -z "${ANDROID_ABI:-}" ]]; then
    case "$(basename "$QT_ANDROID")" in
        *arm64_v8a) ANDROID_ABI=arm64-v8a ;;
        *armv7)     ANDROID_ABI=armeabi-v7a ;;
        *x86_64)    ANDROID_ABI=x86_64 ;;
        *x86)       ANDROID_ABI=x86 ;;
        *) echo "cannot tell which ABI $QT_ANDROID is for — set ANDROID_ABI" >&2
           exit 1 ;;
    esac
fi
"$ROOT/scripts/fetch-android-openssl.sh" "$ANDROID_ABI"

"$QT_ANDROID/bin/qt-cmake" -S "$ROOT" -B "$OUT" \
    -DCMAKE_BUILD_TYPE="$MODE" \
    -DQT_HOST_PATH="$QT_HOST_PATH" \
    -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
    -DANDROID_NDK_ROOT="$ANDROID_NDK_ROOT" \
    "${VERSION_ARGS[@]}" "${SIGN_ARGS[@]}"

# `apk` is the target qt_add_executable() generates for an Android build: it
# builds the library, runs androiddeployqt over it, and drives Gradle. Building
# the default target alone leaves you with a .so and no package.
cmake --build "$OUT" --target apk

# A signed build writes the signed package beside the unsigned one it was made
# from, and only one of the two can be installed. Prefer it; there is exactly
# one .apk to find otherwise.
APK=$(find "$OUT/android-build/build/outputs/apk" -name '*-signed.apk' -print -quit)
[[ -n "$APK" ]] || \
    APK=$(find "$OUT/android-build/build/outputs/apk" -name '*.apk' -print -quit)
[[ -n "$APK" ]] || { echo "built, but no .apk came out — check the log above" >&2; exit 1; }

if [[ "$SIGN" == yes && "$APK" != *-signed.apk ]]; then
    echo "asked to sign, but only an unsigned .apk was produced: $APK" >&2
    exit 1
fi

printf '%s — %s\n' "$APK" "$(du -h "$APK" | cut -f1)"

if [[ "$INSTALL" == yes ]]; then
    # The SDK's own adb before whatever is on PATH: platform-tools is where the
    # one matching this SDK lives, and a distro-packaged adb of a different
    # vintage is the kind of mismatch that shows up as "device unauthorized".
    ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
    [[ -x "$ADB" ]] || ADB=$(command -v adb) || {
        echo "no adb — install platform-tools into the SDK" >&2; exit 1; }

    [[ -n "$("$ADB" devices | sed '1d;/^$/d')" ]] || {
        echo "no device: plug a phone in with USB debugging on, or start an emulator" >&2
        exit 1; }

    # -r replaces an already-installed copy rather than failing on it
    "$ADB" install -r "$APK"
    printf 'installed. Its log: %s logcat -s mtgdeck:* Qt:*\n' "$ADB"
fi
