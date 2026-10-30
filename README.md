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
| Validation | Semantic invariants, schema validation, and rendered-page review |

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

Rendered checks run through documented out-of-tree manuscript and
response-letter reproductions. Focused equation-manifest and DOCX/PDF parsing
tests also run with `bun test equations.test.ts`; they supplement rather than
replace rendered-page review.

Compare rendered output against the APA rubric, not against the Typst PDF
pixel-for-pixel. LibreOffice renders are useful for automated inspection, but
they do not replace manual review in Word when rendering differences matter.

## Toolchain

- `pandoc/` is a submodule tracking the custom pandoc fork's `main` branch.
- `typst-hs/` pins a temporary Typst parser fix for shorthand references
  containing punctuation. Retire it once upstream releases the fix.
- `build-typst.sh` builds Typst and Hayagriva at pinned, mutually
  compatible upstream commits. Their sources and all build artifacts stay in
  the ignored `.build/` directory, so no forks or additional submodules are
  required.
- `build-reference.sh` rebuilds the APA reference stock from its patch
  series.

The Typst build requires git, Cargo with Rust 1.92 or newer, and network
access on the first run. The pandoc build requires GHC and Cabal. Conversion
also requires Bun, LibreOffice (`soffice`, with the Writer and Math modules),
Poppler (`pdftotext`), and `zip`, `unzip`, and `patch`.

Initialize the pandoc submodule and build Typst:

```sh
git submodule update --init --recursive
build-typst.sh
```

The script produces `.build/bin/typst`. Use this binary for converter steps
that need the pinned Typst and Hayagriva toolchain.

## Build and install

`just build` compiles the pinned Typst and pandoc toolchains into
`.build/bin`. `just install` performs the same build and installs only the
`typ2docx` command under `~/.local/bin`. Pandoc and Typst remain repo-local.

```sh
just install
```

Ensure `~/.local/bin` is on your `PATH`, then run `typ2docx <file.typ>`.

## Convert

```sh
bun cli.ts <file.typ>
```

The command writes a DOCX beside the source file.

## House policy

- Every table and figure floats, by house policy. Real manuscripts never
  write placement, so the filter stamps `placement = auto` on all of them.
- The Typst source carries content only. Word style lives in the reference
  stock, never in the source and never in the filter. The filter maps
  semantics; the stock owns appearance.
- The numbered patch series in `patches/` is the single source of truth for
  the stock. The build exports pandoc's pristine reference docx with the
  repo-local binary, applies the `NN-*.patch` series in order with `--fuzz=0`,
  and repacks. Template drift fails at the offending patch. `--max-patch N`
  bisects the series, and every conversion rebuilds a fresh stock into a
  private temp dir so there is no committed stock or dual-source drift.

## Division of labor

- `filter.lua` normalizes captured block and box fills and `highlight` mark
  regions onto pandoc's native mark handling and the default text highlight
  pen. Every pen span the filter mints is bare so the writer's pen matcher
  sees it. Marked code becomes a Code inline under a Source Code
  custom-style div.
- `floats.ts` renders token-injected AST copies through LibreOffice and moves
  whole nodes until each float lands unsplit within one page of its authored
  position. A marked region ending in a table hoists it out, and nested
  floats move only with their highlight region.
- `chain.ts` performs XML surgery on the pandoc-produced DOCX: `cantSplit`
  rows, `keepNext` chains, and caption riding. The keep-together recipe lives
  here because it is house policy, not a writer default.

## Anchors and equation numbers

Typst owns reference and display numbering. The CLI evaluates `anchors.typ`
through the repo-local `typst eval --in` and passes the resulting map to the
filter through `TYP2DOCX_ANCHORS`. Heading and equation sequences are checked
against the AST before use; a mismatch warns and leaves numbering unchanged.

The filter replaces only automatic reference placeholders of the form
`[label]`. Explicit supplements and citations stay untouched, and links keep
their targets. Numbered headings take their displayed ordinal from the map,
except appendix headings, which keep the house label treatment.

A numbered display equation stays OMML and moves into a borderless
6%/88%/6% three-column layout table with a blank left cell, the equation in
the widened center, and its number at the right. Equal narrow gutters keep
the equation centered without taking away a fifth of its available width,
while leaving room for two-digit parenthesized equation numbers.
The `Equation` stock style removes inherited
rules, cell margins, and the default table indent. These tables have no
placement attribute and empty captions, so they neither float nor consume
Table sequence numbers. The equation label moves onto the visible number,
which gives internal links a real bookmark target.

## Equation layout diagnostics

After the final DOCX is written, the converter performs one best-effort
LibreOffice layout pass for display equations. A diagnostic DOCX copy receives
the usual narrow inline measurement tokens; the delivered DOCX is never
patched. PDF content bounds identify clear horizontal overflow, and
cross-page displacement is reported as a possible wrap. Numbered equations
are measured in their table cells rather than against an assumed full-width
paragraph. Same-page marker movement is not treated as proof of wrapping:
LibreOffice can move markers around a tall formula object without adding a
second equation line. Consequently, this conservative check can miss
same-page automatic wrapping.

A warning includes the equation ordinal and its actual label; the displayed
number is included when the anchor sequence and labels align. For example:

```text
typ2docx: warning: display equation (4) <eq:model> may wrap or overflow in the LibreOffice layout; review manual line breaking
```

Accurate source-line reporting requires a separate upstream `typst-hs` change:
its evaluated equation nodes currently do not retain usable source spans.

The check is nonfatal and never rewrites mathematics. Authored multiline and
alignment structures are skipped in this initial version, so their deliberate
rows are not reported as accidental wrapping. Missing markers or a failed
render suppress the affected verdict and produce their own warning. This is a
LibreOffice layout diagnostic, not a guarantee of Word's line breaking.

## Measurement discipline

- No render may contain an object the delivered DOCX lacks. Measurement uses
  inline token runs in per-pass render copies only. Sentinel paragraphs are
  forbidden because they change keepNext page-break arithmetic.
- The float's end token rides inside the float itself; a marker at a page top
  no longer counts as spill or over-tall. Swap cycles are cut by full
  block-order signatures, and the cheapest measured layout is kept.
- `pdftotext -bbox` output goes to a file because a full manuscript overflows
  the subprocess stdout buffer.

## Word versus LibreOffice

Render checks through LibreOffice do not guarantee the same result in Word.
Word lays an oMathPara out as display only when its paragraph holds no other
run, so the filter chops marked equations into their own span-wrapped
paragraphs. Word also handles table-adjacent spacing differently, which is
why caption and post-table spacing live in the stock and writer boundary
marks rather than line spacing. When a defect is Word-side, inspect the probe
document in Word before accepting a fix.

## Upstream dependencies

Anchor evaluation uses `.build/bin/typst`, built from the pinned compatible
Typst and Hayagriva revisions. Pandoc uses `.build/bin/pandoc`, built from the
submodule. Neither tool is selected through `PATH`, so a system installation
cannot silently mask a stale or incompatible local build.

Citation style is APA through a hash-pinned CSL, with native numbering and
tight bibliography spacing. Appendix headings get page breaks, a label line
lettered only when there is more than one appendix, and a line break before
the title. The references section starts on a new page.
