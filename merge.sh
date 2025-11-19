#!/bin/sh
set -e

unzip -o -q a.docx -d a.d
unzip -o -q b.docx -d b.d
rsync -a --delete a.d/ out.d/

python3 -m saxon >out.d/word/document.xml

cd out.d # must be zipped from inside!
zip -r -q ../out.docx *
