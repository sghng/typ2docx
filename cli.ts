#!/usr/bin/env bun
/**
 * cli.ts -- the `typ2docx` command.
 *
 * Converts a Typst source to Word beside it: house reference stock
 * rebuilt fresh from the patch series, citeproc under the hash-pinned
 * APA style, native numbering, Typst counters from anchors.typ for
 * references and displayed numbers, the content-adjustment filter
 * (filter.lua), the float placement fixpoint (floats.ts) for blocks the
 * Typst reader marked with a placement keyval, and a final best-effort
 * equation layout check (equations.ts). No server or model involved.
 *
 *   typ2docx <file.typ> [--no-floats] [--max-passes N]
 *                                  [--keep-scratch]
 */
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chainDocx } from "./chain.ts";
import { checkEquationLayout } from "./equations.ts";
import { placeFloats } from "./floats.ts";

const DIR = dirname(fileURLToPath(import.meta.url));
const HARNESS_DIR = DIR;
const PANDOC = join(HARNESS_DIR, ".build", "bin", "pandoc");
const TYP2DOCX_HOME =
  process.env.TYP2DOCX_HOME ?? join(homedir(), ".local", "share", "typ2docx");

function fail(message: string): never {
  console.error(`typ2docx: ${message}`);
  process.exit(1);
}

function run(
  cmd: string,
  args: string[],
  cwd?: string,
  env?: NodeJS.ProcessEnv,
): void {
  // stderr passes through: the filter's guardrail messages (an
  // added-refs key with no entry, a malformed declaration) must reach
  // the user even on success
  const r = spawnSync(cmd, args, {
    encoding: "utf8",
    cwd,
    env,
    stdio: ["ignore", "pipe", "inherit"],
  });
  if (r.error) fail(`${cmd} not runnable: ${r.error.message}`);
  if (r.status !== 0) process.exit(r.status ?? 1);
}

/** Build the house reference stock into a private temp dir and return the
 *  dir path. Rebuilt on every conversion: the patch series is the single
 *  source of truth and nothing is cached. Quiet on success; the build
 *  log only surfaces when the build fails. */
function buildReference(): string {
  const script = join(HARNESS_DIR, "build-reference.sh");
  const dir = mkdtempSync(join(tmpdir(), "typ2docx-"));
  const r = spawnSync(script, ["--out", join(dir, "reference.docx")], {
    encoding: "utf8",
  });
  if (r.error) fail(`build script not runnable: ${script}`);
  if (r.status !== 0) {
    process.stdout.write(r.stdout ?? "");
    process.stderr.write(r.stderr ?? "");
    process.exit(r.status ?? 1);
  }
  return dir;
}

/** Build the pinned Typst and Hayagriva toolchain and return its binary. */
function buildTypst(): string {
  const script = join(HARNESS_DIR, "build-typst.sh");
  const r = spawnSync(script, [], { encoding: "utf8" });
  if (r.error) fail(`build script not runnable: ${script}`);
  if (r.status !== 0) {
    process.stdout.write(r.stdout ?? "");
    process.stderr.write(r.stderr ?? "");
    process.exit(r.status ?? 1);
  }
  return join(HARNESS_DIR, ".build", "bin", "typst");
}

/** Evaluate Typst's counters into the anchor map consumed by filter.lua.
 *  The map lives in scratch and reaches the filter through the environment;
 *  the final render never needs it. Typst owns numbering semantics, so Word
 *  references and displayed equation numbers match the Typst PDF. */
function buildAnchors(
  src: string,
  cwd: string,
  scratch: string,
  typst: string,
): string {
  const script = readFileSync(join(DIR, "anchors.typ"), "utf8");
  const r = spawnSync(typst, ["eval", "--in", src, script], {
    encoding: "utf8",
    cwd,
    stdio: ["ignore", "pipe", "inherit"],
  });
  if (r.error) fail(`typst not runnable: ${r.error.message}`);
  if (r.status !== 0) process.exit(r.status ?? 1);
  const path = join(scratch, "anchors.json");
  writeFileSync(path, r.stdout);
  return path;
}

/** The APA citation style, hash-pinned. Pandoc's built-in style is
 * Chicago author-date, but the drafts cite APA (their Typst PDFs
 * render style: "apa"), so the conversion passes the canonical APA
 * CSL explicitly. The file is fetched once from the styles repository
 * into the typ2docx home and verified against the pin; a drifted
 * upstream file fails the run rather than silently changing the
 * citation format, and updating the pin is a reviewed decision. */
const CSL_URL =
  "https://raw.githubusercontent.com/citation-style-language/styles/master/apa.csl";
const CSL_SHA256 =
  "3917def5fc951b104d64216c3373096042368b9704ba269ca83c14ebaba889fc";
const CSL_PATH = join(TYP2DOCX_HOME, "csl", "apa.csl");

async function ensureApaCsl(): Promise<string> {
  if (existsSync(CSL_PATH)) {
    const cached = readFileSync(CSL_PATH);
    if (sha256hex(cached) === CSL_SHA256) return CSL_PATH;
    console.error(
      "typ2docx: cached apa.csl does not match the pin; refetching",
    );
  }
  let body: Uint8Array;
  try {
    const r = await fetch(CSL_URL);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    body = new Uint8Array(await r.arrayBuffer());
  } catch (e) {
    fail(
      `cannot fetch the APA citation style (${CSL_URL}): ` +
        (e instanceof Error ? e.message : e),
    );
  }
  if (sha256hex(body) !== CSL_SHA256)
    fail(
      "apa.csl at " +
        CSL_URL +
        " does not match the pinned hash; " +
        "review it and update CSL_SHA256 in cli.ts",
    );
  mkdirSync(dirname(CSL_PATH), { recursive: true });
  writeFileSync(CSL_PATH, body);
  return CSL_PATH;
}

function sha256hex(data: Uint8Array): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

/** Convert a Typst source to Word beside it. Pandoc runs from the
 *  source's directory so relative bibliography and asset paths in the
 *  .typ resolve as they do when drafting there. */
export async function typeToDocx(args: string[]): Promise<void> {
  const arg = args.find(
    (a, i) => !a.startsWith("--") && args[i - 1] !== "--max-passes",
  );
  if (!arg) fail("usage: typ2docx <file.typ> [--no-floats]");
  const src = resolve(arg);
  if (!src.endsWith(".typ")) fail(`not a .typ file: ${arg}`);
  if (!existsSync(src)) fail(`not found: ${arg}`);
  const noFloats = args.includes("--no-floats");
  const keepScratch = args.includes("--keep-scratch");
  const passesArg = args.find((a) => a.startsWith("--max-passes="));
  const passesIndex = args.indexOf("--max-passes");
  const maxPasses = passesArg
    ? Number(passesArg.split("=")[1])
    : passesIndex >= 0
      ? Number(args[passesIndex + 1])
      : 0;

  const cwd = dirname(src);
  const out = src.slice(0, -4) + ".docx";
  const csl = await ensureApaCsl();
  const stockDir = buildReference();
  const scratch = mkdtempSync(join(tmpdir(), "typ2docx-floats-"));
  const log = (msg: string) => console.error(`typ2docx: ${msg}`);
  try {
    const referenceDocx = join(stockDir, "reference.docx");
    const typst = buildTypst();
    const anchorsPath = buildAnchors(src, cwd, scratch, typst);
    // Pass 0: source to AST (citeproc and the content filter run here
    // only; the fixpoint and the final render operate on the JSON).
    const astPath = join(scratch, "ast.json");
    run(
      PANDOC,
      [
        src,
        "-f",
        "typst",
        "-t",
        "json",
        "--citeproc",
        "--csl",
        csl,
        "--lua-filter",
        join(DIR, "filter.lua"),
        "-o",
        astPath,
      ],
      cwd,
      { ...process.env, TYP2DOCX_ANCHORS: anchorsPath },
    );
    let doc = JSON.parse(readFileSync(astPath, "utf8"));
    if (!noFloats) {
      doc = await placeFloats(doc, {
        pandoc: PANDOC,
        referenceDocx,
        workDir: scratch,
        cwd,
        log,
        opts: maxPasses > 0 ? { maxPasses } : {},
      });
    }
    const finalPath = join(scratch, "final.json");
    writeFileSync(finalPath, JSON.stringify(doc));
    run(
      PANDOC,
      [
        finalPath,
        "-f",
        "json",
        "-t",
        "docx+native_numbering",
        "--figure-caption-position=above",
        "--reference-doc",
        referenceDocx,
        "-o",
        out,
      ],
      cwd,
    );
    // The house keep-together chain for every table and captioned float,
    // as a docx post-process (pandoc stays pristine).
    chainDocx(out);
    checkEquationLayout(doc, {
      docxPath: out,
      anchors: JSON.parse(readFileSync(anchorsPath, "utf8")),
      workDir: scratch,
      log,
    });
    console.log(`wrote ${out}`);
  } finally {
    rmSync(stockDir, { recursive: true, force: true });
    if (keepScratch) log(`scratch kept at ${scratch}`);
    else rmSync(scratch, { recursive: true, force: true });
  }
}

if (import.meta.main) await typeToDocx(process.argv.slice(2));
