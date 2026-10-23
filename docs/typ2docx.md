# typ2docx

The Typst-to-Word converter behind `abstract typ2docx`, as a contract
rather than a diary. Layout is `typ2docx/` (cli.ts the command, filter.lua
the content adjustments, floats.ts the placement fixpoint, chain.ts the
keep-together chain); `tools/` holds the reference stock concern.

## Policy

- Every table and figure floats, by house policy. Real manuscripts never
  write placement, so the filter stamps `placement = auto` on all of them.
- The Typst source carries content only. Word style lives in the reference
  stock, never in the source and never in the filter: the writer can
  reference styles but cannot define them, so per-instance formatting
  through filters would lose inheritance, docDefaults, and theme fonts.
  The filter maps semantics; the stock owns appearance.
- The numbered patch series in `tools/` is the single source of truth for
  the stock. The build exports pandoc's pristine reference docx with
  whatever `pandoc` is on `PATH`, applies the `NN-*.patch` series in order
  with `--fuzz=0`, and repacks. A pandoc whose template drifted from the
  one the patches were cut against fails at the offending patch. `--max-patch
  N` bisects (0 is the pristine export; partial builds write
  `reference/reference.debug.docx`). Every conversion rebuilds a fresh
  stock into a private temp dir (~100 ms warm), so there is no committed
  stock and no dual-source drift. Built docx artifacts are gitignored.

## Division of labor

- The filter normalizes captured block/box fills and `highlight` mark
  regions onto pandoc's native mark handling and the default text highlight
  pen, and the writer pens every run inside a mark: text, OMML math, and
  caption supplements. Every pen span the filter mints is bare (the
  writer's pen matcher sees bare spans only). A marked code block re-voices
  itself as a Code inline under a Source Code custom-style div, where the
  same span pens it.
- The fixpoint (floats.ts) renders token-injected AST copies through
  soffice and moves whole nodes until each float lands unsplit within one
  page of its authored position. A marked region ending in a table hoists
  it out (the following paragraph regains its `FirstParagraph` margin);
  nested floats are movable as long as the highlight travels with the
  float (each is lifted into its own mark-wrapped unit at the same spot).
- The chain (chain.ts) is XML surgery on the pandoc-produced docx
  (cantSplit rows, keepNext chain, caption riding): the keep-together
  recipe lives here, not in a forked writer, because the house policy is
  float-everything and the reader has nothing to carry. Pandoc stays
  pristine lab-stack.

## Measurement discipline

- No render may contain an object the delivered docx lacks. Measurement
  uses inline token runs (white, 12 pt, `w:w=30`, the pdftotext wholeness
  floor, matched as substrings since pdftotext merges them into neighbor
  words) prepended/appended inside existing paragraphs of per-pass render
  copies only. Sentinel paragraphs are forbidden: a scaffolding paragraph
  changes LibreOffice's keepNext page-break arithmetic, so a layout
  measured with sentinels is not the delivered layout (observed once as a
  68-page fixpoint optimizing a 69-page render).
- The float's end token rides inside the float itself; a marker sitting at
  a page top no longer counts as spill or over-tall. Swap cycles are cut
  by full-block-order signatures, and the cheapest measured layout is
  kept.
- `pdftotext -bbox` output goes to a file; a full manuscript overflows
  spawnSync's stdout buffer.

## Word vs LibreOffice

Render checks through soffice pass while Word fails whenever the two
engines disagree. Divergences on record: Word lays an oMathPara out as
display only when its paragraph holds no other run (revision marks embed
equations in mark spans, so the filter must chop them into their own
span-wrapped paragraphs); Word applies none of a paragraph's line-spacing
lead before or after a table (caption and post-table spacing live in the
stock and the writer's boundary marks, not in line spacing); Word's
built-in Caption is not italic and pristine pandoc headings are not bold.
Measurement is honest only against the engine that will print it, so when
a defect is Word-side, the probe document must be opened in Word before
believing a fix.

## Upstream dependencies

The pandoc reader/writer fixes this pipeline leans on are local builds on
`~/.local/bin` ahead of release (highlight parsing, OMML penning, caption
label penning, table column widths, table-boundary marks, math
continuations). Keep the symlink ahead of the system pandoc until they
land upstream, and rebuild-refresh-verify after every lab-stack change:
a stale binary there has silently masked a fix before.

Citation style is APA through a hash-pinned CSL cached in the abstract
home, with native numbering and tight bibliography spacing. Appendix
headings get page breaks, a label line lettered only when there is more
than one appendix, and a line break before the title. The references
section starts on a new page.
