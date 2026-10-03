/**
 * typ2docx/chain.ts -- keep-together chains as a docx post-process.
 *
 * The house float policy (float every table and figure by default) needs
 * the standard Word recipe -- cantSplit on every row, keepNext chaining
 * caption and rows into one atomic unit, and the same for a figure's
 * caption and image -- applied to every table and captioned float in the
 * document. Doing it as XML surgery on the pandoc-produced docx keeps
 * pandoc itself pristine: the styling lives in the reference stock, the
 * policy lives here. The document.xml of a pandoc docx has a fixed,
 * known shape, so the surgery is deliberately textual.
 *
 * Caption position is assumed above (the house CLI forces it for figures
 * and it is the pandoc default for tables): caption paragraphs chain
 * down into the body, and every table row but the last chains down into
 * the next. A float's note paragraph (italic "Note." opener, the house
 * convention) is part of its unit: the last table row or the image
 * paragraph before a note chains down to it.
 */
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CAPTION_STYLES = new Set(["TableCaption", "ImageCaption"]);

/** Insert a keepNext property into a paragraph's pPr, respecting the
 *  schema's child order (pStyle first, keepNext before everything else).
 *  Idempotent. Pandoc emits self-closing tags as `<w:x />` with a space,
 *  so every pattern here is space-tolerant. */
function addKeepNext(para: string): string {
  if (para.includes("<w:keepNext/>")) return para;
  const pStyle = para.match(/<w:pStyle w:val="[^"]*"\s*\/>/);
  if (pStyle) return para.replace(pStyle[0], pStyle[0] + "<w:keepNext/>");
  if (para.includes("<w:pPr>"))
    return para.replace("<w:pPr>", "<w:pPr><w:keepNext/>");
  return para.replace(/^<w:p>/, "<w:p><w:pPr><w:keepNext/></w:pPr>");
}

/** Ensure a cantSplit property in a row's trPr (cantSplit precedes
 *  tblHeader in the schema). Idempotent. */
function addCantSplit(row: string): string {
  if (row.includes("<w:cantSplit/>")) return row;
  if (row.includes("<w:trPr>"))
    return row.replace("<w:trPr>", "<w:trPr><w:cantSplit/>");
  return row.replace(/^<w:tr>/, "<w:tr><w:trPr><w:cantSplit/></w:trPr>");
}

/** A paragraph whose first run is italic and opens with "Note.": the
 *  house float-note convention (mirrors is_note_para in filter.lua). */
function isNotePara(para: string): boolean {
  const m = para.match(
    /^<w:p>(?:<w:pPr>.*?<\/w:pPr>)?<w:r><w:rPr>(.*?)<\/w:rPr><w:t[^>]*>([^<]*)<\/w:t>/,
  );
  if (!m) return false;
  return /<w:i\s*\/>/.test(m[1]) && /^Note\.?$/.test(m[2].trim());
}

/** Ranges of top-level w:tbl elements (balanced, nesting-aware). */
function tableSpans(xml: string): [number, number][] {
  const spans: [number, number][] = [];
  const re = /<w:tbl>|<\/w:tbl>/g;
  const stack: number[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    if (m[0] === "<w:tbl>") stack.push(m.index);
    else {
      const start = stack.pop();
      if (start !== undefined) spans.push([start, re.lastIndex]);
    }
  }
  return spans.sort((a, b) => a[0] - b[0]);
}

/** Patch one table: cantSplit on every row, keepNext on every paragraph
 *  of every row but the last (and of the last row too when it chains to
 *  a note). */
function chainTable(tbl: string, lastRowChains: boolean): string {
  const parts = tbl.split(/(?=<w:tr>)/);
  // parts[0] is everything before the first row (tblPr, tblGrid).
  const rowIdxs = parts
    .map((p, i) => (p.startsWith("<w:tr>") ? i : -1))
    .filter((i) => i >= 0);
  const lastRowPart = rowIdxs[rowIdxs.length - 1];
  return parts
    .map((p, i) => {
      if (!p.startsWith("<w:tr>")) return p;
      let out = addCantSplit(p);
      if (i !== lastRowPart || lastRowChains) {
        out = out.replace(/<w:p>.*?<\/w:p>|<w:p\/>/gs, (para) =>
          addKeepNext(para),
        );
      }
      return out;
    })
    .join("");
}

/** Patch document.xml and return the result. */
export function chainDocumentXml(xml: string): string {
  // Patch every table, innermost first so nested spans stay valid; note
  // attachment for the last row is decided from what follows the table.
  const spans = tableSpans(xml);
  const replacements: [number, number, string][] = [];
  for (const [start, end] of spans) {
    const tbl = xml.slice(start, end);
    const rest = xml.slice(end).match(/^\s*(<w:p>.*?<\/w:p>|<w:p\/>)/s);
    const lastRowChains = rest !== null && isNotePara(rest[1]);
    replacements.push([start, end, chainTable(tbl, lastRowChains)]);
  }
  let out = "";
  let cursor = 0;
  for (const [start, end, text] of replacements) {
    out += xml.slice(cursor, start) + text;
    cursor = end;
  }
  out += xml.slice(cursor);
  xml = out;

  // Paragraph-level passes, applied piecewise to avoid cross-paragraph
  // regex greed: captions chain down, and an image paragraph followed by
  // a note chains to the note.
  const paras = xml.split(/(?=<w:p>)/);
  return paras
    .map((p, i) => {
      if (!p.startsWith("<w:p>")) return p;
      const style = p.match(/<w:pStyle w:val="([^"]*)"\s*\/>/);
      if (style && CAPTION_STYLES.has(style[1])) return addKeepNext(p);
      if (p.includes("<w:drawing>")) {
        const next = paras[i + 1];
        if (next && next.startsWith("<w:p>") && isNotePara(next))
          return addKeepNext(p);
      }
      return p;
    })
    .join("");
}

/** Chain every table and captioned float in a docx, in place. */
export function chainDocx(docxPath: string): void {
  const dir = mkdtempSync(join(tmpdir(), "typ2docx-chain-"));
  try {
    const rel = "word/document.xml";
    const get = spawnSync("unzip", ["-p", docxPath, rel], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    if (get.status !== 0) throw new Error(`unzip ${docxPath}: ${get.stderr}`);
    const patched = chainDocumentXml(get.stdout);
    mkdirSync(join(dir, "word"));
    writeFileSync(join(dir, rel), patched);
    // zip updates the single entry inside the existing archive.
    const put = spawnSync("zip", ["-q", "-X", docxPath, rel], {
      cwd: dir,
      encoding: "utf8",
    });
    if (put.status !== 0) throw new Error(`zip ${docxPath}: ${put.stderr}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
