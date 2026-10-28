#!/bin/sh
# Build Typst and Hayagriva at pinned upstream commits. Both source trees and
# all build artifacts stay in the ignored .build directory; no fork or
# submodule is required.
set -eu
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="$ROOT/.build/typst-head"
TYPST_REV="fe537181def05ba2760e305befd4fe8d245f06ce"
# Last commit before Hayagriva replaced serde_yaml with yaml_serde. Typst
# HEAD still expects serde_yaml. This commit already includes the citation
# disambiguation rework from typst/hayagriva#413.
HAYAGRIVA_REV="93f2bd3a89375fe882c9507ee16801d956e74523"

checkout() {
  url="$1"
  rev="$2"
  dest="$3"
  if [ ! -d "$dest/.git" ]; then
    if [ -e "$dest" ]; then
      echo "$dest exists but is not a git checkout" >&2
      exit 1
    fi
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
  fi
  if ! git -C "$dest" cat-file -e "$rev^{commit}" 2>/dev/null; then
    git -C "$dest" fetch -q --depth 1 origin "$rev"
  fi
  git -C "$dest" checkout -q --detach -f "$rev"
}

mkdir -p "$BUILD" "$ROOT/.build/bin"
checkout "https://github.com/typst/typst.git" "$TYPST_REV" "$BUILD/typst"
checkout "https://github.com/typst/hayagriva.git" "$HAYAGRIVA_REV" "$BUILD/hayagriva"

CARGO_TARGET_DIR="$BUILD/target" cargo \
  --config "patch.crates-io.hayagriva.path=\"$BUILD/hayagriva\"" \
  build --release --manifest-path "$BUILD/typst/Cargo.toml" --package typst-cli
if ! CARGO_TARGET_DIR="$BUILD/target" cargo \
  --config "patch.crates-io.hayagriva.path=\"$BUILD/hayagriva\"" \
  tree --manifest-path "$BUILD/typst/Cargo.toml" -i hayagriva |
  grep -F "$BUILD/hayagriva" >/dev/null; then
  echo "Cargo did not select the pinned Hayagriva checkout" >&2
  exit 1
fi
cp "$BUILD/target/release/typst" "$ROOT/.build/bin/typst"
"$ROOT/.build/bin/typst" --version
