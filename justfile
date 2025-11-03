clean:
    rm -rf target/ typ2docx.* *.docx *.pdf *.xml uv.lock Cargo.lock

pack-docx DIR OUTPUT:
    cd "{{DIR}}" && zip -r -q "../{{OUTPUT}}" *

unpack-docx DOCX OUTDIR:
    unzip -o -q "{{DOCX}}" -d "{{OUTDIR}}"

compile-with-preamble INPUT OUTPUT:
    cat preamble.typ "{{INPUT}}" | typst c - {{OUTPUT}}
