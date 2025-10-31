#!/bin/bash
set -euo pipefail

unzip -q typ2docx.a.docx -d typ2docx.a.d
unzip -q typ2docx.b.docx -d typ2docx.b.d

echo Pretending to do some operation...
wc -c typ2docx.a.d/word/document.xml

cd typ2docx.a.d # must be zipped from inside!
zip -r -q ../typ2docx.out.docx *
