#!/bin/sh
set -e
rm -rf a.d b.d out.d
unzip -o -q a.docx -d a.d &
unzip -o -q b.docx -d b.d &
wait
rsync -a --delete a.d/ out.d/
python3 -m saxon >out.d/word/document.xml
cd out.d # must be zipped from inside!
zip -r -q ../out.docx *
