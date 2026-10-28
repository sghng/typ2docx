# typ2docx

Typst-to-Word conversion for academic manuscripts, built around pandoc with
local reader and writer fixes, APA reference styles, Lua filters, float
measurement, and DOCX post-processing.

The previous standalone implementation is preserved on `legacy` and in the
`v0.9.0` release. The pandoc-based implementation is on `main`.

## Toolchain

- `pandoc/` is a submodule tracking the custom pandoc fork's `main` branch.
- `tools/build-typst.sh` builds Typst and Hayagriva at pinned, mutually
  compatible upstream commits. Their sources and all build artifacts stay in
  the ignored `.build/` directory, so no forks or additional submodules are
  required.
- `tools/build-reference.sh` rebuilds the APA reference stock from its patch
  series.

The Typst build requires git, Cargo with Rust 1.92 or newer, and network
access on the first run.

Initialize the pandoc submodule and build Typst:

```sh
git submodule update --init --recursive
tools/build-typst.sh
```

The script produces `.build/bin/typst`. Use this binary for converter steps
that need the pinned Typst and Hayagriva toolchain.

## Convert

```sh
bun typ2docx/cli.ts <file.typ>
```

The command writes a DOCX beside the source file.
