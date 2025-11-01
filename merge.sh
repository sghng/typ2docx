#!/bin/bash
set -euo pipefail

unzip -o -q typ2docx.a.docx -d typ2docx.a.d
unzip -o -q typ2docx.b.docx -d typ2docx.b.d

# dummy input/output
saxon -s:empty.xml -xsl:merge.xslt -o:output.xml

cd typ2docx.a.d # must be zipped from inside!
zip -r -q ../typ2docx.out.docx *
