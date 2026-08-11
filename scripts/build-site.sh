#!/usr/bin/env bash
#
# Assemble the deployable site into site/ — the landing page at the root, the
# WebAssembly build under app/.
#
#   ./scripts/build-site.sh          use the existing build-wasm/
#   ./scripts/build-site.sh --build  rebuild it first
#
# The result is plain static files with no server-side anything, so it can go on
# any static host. Two requirements of whatever serves it:
#
#   * .wasm must be sent as application/wasm, or the browser cannot
#     stream-compile and buffers all 35 MB before it starts.
#   * compression on. The payload is ~52 MB raw and ~17 MB gzipped; serving it
#     uncompressed triples what a visitor waits for.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site"
WASM="$ROOT/build-wasm"

if [[ "${1:-}" == "--build" ]]; then
    [[ -n "${EMSDK:-}" ]] || { echo "source ~/emsdk/emsdk_env.sh first" >&2; exit 1; }
    cmake --build "$WASM"
fi

[[ -f "$WASM/mtgdeck.wasm" ]] || {
    echo "no build-wasm/mtgdeck.wasm — see the README's browser build section" >&2
    exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT/app"

cp -r "$ROOT/web/." "$OUT/"
# Only the five files the page actually loads; build-wasm/ is full of CMake.
cp "$WASM"/mtgdeck.{html,js,wasm,data} "$WASM/qtloader.js" "$OUT/app/"

# The generated shell titles itself "mtgdeck", which is the CMake target name
# and not what anyone should see in a tab or a bookmark.
sed -i 's|<title>mtgdeck</title>|<title>Command Creation</title>|' "$OUT/app/mtgdeck.html"

raw=$(du -sb "$OUT" | cut -f1)
gz=$(find "$OUT" -type f -exec gzip -9c {} + | wc -c)
printf 'site/ ready — %s raw, ~%s gzipped\n' \
    "$(numfmt --to=iec "$raw")" "$(numfmt --to=iec "$gz")"
printf 'preview: python3 -m http.server 8765 --directory %s\n' "$OUT"
