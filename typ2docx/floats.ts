/**
 * typ2docx/floats.ts -- float placement fixpoint for Word export.
 *
 * Blocks carrying a `placement` attr keyval (stamped on every table and
 * figure by filter.lua, the house float-by-default policy) must land
 * unsplit within one page of their authored position, with minimal
 * whitespace disturbance. chain.ts gives every such block soft atomicity
 * (cantSplit + keepNext chain) in the rendered docx; this module runs
 * the render-measure-move loop on top:
 *
 *   loop, capped at ~2n+5 passes:
 *     inject inline token runs into a render copy (measurement only)
 *     pandoc json -> docx (house reference doc) -> soffice pdf
 *     measure token positions (pdftotext -bbox)
 *     score every float's current spot against movable candidates
 *     apply strictly improving moves (whole nodes only, never edited)
 *   final: the working state itself (tokens never enter it, so the
 *     delivered blocks are pristine)
 *
 * Measurement uses inline token runs, never sentinel paragraphs: a
 * paragraph of scaffolding changes LibreOffice's keepNext page-break
 * arithmetic (verified empirically: one plain 1pt paragraph between
 * prose and a chain flips a near-fit float across a page), so the
 * measured layout must not contain any object the delivered docx
 * lacks. Tokens are white 12pt text at 10% character width inside
 * existing paragraphs: they carry the exact line geometry (start
 * tokens read line tops, end tokens read line bottoms) and add about
 * three points of width, which can only make the measurement
 * conservative, never optimistic.
 *
 * The origin of a float is its authored AST position, estimated by
 * the nearest non-float block (non-floats never move in the working
 * state): the allowed landing range {p-1, p, p+1} (p = origin page)
 * re-derives every pass.
 */

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chainDocx } from "./chain.ts";

/* -- pandoc JSON plumbing ------------------------------------------------- */

export type Block = { t: string; c?: unknown };
type Inline = { t: string; c?: unknown };
export type PandocDoc = {
  "pandoc-api-version": number[];
  meta: unknown;
  blocks: Block[];
};

type Attr = [string, string[], [string, string][]];

/** Attr tuple of blocks that carry one (Table, Figure, Div, CodeBlock,
 *  Header); null for everything else. */
function attrOf(b: Block): Attr | null {
  if (!Array.isArray(b.c)) return null;
  if (b.t === "Table" || b.t === "Figure" || b.t === "Div") return b.c[0];
  if (b.t === "CodeBlock") return b.c[0];
  if (b.t === "Header") return (b.c as unknown[])[1] as Attr;
  return null;
}

function placementOf(b: Block): string | null {
  const attr = attrOf(b);
  if (!attr) return null;
  const kv = attr[2].find(([k]) => k === "placement");
  return kv ? kv[1] : null;
}

/** Top-level blocks marked as floats by the house filter (placement
 *  keyval; every table and figure by default, note units included). */
export function findFloats(blocks: Block[]): Block[] {
  return blocks.filter((b) => placementOf(b) !== null);
}

/** Floated blocks nested inside containers (mark Divs): the chain keeps
 *  them whole, but moving them would rip them out of their region, so
 *  the fixpoint leaves them alone. A block that itself carries placement
 *  is a unit (e.g. a bundled float and its note); its contents are not
 *  counted separately. */
export function countNestedFloats(blocks: Block[]): number {
  let n = 0;
  const walk = (bs: Block[]) => {
    for (const b of bs) {
      if (placementOf(b) !== null) {
        n++;
        continue;
      }
      if (b.t === "Div" && Array.isArray(b.c))
        walk((b.c as unknown[])[1] as Block[]);
    }
  };
  walk(blocks);
  return n - findFloats(blocks).length;
}

/* -- inline tokens -------------------------------------------------------- */

/**
 * Token runs are measurement scaffolding: unique tokens in white 12pt
 * text at 10% character width (LibreOffice honors w:w; the glyph keeps
 * the full line box at negligible width). They live only in per-pass
 * render copies. The "XQ" prefix plus three base36 digits cannot occur
 * as a natural word, so bbox words are matched by format alone.
 */
function tokenXml(token: string): string {
  return (
    `<w:r><w:rPr><w:color w:val="FFFFFF"/><w:w w:val="30"/>` +
    `<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>` +
    `<w:t>${token}</w:t></w:r>`
  );
}

function tokenRun(token: string): Inline {
  return { t: "RawInline", c: ["openxml", tokenXml(token)] };
}

const B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
function token(n: number): string {
  let s = "";
  for (let i = 0; i < 3; i++) {
    s = B36[n % 36] + s;
    n = Math.floor(n / 36);
  }
  return `XQ${s}`;
}

/** The inline array that opens a block (for a start token). The input
 *  is unknown because containers can hold stray nulls and nested block
 *  lists (the filter's Figure content does). null when nothing in the
 *  block holds a paragraph (the measurement then reports the token as
 *  missing and the pass keeps the current placement). */
function firstInlines(b: unknown): Inline[] | null {
  if (Array.isArray(b)) {
    for (const el of b) {
      const r = firstInlines(el);
      if (r) return r;
    }
    return null;
  }
  if (!b || typeof b !== "object") return null;
  const blk = b as Block;
  if (blk.t === "Para" || blk.t === "Plain") return blk.c as Inline[];
  if (blk.t === "Header") return (blk.c as unknown[])[2] as Inline[];
  if ((blk.t === "Div" || blk.t === "Figure") && Array.isArray(blk.c))
    return firstInlines((blk.c as unknown[])[1]);
  if (blk.t === "Table" && Array.isArray(blk.c)) {
    // Table c: [attr, caption, colspecs, head, bodies, foot]; head and
    // foot are [attr, [rows]]; a body is [attr, rowHeadColumns,
    // [headRows], [bodyRows]]; a row is [attr, [cells]]; a cell is
    // [attr, align, rowspan, colspan, [blocks]].
    const t = blk.c as unknown[];
    const rowCells = (rows: unknown): Block[][][] =>
      Array.isArray(rows)
        ? (rows as unknown[]).map((r) => (r as unknown[])[1] as Block[][])
        : [];
    const sections = [
      ...rowCells((t[3] as unknown[])[1]),
      ...(t[4] as unknown[]).flatMap((body) => [
        ...rowCells((body as unknown[])[2]),
        ...rowCells((body as unknown[])[3]),
      ]),
      ...rowCells((t[5] as unknown[])[1]),
    ];
    for (const row of sections) {
      for (const cell of row) {
        const r = firstInlines(cell[4]);
        if (r) return r;
      }
    }
  }
  return null;
}

/** The inline array that closes a block (for an end token). */
function lastInlines(b: unknown): Inline[] | null {
  if (Array.isArray(b)) {
    for (let i = b.length - 1; i >= 0; i--) {
      const r = lastInlines(b[i]);
      if (r) return r;
    }
    return null;
  }
  if (!b || typeof b !== "object") return null;
  const blk = b as Block;
  if (blk.t === "Para" || blk.t === "Plain") return blk.c as Inline[];
  if (blk.t === "Header") return (blk.c as unknown[])[2] as Inline[];
  if ((blk.t === "Div" || blk.t === "Figure") && Array.isArray(blk.c))
    return lastInlines((blk.c as unknown[])[1]);
  if (blk.t === "Table" && Array.isArray(blk.c)) {
    const t = blk.c as unknown[];
    const rowCells = (rows: unknown): Block[][][] =>
      Array.isArray(rows)
        ? (rows as unknown[]).map((r) => (r as unknown[])[1] as Block[][])
        : [];
    const sections = [
      ...rowCells((t[3] as unknown[])[1]),
      ...(t[4] as unknown[]).flatMap((body) => [
        ...rowCells((body as unknown[])[2]),
        ...rowCells((body as unknown[])[3]),
      ]),
      ...rowCells((t[5] as unknown[])[1]),
    ];
    for (let s = sections.length - 1; s >= 0; s--) {
      const cells = sections[s];
      for (let ci = cells.length - 1; ci >= 0; ci--) {
        const r = lastInlines(cells[ci][4]);
        if (r) return r;
      }
    }
  }
  return null;
}

/* -- geometry ------------------------------------------------------------- */

type Geometry = {
  pageHeight: number; // pt
  textTop: number; // pt, y of text area top (PDF coords, origin top-left)
  textBottom: number; // pt, y of text area bottom
  textHeight: number; // pt
};

/** Page geometry from the rendered PDF itself. The house reference stock
 *  declares no pgSz/pgMar (Word/LO defaults apply: 1in margins), so the
 *  render is the only honest source. The page height is read off the PDF;
 *  margins take the OOXML default and the bottom self-calibrates upward
 *  to the lowest observed content, which covers locales whose default
 *  bottom margin is smaller. */
function geometryFromPdf(
  pageHeight: number,
  tokens: Map<string, Pt>,
): Geometry {
  const margin = 72;
  let textBottom = pageHeight - margin;
  for (const p of tokens.values()) textBottom = Math.max(textBottom, p.yMax);
  return {
    pageHeight,
    textTop: margin,
    textBottom,
    textHeight: textBottom - margin,
  };
}

/* -- measurement ---------------------------------------------------------- */

type Pt = { page: number; x: number; yMin: number; yMax: number };

/** Token positions and page height from pdftotext -bbox output
 *  (1-based pages). Tokens have no spaces around them, so pdftotext
 *  merges them into neighbor words ("ProposedXQ000", "text.XQ001"),
 *  and narrower scales fragment the glyphs, so the scale sits at the
 *  measured wholeness floor (w:w=30) and tokens are matched as
 *  substrings. Only page and line geometry matter downstream, so a
 *  match records its word's line box. */
function parseBbox(xml: string): {
  tokens: Map<string, Pt>;
  pageHeight: number;
} {
  const pageHeight = Number(
    xml.match(/<page\b[^>]*\bheight="([\d.]+)"/)?.[1] ?? 0,
  );
  const tokens = new Map<string, Pt>();
  let page = 0;
  const re = /<page\b[^>]*>|<word\b([^>]*)>([^<]*)<\/word>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    if (m[1] === undefined) {
      page++;
      continue;
    }
    for (const mm of m[2].matchAll(/XQ[0-9A-Z]{3}/g)) {
      if (tokens.has(mm[0])) continue;
      const x = Number(m[1].match(/xMin="([\d.]+)"/)?.[1] ?? NaN);
      const yMin = Number(m[1].match(/yMin="([\d.]+)"/)?.[1] ?? NaN);
      const yMax = Number(m[1].match(/yMax="([\d.]+)"/)?.[1] ?? NaN);
      if (!Number.isNaN(x) && !Number.isNaN(yMin))
        tokens.set(mm[0], { page, x, yMin, yMax });
    }
  }
  return { tokens, pageHeight };
}

function run(cmd: string, args: string[], cwd?: string): string {
  const r = spawnSync(cmd, args, { encoding: "utf8", cwd });
  if (r.error) throw new Error(`${cmd} not runnable: ${r.error.message}`);
  if (r.status !== 0)
    throw new Error(`${cmd} ${args.join(" ")} failed:\n${r.stderr}`);
  return r.stdout;
}

/* -- the fixpoint --------------------------------------------------------- */

export type FloatsOptions = {
  /** Max blank left at a page bottom before a float, fraction of text
   *  height. Above this the float should move later. */
  maxBlankFrac: number;
  /** Max gap left under a float before a page turn, fraction of text
   *  height. */
  maxGapFrac: number;
  /** Fit slack in points (borderline pagination). */
  slackPt: number;
  maxPasses: number;
};

const DEFAULTS: FloatsOptions = {
  maxBlankFrac: 0.22,
  maxGapFrac: 0.22,
  slackPt: 3,
  maxPasses: 0, // 0 = derive from float count (2n + 5)
};

export type FloatsContext = {
  referenceDocx: string;
  workDir: string; // scratch dir for pass artifacts
  cwd: string; // pandoc cwd (relative asset paths resolve from here)
  log: (msg: string) => void;
  opts?: Partial<FloatsOptions>;
};

/** Vertical distance from a to b in the text flow (b at or after a),
 *  measured line-top to line-top. */
function flowDist(a: Pt, b: Pt, geo: Geometry): number {
  if (b.page === a.page) return b.yMin - a.yMin;
  return (
    geo.textBottom -
    a.yMin +
    (b.page - a.page - 1) * geo.textHeight +
    (b.yMin - geo.textTop)
  );
}

/** Shift a position up by h points of removed content. */
function shiftUp(p: Pt, h: number, geo: Geometry): Pt {
  let { page, x, yMin, yMax } = p;
  yMin -= h;
  yMax -= h;
  while (yMin < geo.textTop && page > 1) {
    page--;
    yMin += geo.textHeight;
    yMax += geo.textHeight;
  }
  return {
    page,
    x,
    yMin: Math.max(yMin, geo.textTop),
    yMax: Math.max(yMax, geo.textTop),
  };
}

/** Threshold-aware whitespace cost: cheap within tolerance, prohibitive
 *  beyond. */
function whiteCost(frac: number, maxFrac: number): number {
  return frac <= maxFrac ? frac : 100 + frac;
}

export async function placeFloats(
  doc: PandocDoc,
  ctx: FloatsContext,
): Promise<PandocDoc> {
  const o = { ...DEFAULTS, ...ctx.opts };
  const floats = findFloats(doc.blocks);
  const nested = countNestedFloats(doc.blocks);
  if (nested > 0)
    ctx.log(
      `${nested} nested floated block(s): keep-next chain only, no repositioning`,
    );
  if (floats.length === 0) return doc;

  let geo: Geometry | null = null;
  const maxPasses = o.maxPasses > 0 ? o.maxPasses : 2 * floats.length + 5;

  // Working state: the authored blocks themselves. Only floats are ever
  // reordered; non-floats keep their relative order, which makes the
  // nearest non-float block a stable origin anchor.
  const state: Block[] = [...doc.blocks];
  const nonFloat = new Set<Block>(state.filter((b) => !floats.includes(b)));
  const origIdx = new Map<Block, number>(
    doc.blocks.map((b, i) => [b, i] as [Block, number]),
  );
  const seen = new Map<string, number>(); // block-order signature -> pass
  let best: { cost: number; pass: number; state: Block[] } | null = null;
  let lastTotal = Infinity;

  // Origin anchor per float: the first non-float block after it in the
  // authored order, else the last non-float before it. The anchor's
  // position estimates the authored spot; it re-derives every pass.
  const anchorOf = new Map<Block, Block | null>();
  for (let i = 0; i < doc.blocks.length; i++) {
    if (!floats.includes(doc.blocks[i])) continue;
    let anchor: Block | null = null;
    for (let j = i + 1; j < doc.blocks.length; j++) {
      if (nonFloat.has(doc.blocks[j])) {
        anchor = doc.blocks[j];
        break;
      }
    }
    if (!anchor)
      for (let j = i - 1; j >= 0; j--) {
        if (nonFloat.has(doc.blocks[j])) {
          anchor = doc.blocks[j];
          break;
        }
      }
    anchorOf.set(doc.blocks[i], anchor);
  }

  const measureRender = (
    blocks: Block[],
    pass: number,
  ): { tokens: Map<string, Pt>; pageHeight: number } => {
    // Render copy: deep-cloned blocks with a start token at the first
    // paragraph of every block and an end token at the last. Tokens are
    // issued deterministically (2 per block) so the bbox parser matches
    // them by format.
    const render: Block[] = blocks.map((b, bi) => {
      const clone: Block = JSON.parse(JSON.stringify(b));
      const start = firstInlines(clone);
      if (start) start.unshift(tokenRun(token(bi * 2)));
      const end = lastInlines(clone);
      if (end) end.push(tokenRun(token(bi * 2 + 1)));
      return clone;
    });
    const jsonPath = join(ctx.workDir, `pass${pass}.json`);
    const docxPath = join(ctx.workDir, `pass${pass}.docx`);
    writeFileSync(jsonPath, JSON.stringify({ ...doc, blocks: render }));
    run(
      "pandoc",
      [
        "-f",
        "json",
        "-t",
        "docx+native_numbering",
        "--figure-caption-position=above",
        "--reference-doc",
        ctx.referenceDocx,
        "-o",
        docxPath,
        jsonPath,
      ],
      ctx.cwd,
    );
    // The docx gets the house keep-together chain before the render, so
    // the pass layout matches the final one.
    chainDocx(docxPath);
    run("soffice", [
      "--headless",
      "--convert-to",
      "pdf",
      "--outdir",
      ctx.workDir,
      docxPath,
    ]);
    const pdfPath = docxPath.replace(/\.docx$/, ".pdf");
    const xmlPath = join(ctx.workDir, `pass${pass}.xml`);
    // -bbox output for a full manuscript dwarfs spawnSync's buffer, so
    // it goes to a file, never stdout.
    run("pdftotext", ["-bbox", pdfPath, xmlPath]);
    return parseBbox(readFileSync(xmlPath, "utf8"));
  };

  for (let pass = 1; pass <= maxPasses; pass++) {
    let tokens: Map<string, Pt>;
    try {
      const m = await measureRender(state, pass);
      tokens = m.tokens;
      geo ??= geometryFromPdf(m.pageHeight, tokens);
    } catch (e) {
      ctx.log(
        `measurement failed on pass ${pass}: ${e instanceof Error ? e.message : e}; keeping current placement`,
      );
      break;
    }
    const g = geo;
    // Per-block measured geometry: start[i] is the top of block i's
    // first line, end[i] the bottom of its last line. The doc-end
    // pseudo-boundary sits just past the last block.
    const start: (Pt | null)[] = [];
    const end: (Pt | null)[] = [];
    for (let i = 0; i < state.length; i++) {
      start[i] = tokens.get(token(i * 2)) ?? null;
      end[i] = tokens.get(token(i * 2 + 1)) ?? null;
    }
    const last = end[state.length - 1];
    const docEnd: Pt | null = last
      ? { page: last.page, x: last.x, yMin: last.yMax, yMax: last.yMax }
      : null;
    const bpos = (b: number): Pt | null =>
      b < state.length ? start[b] : docEnd;

    // Per-float status from this render.
    type Status = {
      f: Block;
      cf: number; // current state index
      h: number; // height, line-top to line-top
      landing: number;
      p: number; // origin page
      spill: boolean; // the float's own tail lands on a later page
      overTall: boolean;
      blankBefore: number; // pt
      gapAfter: number; // pt
      cost: number;
    };
    const statuses: Status[] = [];
    let broken = false;
    for (const f of floats) {
      const cf = state.indexOf(f);
      const fStart = start[cf];
      const fEnd = end[cf];
      const prevEnd = cf > 0 ? end[cf - 1] : null;
      const nextStart = bpos(cf + 1);
      const anchor = anchorOf.get(f);
      const anchorPos = anchor ? bpos(state.indexOf(anchor)) : null;
      if (!fStart || !fEnd || !nextStart || !anchorPos) {
        ctx.log(
          `float ${floats.indexOf(f) + 1} of ${floats.length}: tokens missing on pass ${pass}; keeping current placement`,
        );
        broken = true;
        break;
      }
      const h = flowDist(fStart, nextStart, g);
      // spill and over-tall read the float's own tail (the end token
      // rides inside it), so a following block starting a fresh page
      // no longer masquerades as a split. A tail sitting at the very
      // top of a later page is the float exactly filling its page,
      // which gets the benefit of the doubt.
      const tailAtTop =
        fEnd.page > fStart.page && fEnd.yMin <= g.textTop + o.slackPt;
      const spill = fEnd.page > fStart.page && !tailAtTop;
      const overTall = h > g.textHeight + o.slackPt && !tailAtTop;
      const blankBefore =
        prevEnd && fStart.page > prevEnd.page ? g.textBottom - prevEnd.yMax : 0;
      const gapAfter =
        nextStart.page > fEnd.page ? g.textBottom - fEnd.yMax : 0;
      const p = anchorPos.page;
      const landing = fStart.page;
      const cost =
        100 * Math.abs(landing - p) +
        (spill ? 500 : 0) +
        50 * whiteCost(blankBefore / g.textHeight, o.maxBlankFrac) +
        50 * whiteCost(gapAfter / g.textHeight, o.maxGapFrac);
      statuses.push({
        f,
        cf,
        h,
        landing,
        p,
        spill,
        overTall,
        blankBefore,
        gapAfter,
        cost,
      });
    }
    if (broken) break;

    // Track the cheapest layout seen: cycles and caps can stop on a
    // worse state than an earlier pass reached.
    const total = statuses.reduce((a, s) => a + s.cost, 0);
    lastTotal = total;
    if (!best || total < best.cost)
      best = { cost: total, pass, state: [...state] };

    // Cycle detection: the full block order determines the layout. A
    // repeated order reproduces the same measurement and the same move
    // proposals forever (two floats can trade places endlessly, each
    // move strictly improving for its own float while degrading the
    // other); stop instead of spinning.
    const sig = state.map((b) => origIdx.get(b) ?? -1).join(",");
    if (seen.has(sig)) {
      ctx.log(
        `pass ${pass}: block order repeated from pass ${seen.get(sig)}; cycle cut`,
      );
      break;
    }
    seen.set(sig, pass);

    // Best movable candidate per float. Boundary b means "immediately
    // before the block currently at state index b" (or the end).
    const moves: { f: Block; to: number; gain: number }[] = [];
    for (const s of statuses) {
      if (s.overTall) continue;
      // Lock the satisfied: within one page of the origin, not
      // spilling, and inside the whitespace tolerances. Without this
      // rule a cosmetic page-p preference ping-pongs the float, because
      // each move drifts the origin page with it.
      const inRange = Math.abs(s.landing - s.p) <= 1;
      const blankOK = s.blankBefore <= o.maxBlankFrac * g.textHeight;
      const gapOK = s.gapAfter <= o.maxGapFrac * g.textHeight;
      if (inRange && !s.spill && blankOK && gapOK) continue;
      const cf = s.cf;
      // Never cross another float: the search stays strictly between
      // the neighboring floats' current blocks.
      let lo = 0;
      let hi = state.length;
      for (const other of statuses) {
        if (other.f === s.f) continue;
        if (other.cf < cf) lo = Math.max(lo, other.cf + 1);
        else hi = Math.min(hi, other.cf);
      }
      let best: { to: number; cost: number } | null = null;
      for (let b = lo; b <= hi; b++) {
        if (b === cf || b === cf + 1) continue;
        const measured = bpos(b);
        if (!measured) continue;
        // Removing the float closes its hole: boundaries after it
        // shift up by its height.
        const ins = b > cf ? shiftUp(measured, s.h, g) : measured;
        const fits = ins.yMin + s.h <= g.textBottom + o.slackPt;
        const landing = fits ? ins.page : ins.page + 1;
        if (Math.abs(landing - s.p) > 1) continue;
        const blank = fits ? 0 : g.textBottom - ins.yMin;
        const cost =
          100 * Math.abs(landing - s.p) +
          50 * whiteCost(blank / g.textHeight, o.maxBlankFrac) +
          Math.abs(b - cf);
        if (!best || cost < best.cost) best = { to: b, cost };
      }
      // Move only on a strict improvement; noise-level gains oscillate.
      if (best && best.cost < s.cost - 1) {
        moves.push({ f: s.f, to: best.to, gain: s.cost - best.cost });
      }
    }

    if (moves.length === 0) {
      ctx.log(
        `pass ${pass}: placement settled (${floats.length} float(s), ${statuses.filter((s) => s.spill).length} spilling, ${statuses.filter((s) => s.overTall).length} over-tall)`,
      );
      break;
    }

    // Apply simultaneously: anchors are the first stationary block at
    // or after the target boundary, so each float lands where the
    // measurement said, independent of other moves.
    const movedSet = new Set(moves.map((m) => m.f));
    const ordered = [...moves].sort(
      (a, b) => state.indexOf(a.f) - state.indexOf(b.f),
    );
    const insertBefore = new Map<Block, Block[]>();
    const atEnd: Block[] = [];
    for (const m of ordered) {
      let i = m.to;
      while (i < state.length && movedSet.has(state[i])) i++;
      if (i >= state.length) atEnd.push(m.f);
      else {
        const anchor = state[i];
        if (!insertBefore.has(anchor)) insertBefore.set(anchor, []);
        insertBefore.get(anchor)!.push(m.f);
      }
    }
    const next: Block[] = [];
    for (const b of state) {
      if (movedSet.has(b)) continue;
      const anchored = insertBefore.get(b);
      if (anchored) next.push(...anchored);
      next.push(b);
    }
    next.push(...atEnd);
    state.length = 0;
    state.push(...next);
    ctx.log(`pass ${pass}: moved ${moves.length} float(s)`);
  }

  // A cycle or the pass cap can leave the loop on a layout worse than
  // an earlier pass measured; keep the cheapest one seen.
  if (best && lastTotal > best.cost + 0.5) {
    ctx.log(
      `kept layout from pass ${best.pass} (score ${best.cost.toFixed(0)} over ${lastTotal.toFixed(0)})`,
    );
    state.length = 0;
    state.push(...best.state);
  }

  return { ...doc, blocks: state };
}
