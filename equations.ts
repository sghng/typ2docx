/**
 * equations.ts -- best-effort display-equation layout diagnostics.
 *
 * Pandoc has already isolated display math into its own paragraphs in the
 * delivered DOCX. A diagnostic copy gets tiny white token runs at
 * the boundaries of each such paragraph; LibreOffice and pdftotext then tell
 * us whether the content extends beyond the text area or the boundaries land
 * on different pages. The delivered DOCX is never patched.
 *
 * This is deliberately a warning-only LibreOffice check, not a prediction of
 * Word's exact line breaking. Authored multiline math is skipped for now:
 * distinguishing its expected rows from an additional automatic wrap needs a
 * later row-count comparison.
 */
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { token, tokenXml, type PandocDoc } from "./floats.ts";

export type EquationInfo = {
  index: number;
  tex: string;
  label: string;
  number: string;
  authoredMultiline: boolean;
};

type AnchorMap = {
  equations?: { key?: string; number?: string }[];
};

type Attr = [string, string[], [string, string][]];

/** Explicit TeX row breaks and structured environments represent authored
 *  math layout, not an automatically wrapped single-line equation. Being
 *  conservative here avoids maintaining an incomplete environment list. */
export function hasAuthoredMultiline(tex: string): boolean {
  return /\\\\/.test(tex) || /\\begin\{|\\substack/.test(tex);
}

/** Equation labels start beside unnumbered math and move onto the visible
 *  number cell for numbered math. Inspect the containing paragraph/table so
 *  both shapes yield the actual AST label before consulting anchors.json. */
function equationLabelOf(node: unknown): string | null {
  if (Array.isArray(node)) {
    for (const child of node) {
      const label = equationLabelOf(child);
      if (label !== null) return label;
    }
    return null;
  }
  if (!node || typeof node !== "object") return null;
  const el = node as { t?: string; c?: unknown; [key: string]: unknown };
  if (el.t === "Span" && Array.isArray(el.c)) {
    const id = (el.c[0] as Attr)[0];
    if (id !== "") return id;
  }
  for (const [key, value] of Object.entries(el)) {
    if (key === "t") continue;
    const label = equationLabelOf(value);
    if (label !== null) return label;
  }
  return null;
}

/** Collect display math and actual labels in document order. Notes live in
 *  a separate DOCX part and are outside this document.xml measurement pass. */
export function collectEquations(
  doc: PandocDoc,
  anchors: AnchorMap = {},
): EquationInfo[] {
  const found: Omit<EquationInfo, "index" | "number">[] = [];
  const walk = (node: unknown, label: string): void => {
    if (Array.isArray(node)) {
      for (const child of node) walk(child, label);
      return;
    }
    if (!node || typeof node !== "object") return;
    const el = node as { t?: string; c?: unknown; [key: string]: unknown };
    if (el.t === "Note") return;
    if (el.t === "Math" && Array.isArray(el.c)) {
      const mathType = el.c[0] as { t?: string } | undefined;
      if (mathType?.t === "DisplayMath") {
        const tex = String(el.c[1] ?? "");
        found.push({ tex, label, authoredMultiline: hasAuthoredMultiline(tex) });
      }
      return;
    }
    const nested = el.t === "Para" || el.t === "Plain" || el.t === "Table"
      ? equationLabelOf(el) ?? label
      : label;
    for (const [key, value] of Object.entries(el)) {
      if (key !== "t") walk(value, nested);
    }
  };
  walk(doc.blocks, "");

  const expected = anchors.equations ?? [];
  const aligned = expected.length === found.length && found.every(
    (eq, index) => eq.label === (expected[index].key ?? ""),
  );
  return found.map((eq, index) => ({
    ...eq,
    index,
    number: aligned ? expected[index].number ?? "" : "",
  }));
}

function decodeXmlText(text: string): string {
  return text.replace(/&(?:#x([0-9A-Fa-f]+)|#(\d+)|amp|lt|gt|quot|apos);/g,
    (entity, hex, decimal) => {
      if (hex) return String.fromCodePoint(parseInt(hex, 16));
      if (decimal) return String.fromCodePoint(Number(decimal));
      return {
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": '"',
        "&apos;": "'",
      }[entity] ?? entity;
    });
}

/** Display math has an m:oMathPara wrapper; bare m:oMath is inline math.
 *  Requiring the wrapper also excludes inline-only paragraphs hidden inside
 *  mark spans, which need not contain an ordinary word run or zero-width space. */
function isDisplayEquationParagraph(para: string): boolean {
  if (!/<m:oMathPara\b[^>]*>/.test(para)) return false;
  for (const m of para.matchAll(/<w:t\b[^>]*>([\s\S]*?)<\/w:t>/g)) {
    // Even a zero-width space is meaningful: the writer uses it to keep a
    // lone inline equation from becoming display math in Word.
    if (decodeXmlText(m[1]) !== "") return false;
  }
  return true;
}

/** Add one start/end token pair per display equation, in document order. */
export function injectEquationTokens(
  xml: string,
): { xml: string; count: number } {
  let count = 0;
  const patched = xml.replace(/<w:p\b[^>]*>[\s\S]*?<\/w:p>/g, (para) => {
    if (!isDisplayEquationParagraph(para)) return para;
    const start = tokenXml(token(count * 2));
    const end = tokenXml(token(count * 2 + 1));
    count++;
    let out = para;
    const pPrEnd = out.indexOf("</w:pPr>");
    if (pPrEnd >= 0) {
      const at = pPrEnd + "</w:pPr>".length;
      out = out.slice(0, at) + start + out.slice(at);
    } else if (/<w:pPr\s*\/>/.test(out)) {
      out = out.replace(/<w:pPr\s*\/>/, (pPr) => pPr + start);
    } else {
      out = out.replace(/^<w:p\b[^>]*>/, (open) => open + start);
    }
    return out.replace(/<\/w:p>$/, end + "</w:p>");
  });
  return { xml: patched, count };
}

export type EquationPoint = {
  page: number;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
};

export type EquationWord = EquationPoint & { text: string };

function numberAttr(attrs: string, name: string): number {
  const m = attrs.match(new RegExp(`\\b${name}="(-?[\\d.]+)"`));
  return m ? Number(m[1]) : NaN;
}

/** Read token positions and word bounds in PDF document order. */
export function parseEquationBbox(xml: string): {
  tokens: Map<string, EquationPoint>;
  words: EquationWord[];
  pageWidths: Map<number, number>;
} {
  const tokens = new Map<string, EquationPoint>();
  const words: EquationWord[] = [];
  const pageWidths = new Map<number, number>();
  let page = 0;
  let lineAttrs = "";
  const re = /<page\b([^>]*)>|<line\b([^>]*)>|<word\b([^>]*)>([^<]*)<\/word>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    if (m[1] !== undefined) {
      page++;
      lineAttrs = "";
      pageWidths.set(page, numberAttr(m[1], "width"));
      continue;
    }
    if (m[2] !== undefined) {
      lineAttrs = m[2];
      continue;
    }
    const xMin = numberAttr(m[3], "xMin");
    const xMax = numberAttr(m[3], "xMax");
    const yMin = numberAttr(lineAttrs, "yMin");
    const yMax = numberAttr(lineAttrs, "yMax");
    if (![xMin, xMax, yMin, yMax].every(Number.isFinite)) continue;
    words.push({ page, xMin, xMax, yMin, yMax, text: m[4] });
    for (const mm of m[4].matchAll(/XQ[0-9A-Z]{3}/g)) {
      if (!tokens.has(mm[0])) tokens.set(mm[0], { page, xMin, xMax, yMin, yMax });
    }
  }
  return { tokens, words, pageWidths };
}

/** Horizontal bounds of the PDF words bracketed by one equation's markers.
 *  LibreOffice may move an end marker away from a wide formula object, so the
 *  end token's own position is not a reliable measure of the math's extent. */
export function equationContentBounds(
  words: EquationWord[],
  index: number,
  number = "",
): { xMin: number; xMax: number } | null {
  const startToken = token(index * 2);
  const endToken = token(index * 2 + 1);
  const start = words.findIndex((word) => word.text.includes(startToken));
  if (start < 0) return null;
  const end = words.findIndex(
    (word, i) => i >= start && word.text.includes(endToken),
  );
  if (end < 0) return null;
  if (start === end) {
    const remainder = words[start].text
      .replace(startToken, "")
      .replace(endToken, "");
    // Without LibreOffice's Math module, both markers can collapse into one
    // token-only word while the formula itself disappears from the render.
    if (remainder === "") return null;
  }
  const yLo = Math.min(words[start].yMin, words[end].yMin) - 12;
  const yHi = Math.max(words[start].yMax, words[end].yMax) + 12;
  let xMin = Infinity;
  let xMax = -Infinity;
  for (const word of words.slice(start, end + 1)) {
    if (number !== "" && word.text === number) continue;
    const y = (word.yMin + word.yMax) / 2;
    // Exclude neighboring prose that PDF flow ordering may place between the
    // markers. The small vertical allowance retains fraction numerators and
    // denominators without treating tall math as an automatic wrap.
    if (y < yLo || y > yHi) continue;
    xMin = Math.min(xMin, word.xMin);
    xMax = Math.max(xMax, word.xMax);
  }
  return Number.isFinite(xMin) ? { xMin, xMax } : null;
}

export type EquationTableFractions = { left: number; right: number };

/** Center-cell boundaries from each Equation table's grid, in document order.
 *  The table fills the text column, so these fractions can be mapped onto the
 *  rendered page without duplicating the 6%/88%/6% policy in this module. */
export function equationTableFractions(xml: string): EquationTableFractions[] {
  const out: EquationTableFractions[] = [];
  for (const table of xml.matchAll(/<w:tbl>[\s\S]*?<\/w:tbl>/g)) {
    const xmlTable = table[0];
    if (!xmlTable.includes('<w:tblStyle w:val="Equation"')) continue;
    const grid = xmlTable.match(/<w:tblGrid>([\s\S]*?)<\/w:tblGrid>/)?.[1];
    if (!grid) continue;
    const widths = [...grid.matchAll(/<w:gridCol w:w="(\d+)"\s*\/>/g)]
      .map((m) => Number(m[1]));
    if (widths.length !== 3 || widths.some((w) => w <= 0)) continue;
    const total = widths.reduce((a, b) => a + b, 0);
    out.push({
      left: widths[0] / total,
      right: (widths[0] + widths[1]) / total,
    });
  }
  return out;
}

export type EquationLayoutProblem = "wrap" | "cell-overflow" | "overflow" | null;

export function equationLayoutProblem(
  eq: Pick<EquationInfo, "authoredMultiline">,
  start: EquationPoint,
  end: EquationPoint,
  pageWidth: number,
  content: { xMin: number; xMax: number } | null = null,
  cell: EquationTableFractions | null = null,
): EquationLayoutProblem {
  if (eq.authoredMultiline) return null;
  const xMin = content?.xMin ?? start.xMin;
  const xMax = content?.xMax ?? end.xMax;
  const textWidth = pageWidth - 144;
  if (cell && pageWidth > 0) {
    const left = 72 + cell.left * textWidth;
    const right = 72 + cell.right * textWidth;
    if (xMin < left - 3 || xMax > right + 3) return "cell-overflow";
  }
  // The reference stock uses the OOXML default one-inch margins.
  if (xMin < 72 - 3 || (pageWidth > 0 && xMax > pageWidth - 72 + 3))
    return "overflow";
  // Tall formula objects can move an end marker to another PDF line without
  // wrapping. Only cross-page displacement is unambiguous enough to report.
  if (start.page !== end.page) return "wrap";
  return null;
}

function run(cmd: string, args: string[], cwd?: string): string {
  const r = spawnSync(cmd, args, {
    encoding: "utf8",
    cwd,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.error) throw new Error(`${cmd} not runnable: ${r.error.message}`);
  if (r.status !== 0)
    throw new Error(`${cmd} ${args.join(" ")} failed:\n${r.stderr}`);
  return r.stdout;
}

function documentXml(docxPath: string): string {
  return run("unzip", ["-p", docxPath, "word/document.xml"]);
}

function replaceDocumentXml(docxPath: string, xml: string): void {
  const dir = mkdtempSync(join(tmpdir(), "typ2docx-equations-"));
  try {
    const rel = "word/document.xml";
    mkdirSync(join(dir, "word"), { recursive: true });
    writeFileSync(join(dir, rel), xml);
    run("zip", ["-q", "-X", docxPath, rel], dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export type EquationLayoutContext = {
  docxPath: string;
  anchors: AnchorMap;
  workDir: string;
  log: (message: string) => void;
};

/** Measure the final document and emit nonfatal warnings. Any measurement
 *  failure suppresses the check rather than blocking conversion. */
export function checkEquationLayout(
  doc: PandocDoc,
  ctx: EquationLayoutContext,
): void {
  const equations = collectEquations(doc, ctx.anchors);
  if (equations.length === 0) return;
  try {
    const sourceXml = documentXml(ctx.docxPath);
    const tableFractions = equationTableFractions(sourceXml);
    const injected = injectEquationTokens(sourceXml);
    if (injected.count !== equations.length) {
      throw new Error(
        `found ${injected.count} display-math paragraphs for ` +
          `${equations.length} AST equations`,
      );
    }
    const probePath = join(ctx.workDir, "equation-layout.docx");
    copyFileSync(ctx.docxPath, probePath);
    replaceDocumentXml(probePath, injected.xml);
    const profile = pathToFileURL(join(ctx.workDir, "equation-lo-profile"));
    run("soffice", [
      `-env:UserInstallation=${profile.href}`,
      "--headless",
      "--convert-to",
      "pdf",
      "--outdir",
      ctx.workDir,
      probePath,
    ]);
    const pdfPath = probePath.replace(/\.docx$/, ".pdf");
    const bboxPath = join(ctx.workDir, "equation-layout-bbox.xml");
    run("pdftotext", ["-bbox-layout", pdfPath, bboxPath]);
    const { tokens, words, pageWidths } = parseEquationBbox(
      readFileSync(bboxPath, "utf8"),
    );

    const missing: EquationInfo[] = [];
    let tableIndex = 0;
    for (const eq of equations) {
      const cell = eq.number ? tableFractions[tableIndex++] ?? null : null;
      if (eq.authoredMultiline) continue;
      if (eq.number && !cell) {
        missing.push(eq);
        continue;
      }
      const start = tokens.get(token(eq.index * 2));
      const end = tokens.get(token(eq.index * 2 + 1));
      if (!start || !end) {
        missing.push(eq);
        continue;
      }
      const content = equationContentBounds(words, eq.index, eq.number);
      if (!content) {
        missing.push(eq);
        continue;
      }
      const pageWidth = pageWidths.get(start.page) ?? 0;
      const verdict = equationLayoutProblem(
        eq, start, end, pageWidth, content, cell,
      );
      if (!verdict) continue;
      const identity = eq.number || String(eq.index + 1);
      const label = eq.label ? ` <${eq.label}>` : "";
      const problem = verdict === "wrap"
        ? "may wrap or overflow"
        : verdict === "cell-overflow"
          ? "may overflow its equation cell"
          : "may extend beyond the text area";
      ctx.log(
        `warning: display equation ${identity}${label} ${problem} ` +
          "in the LibreOffice layout; review manual line breaking",
      );
    }
    if (missing.length > 0) {
      const identities = missing.map((eq) =>
        `${eq.number || String(eq.index + 1)}${eq.label ? ` <${eq.label}>` : ""}`
      ).join(", ");
      ctx.log(
        `warning: equation layout check could not measure ${missing.length} ` +
          `single-line equation(s): ${identities}; no layout verdict for those`,
      );
    }
  } catch (e) {
    ctx.log(
      `warning: equation layout check failed: ` +
        `${e instanceof Error ? e.message : e}; no equation layout warnings emitted`,
    );
  }
}
