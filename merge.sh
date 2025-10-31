#!/bin/bash
set -euo pipefail

unzip -q typ2docx.a.docx -d typ2docx.a.d
unzip -q typ2docx.b.docx -d typ2docx.b.d

saxon -s:typ2docx.a.d/word/document.xml \
      -xsl:merge.xslt \
      -o:typ2docx.a.d/word/document.xml \
      doc-b-path=typ2docx.b.d/word/document.xml

cd typ2docx.a.d # must be zipped from inside!
zip -r -q ../typ2docx.out.docx *
