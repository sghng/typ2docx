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
 *     inject sentinel markers (1pt white paragraphs, unique tokens)
 *     pandoc json -> docx (house reference doc) -> soffice pdf
 *     measure token positions (pdftotext -bbox)
 *     score every float's current spot against movable candidates
 *     apply strictly improving moves (whole nodes only, never edited)
 *   final: state without origin markers (sentinels only ever lived in
 *   measurement renders, so the delivered nodes are pristine)
 *
 * The origin of a float is its authored AST position: an origin sentinel
 * stays behind at that spot when the node moves, so the allowed landing
 * range {p-1, p, p+1} (p = origin page) is re-derived every pass.
 */

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chainDocx } from "./chain.ts";

/* -- pandoc JSON plumbing ------------------------------------------------- */

export type Block = { t: string; c?: unknown };
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

/* -- sentinels ------------------------------------------------------------ */

/**
 * Sentinel paragraphs are measurement scaffolding: a unique alphanumeric
 * token in 0.5pt white text on an exact 1pt line with zero spacing. They
 * exist only in measurement renders; the final docx is rendered from
 * state that never contained them (origin markers excepted, and those
 * are filtered out before the final render).
 */
const SENT_LINE_TWIPS = 20; // 1pt exact line
const pad = (n: number) => String(n).padStart(4, "0");

function sentinelXml(token: string, keepNext: boolean): string {
  return (
    `<w:p><w:pPr>` +
    (keepNext ? `<w:keepNext/>` : "") +
    `<w:spacing w:before="0" w:after="0" w:line="${SENT_LINE_TWIPS}" w:lineRule="exact"/>` +
    `</w:pPr><w:r><w:rPr>` +
    `<w:color w:val="FFFFFF"/><w:sz w:val="1"/><w:szCs w:val="1"/>` +
    `</w:rPr><w:t>${token}</w:t></w:r></w:p>`
  );
}

function sentinelBlock(token: string, keepNext = false): Block {
  return { t: "RawBlock", c: ["openxml", sentinelXml(token, keepNext)] };
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
  for (const p of tokens.values()) textBottom = Math.max(textBottom, p.y);
  return {
    pageHeight,
    textTop: margin,
    textBottom,
    textHeight: textBottom - margin,
  };
}

/* -- measurement ---------------------------------------------------------- */

type Pt = { page: number; y: number };

/** Token positions and page height from pdftotext -bbox output
 *  (1-based pages). */
function parseBbox(xml: string): {
  tokens: Map<string, Pt>;
  pageHeight: number;
} {
  const tokens = new Map<string, Pt>();
  const pageHeight = Number(
    xml.match(/<page\b[^>]*\bheight="([\d.]+)"/)?.[1] ?? 0,
  );
  let page = 0;
  const re = /<page\b[^>]*>|<word\b([^>]*)>([^<]*)<\/word>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    if (m[1] === undefined) {
      page++;
      continue;
    }
    const text = m[2];
    if (!/^ZQ[OBK]\d+$/.test(text)) continue;
    const y = Number(m[1].match(/yMin="([\d.]+)"/)?.[1] ?? NaN);
    if (!Number.isNaN(y)) tokens.set(text, { page, y });
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
  /** Fit slack in points (sentinel lines, borderline pagination). */
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

/** Vertical distance from a to b in the text flow (b at or after a). */
function flowDist(a: Pt, b: Pt, geo: Geometry): number {
  if (b.page === a.page) return b.y - a.y;
  return (
    geo.textBottom -
    a.y +
    (b.page - a.page - 1) * geo.textHeight +
    (b.y - geo.textTop)
  );
}

/** Shift a position up by h points of removed content. */
function shiftUp(p: Pt, h: number, geo: Geometry): Pt {
  let { page, y } = p;
  y -= h;
  while (y < geo.textTop && page > 1) {
    page--;
    y += geo.textHeight;
  }
  return { page, y: Math.max(y, geo.textTop) };
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

  // Working state: the authored blocks plus one origin sentinel per
  // float at the authored position. Float nodes move; nothing else does.
  const originSet = new Set<Block>();
  const originToken = new Map<Block, string>();
  const originOf = new Map<Block, Block>(); // float -> its origin marker
  const state: Block[] = [];
  let floatCount = 0;
  for (const b of doc.blocks) {
    if (floats.includes(b)) {
      const token = `ZQO${pad(floatCount++)}`;
      const marker = sentinelBlock(token);
      originSet.add(marker);
      originToken.set(marker, token);
      originOf.set(b, marker);
      state.push(marker);
    }
    state.push(b);
  }

  const measureRender = (
    blocks: Block[],
    pass: number,
  ): { tokens: Map<string, Pt>; pageHeight: number } => {
    const jsonPath = join(ctx.workDir, `pass${pass}.json`);
    const docxPath = join(ctx.workDir, `pass${pass}.docx`);
    writeFileSync(jsonPath, JSON.stringify({ ...doc, blocks }));
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
    // Boundary sentinels: one plain marker before every block (origin
    // markers double as their own boundary token) plus one at the end,
    // and one keepNext marker immediately before each float so the
    // float's true start is measured even when the chain pushes it.
    const boundary: string[] = [];
    const rideToken = new Map<Block, string>();
    const render: Block[] = [];
    let bc = 0;
    for (let i = 0; i < state.length; i++) {
      const b = state[i];
      if (originSet.has(b)) {
        boundary[i] = originToken.get(b)!;
      } else {
        boundary[i] = `ZQB${pad(bc++)}`;
        render.push(sentinelBlock(boundary[i]));
      }
      if (floats.includes(b)) {
        const t = `ZQK${pad(bc++)}`;
        rideToken.set(b, t);
        render.push(sentinelBlock(t, true));
      }
      render.push(b);
    }
    boundary[state.length] = `ZQB${pad(bc++)}`;
    render.push(sentinelBlock(boundary[state.length]));

    let tokens: Map<string, Pt>;
    try {
      const m = await measureRender(render, pass);
      tokens = m.tokens;
      geo ??= geometryFromPdf(m.pageHeight, tokens);
    } catch (e) {
      ctx.log(
        `measurement failed on pass ${pass}: ${e instanceof Error ? e.message : e}; keeping current placement`,
      );
      break;
    }
    const g = geo;
    const at = (token: string): Pt | null => tokens.get(token) ?? null;
    const bpos = (i: number): Pt | null => at(boundary[i]);

    // Per-float status from this render.
    type Status = {
      f: Block;
      cf: number; // current boundary index
      h: number; // height, pt
      landing: number;
      p: number; // origin page
      spill: boolean; // content after the float starts on a later page
      overTall: boolean;
      blankBefore: number; // pt
      gapAfter: number; // pt
      cost: number;
    };
    const statuses: Status[] = [];
    let broken = false;
    for (const f of floats) {
      const cf = state.indexOf(f);
      const start = at(rideToken.get(f)!);
      const end = bpos(cf + 1);
      // The origin marker stays at the authored spot wherever the float
      // travels, so the allowed range re-derives from its own token.
      const origin = at(originToken.get(originOf.get(f)!)!);
      // The plain boundary sentinel right before the float does not
      // ride with it, so it marks where previous content ended: the
      // blank left behind when the chain pushes the float.
      const prevEnd = bpos(cf);
      if (!start || !end || !origin || !prevEnd) {
        ctx.log(
          `float ${floats.indexOf(f) + 1} of ${floats.length}: sentinels missing on pass ${pass}; keeping current placement`,
        );
        broken = true;
        break;
      }
      const h = flowDist(start, end, g);
      // The end marker is the next block's boundary, so it jumps a page
      // when the NEXT block starts a fresh page (a pushed following
      // float, a heading with a page break) even when this float ended
      // mid-page. That configuration is recognizable: the marker sits
      // at the top of its page. In it, neither spill nor over-tall is
      // provable from this pair, so the float gets the benefit of the
      // doubt; a true split almost always leaves the marker mid-page.
      const nextStartsPage = end.y <= g.textTop + o.slackPt;
      const overTall = h > g.textHeight + o.slackPt && !nextStartsPage;
      const spill = !overTall && end.page > start.page && !nextStartsPage;
      const blankBefore =
        start.page > prevEnd.page ? g.textBottom - prevEnd.y : 0;
      const gapAfter =
        end.page > start.page && end.y > g.textTop + o.slackPt
          ? g.textBottom - end.y
          : 0;
      const p = origin.page;
      const landing = start.page;
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
        const fits = ins.y + s.h <= g.textBottom + o.slackPt;
        const landing = fits ? ins.page : ins.page + 1;
        if (Math.abs(landing - s.p) > 1) continue;
        const blank = fits ? 0 : g.textBottom - ins.y;
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

  const finalBlocks = state.filter((b) => !originSet.has(b));
  return { ...doc, blocks: finalBlocks };
}
