#!/bin/sh
# Build the house reference docx into reference/ (the lab-reference alias
# target): export pandoc's pristine reference docx, unpack it, apply every
# *.patch in this directory (alphabetical order), repack. Each patch names
# one house style concern, so a pandoc upgrade that changes the template
# fails the build at the offending patch. The artifact stays a zip (pandoc
# requires a real docx container).
set -eu
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

rm -rf work && mkdir work
pandoc -o work/pristine.docx --print-default-data-file reference.docx
unzip -q work/pristine.docx -d work/unpacked
for p in *.patch; do
  echo "applying $p"
  patch -d work/unpacked -p1 --batch --forward -i "$PWD/$p"
done
(cd work/unpacked && zip -q -r -X "$ROOT/reference/reference.docx" . -x '*.DS_Store')
echo "built $ROOT/reference/reference.docx"
