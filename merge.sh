#!/bin/bash
set -euo pipefail

unzip -o -q typ2docx.a.docx -d typ2docx.a.d
unzip -o -q typ2docx.b.docx -d typ2docx.b.d
rsync -a --delete typ2docx.a.d/ typ2docx.out.d/

# dummy input/output
saxon -s:empty.xml -xsl:merge.xslt -o:typ2docx.out.d/word/document.xml

cd typ2docx.out.d # must be zipped from inside!
zip -r -q ../typ2docx.out.docx *
