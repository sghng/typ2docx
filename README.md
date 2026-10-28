# typ2docx

Typst-to-Word conversion for academic manuscripts, built around pandoc with
local reader and writer fixes, APA reference styles, Lua filters, float
measurement, and DOCX post-processing.

The previous standalone implementation is preserved on `legacy` and in the
`v0.9.0` release. The pandoc-based implementation is on `main`.

## Project purpose

Typst is a semantic substrate for academic writing. Word is the interchange
format for publishers, reviewers, and collaborators who do not accept or use
Typst. This project exists because the available conversion paths do not
produce satisfactory academic Word documents.

The goal is nearly perfect APA-style Word output, not a pixel-for-pixel copy
of Typst's rendering. Typst supplies content and semantic structure. The
converter owns presentation, including APA styles, pagination, table layout,
and DOCX-specific behavior.

Two kinds of fidelity matter:

1. **Semantic fidelity** preserves text, citations, labels, cross-references,
   mathematics, table structure, captions, notes, and revision markings.
   Missing characters and altered meaning are always defects.
2. **APA presentation** produces readable, valid, publication-quality Word
   output according to the project's documented house rules.

APA requirements take precedence over both Typst's appearance and immediate
aesthetic preferences. For example, APA body text is normally left aligned,
and genuine long quotations receive block indentation. Ordinary body
paragraphs must not accidentally acquire either treatment.

## Layer responsibilities

| Layer | Responsibility |
| --- | --- |
| Typst source | Content and semantic roles only |
| `reference.docx` | Declarative APA styles such as fonts, spacing, alignment, and indentation |
| Lua filter | Structural normalization, such as compact cell paragraphs and caption or note grouping |
| Pandoc and its fork | Reader and writer behavior that is upstreamable or difficult to represent correctly elsewhere |
| CLI and layout code | Measurement, pagination, table layout, and DOCX post-processing |
| Tests | Semantic invariants, schema validation, and rendered-page review |

Source edits are appropriate when the semantic markup is wrong or incomplete,
or when the source is the cleanest place to express a content-level decision.
They require the manuscript owner's consent. Typst source must not become a
container for Word-specific layout hacks.

## Upstream policy

The pandoc fork is an integration and staging branch, not a collection of
unexamined workarounds. Every converter change should be classified by where
it belongs.

For a genuine upstream bug or a reasonable upstream feature gap:

- Fix it at the correct upstream layer.
- Add a focused regression test and reproduce the problem against stock
  behavior.
- Carry the fix in the fork while it is needed.
- Submit a small, independently reviewable upstream PR.
- Remove the local patch after upstream acceptance makes it redundant.

For APA-specific or pipeline-specific behavior:

- Keep the change in `typ2docx` in the reference stock, filter, or layout code.
- Do not present house policy as a universal pandoc default.

For a defect in another dependency, prefer an upstream fix over a Lua or
post-processing workaround. If the fix is merged but unreleased, build a
pinned, compatible upstream revision. Retire the override when compatible
releases make it unnecessary. This is the policy used for Typst and
Hayagriva.

Upstream merges should be regular, and each local commit should be identified
as an upstream candidate or a deliberate local enhancement.

## Validation

A successful conversion and valid XML are only baseline checks. Acceptance
has three levels:

1. **Content checks** establish that no text, citations, labels, or structure
   are lost or corrupted.
2. **APA checks** establish that styles and document relationships follow the
   documented house rules.
3. **Rendered-page checks** establish that pages have no clipping, garbled
   headers, inflated rows, stranded floats, or unreadable spacing.

Compare rendered output against the APA rubric, not against the Typst PDF
pixel-for-pixel. LibreOffice renders are useful for automated inspection, but
they do not replace manual review in Word when rendering differences matter.

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
