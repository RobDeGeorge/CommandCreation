#!/usr/bin/env bash
#
# Publish site/ to GitHub Pages, at robdegeorge.com/CommandCreation/.
#
#   ./scripts/deploy-site.sh            assemble site/ from the current wasm build, then push
#   ./scripts/deploy-site.sh --build    rebuild the wasm first (passed to build-site.sh)
#
# Takes WASM_BUILD=<dir> the same way build-site.sh does.
#
# The site goes out as a single orphan commit force-pushed to gh-pages, so the
# ~53 MB of build never piles up in any branch's history: each deploy replaces
# the last one outright. Pages serves that branch, and because the account's
# user site (RobDeGeorge.github.io) owns robdegeorge.com, this repo's project
# site lands under it at /CommandCreation/. The lowercase /commandcreation/ is a
# redirect that lives in the website repo.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site"

"$ROOT/scripts/build-site.sh" "$@"

# No Jekyll: it has nothing to do here and would only slow the publish.
touch "$OUT/.nojekyll"

remote=$(git -C "$ROOT" remote get-url origin)
source_rev=$(git -C "$ROOT" rev-parse --short HEAD)
dirty=$(git -C "$ROOT" status --porcelain --untracked-files=no | grep -q . && echo " (+ uncommitted changes)" || true)

# A throwaway repo rather than a worktree, so nothing about gh-pages ever
# touches the working copy or its index.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b gh-pages
git -C "$tmp" --work-tree="$OUT" add -A
git -C "$tmp" --work-tree="$OUT" \
    -c user.name="$(git -C "$ROOT" config user.name)" \
    -c user.email="$(git -C "$ROOT" config user.email)" \
    commit -q -m "Site built from $source_rev$dirty"
git -C "$tmp" push -q -f "$remote" gh-pages

echo "pushed gh-pages — live at https://robdegeorge.com/CommandCreation/ in a minute or two"
