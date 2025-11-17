clean:
    rm -rf *.docx *.pdf *.xml __pycache__/ dist/ target/ .typ2docx/

test-pdfservices:
    dotenv -- ./main.py -e pdfservices tests/dir/main.typ -- --root tests

test-acrobat:
    ./main.py -e acrobat tests/dir/main.typ -- --root tests

pack-docx DIR OUTPUT:
    cd "{{DIR}}" && zip -r -q "../{{OUTPUT}}" *

unpack-docx DOCX OUTDIR:
    unzip -o -q "{{DOCX}}" -d "{{OUTDIR}}"

compile-with-preamble INPUT OUTPUT:
    cat preamble.typ "{{INPUT}}" | typst c - {{OUTPUT}}
