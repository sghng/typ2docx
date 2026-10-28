ROOT := justfile_directory()

default: build

build:
  "{{ROOT}}/build-typst.sh"
  test -f "{{ROOT}}/pandoc/cabal.project" || { echo "Run git submodule update --init --recursive first"; exit 1; }
  cd "{{ROOT}}/pandoc" && cabal build --ghc-options=-Werror exe:pandoc
  mkdir -p "{{ROOT}}/.build/bin"
  cp "$(cd "{{ROOT}}/pandoc" && cabal list-bin exe:pandoc)" "{{ROOT}}/.build/bin/pandoc"

install: build
  #!/bin/sh
  set -eu
  bin="$HOME/.local/bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'exec bun "{{ROOT}}/cli.ts" "$@"' > "$bin/typ2docx"
  chmod +x "$bin/typ2docx"
  echo "Installed $bin/typ2docx; toolchains remain under {{ROOT}}/.build/bin"
