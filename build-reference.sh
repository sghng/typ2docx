#!/bin/sh
# Build the house reference docx (the pandoc reference doc that styles every
# Word export): export pandoc's pristine reference docx, unpack it, apply
# the numbered patch series in order, repack. Each patch names one house
# style concern, so a pandoc upgrade that changes the template fails the
# build at the offending patch. The artifact stays a zip (pandoc requires a
# real docx container).
#
# The numbers are the canonical order. One order fact is load-bearing: the
# float hunks of 03-first-line-indent carry jc="center" context that only
# exists after 02-center-figures-tables. fuzz=0 makes any drift (wrong
# order, changed template) fail loudly instead of re-anchoring a hunk.
#
# Nothing is cached: typ2docx rebuilds a fresh stock into a
# private temp dir on every conversion (--out below), so the patch series
# is the single source of truth. A manual invocation writes
# .build/reference.docx (ignored). --max-patch N applies only the first N
# patches and writes .build/reference.debug.docx; 0 means the pristine export
# untouched, for examining pandoc's defaults.
set -eu
cd "$(dirname "$0")"
ROOT="$PWD"
cd "$ROOT/patches"

OUT=""
MAX_PATCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || { echo "--out needs a value" >&2; exit 1; }
      OUT="$2"
      shift 2
      ;;
    --max-patch)
      [ $# -ge 2 ] || { echo "--max-patch needs a value" >&2; exit 1; }
      MAX_PATCH="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
if [ -n "$MAX_PATCH" ]; then
  case "$MAX_PATCH" in
    ''|*[!0-9]*)
      echo "--max-patch wants a non-negative integer, got: $MAX_PATCH" >&2
      exit 1
      ;;
  esac
fi

for p in *.patch; do
  case "$p" in
    [0-9][0-9]-*.patch) ;;
    *)
      echo "unnumbered patch name: $p (NN-name.patch required)" >&2
      exit 1
      ;;
  esac
done

TOTAL=0
for p in [0-9][0-9]-*.patch; do
  TOTAL=$((TOTAL + 1))
done
if [ -n "$MAX_PATCH" ] && [ "$MAX_PATCH" -gt "$TOTAL" ]; then
  echo "only $TOTAL patches exist; --max-patch $MAX_PATCH is out of range" >&2
  exit 1
fi

PANDOC="$ROOT/.build/bin/pandoc"
if [ ! -x "$PANDOC" ]; then
  echo "$PANDOC is missing; run just build first" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/refbuild.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM
"$PANDOC" -o "$WORK/pristine.docx" --print-default-data-file reference.docx
unzip -q "$WORK/pristine.docx" -d "$WORK/unpacked"

APPLIED=0
for p in [0-9][0-9]-*.patch; do
  if [ -n "$MAX_PATCH" ] && [ "$APPLIED" -eq "$MAX_PATCH" ]; then
    echo "stopping after $APPLIED patches (skipping $p and the rest)"
    break
  fi
  echo "applying $p"
  patch -d "$WORK/unpacked" -p1 --batch --forward --fuzz=0 -i "$PWD/$p"
  APPLIED=$((APPLIED + 1))
done

if [ -n "$MAX_PATCH" ]; then
  DEST="$ROOT/.build/reference.debug.docx"
  NOTE=" ($APPLIED of $TOTAL patches)"
elif [ -n "$OUT" ]; then
  DEST="$OUT"
  NOTE=""
else
  DEST="$ROOT/.build/reference.docx"
  NOTE=""
fi
mkdir -p "$(dirname "$DEST")"
(cd "$WORK/unpacked" && zip -q -r -X "$DEST" . -x '*.DS_Store')
echo "built $DEST$NOTE"
