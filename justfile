clean:
    rm -rf *.docx *.pdf *.xml __pycache__/ dist/ target/ .typ2docx/

# PKG_NAMES := "adaptable-pset graceful-genetics splendid-mdpi"

PKG_NAMES := "adaptable-pset"

[working-directory("tests")]
init-tests:
    #!/usr/bin/env fish
    for pkg in {{ PKG_NAMES }}
        echo "Initializing $pkg..."
        rm -rf $pkg
        typst init "@preview/$pkg" &
    end
    wait

[working-directory("tests")]
run-test PKG_NAME="":
    #!/usr/bin/env fish
    if test -z "{{ PKG_NAME }}"
        for pkg in {{ PKG_NAMES }}
            echo "Testing $pkg..."
            just run-test $pkg
        end
        wait
    else
        echo "Running test for {{ PKG_NAME }}..."
        typ2docx {{ PKG_NAME }}/main.typ -o {{ PKG_NAME }}/output.docx -e pdf2docx
    end

test-pdfservices:
    dotenv -- ./main.py -e pdfservices tests/dir/main.typ -- --root tests

test-acrobat:
    ./main.py -e acrobat tests/dir/main.typ -- --root tests

pack-docx DIR OUTPUT:
    cd "{{ DIR }}" && zip -r -q "../{{ OUTPUT }}" *

unpack-docx DOCX OUTDIR:
    unzip -o -q "{{ DOCX }}" -d "{{ OUTDIR }}"

compile-with-preamble INPUT OUTPUT:
    cat preamble.typ "{{ INPUT }}" | typst c - {{ OUTPUT }}
