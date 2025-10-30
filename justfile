clean:
    rm -rf *.docx *.marked *.pdf target/

add-marker file:
    echo '#import "marker.typ": marker; #show: marker' > {{file}}.marked
    cat {{file}} >> {{file}}.marked

extract-math file:
    cargo run --quiet -- {{file}}
