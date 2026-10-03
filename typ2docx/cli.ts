#!/usr/bin/env bun
/**
 * typ2docx/cli.ts -- the `abstract typ2docx` command.
 *
 * Converts a Typst source to Word beside it: house reference stock
 * rebuilt fresh from the patch series, citeproc, native numbering, the
 * content-adjustment filter (filter.lua), and the float placement
 * fixpoint (floats.ts) for blocks the Typst reader marked with a
 * placement keyval. No server or model involved.
 *
 *   abstract typ2docx <file.typ> [--no-floats] [--max-passes N]
 *                                  [--keep-scratch]
 */
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chainDocx } from "./chain.ts";
import { placeFloats } from "./floats.ts";

const DIR = dirname(fileURLToPath(import.meta.url));
const HARNESS_DIR = resolve(DIR, "..");

function fail(message: string): never {
  console.error(`abstract: ${message}`);
  process.exit(1);
}

function run(cmd: string, args: string[], cwd?: string): void {
  const r = spawnSync(cmd, args, { encoding: "utf8", cwd });
  if (r.error) fail(`${cmd} not runnable: ${r.error.message}`);
  if (r.status !== 0) {
    process.stderr.write(r.stderr ?? "");
    process.exit(r.status ?? 1);
  }
}

/** Build the house reference stock into a private temp dir and return the
 *  dir path. Rebuilt on every conversion: the patch series is the single
 *  source of truth and nothing is cached. Quiet on success; the build
 *  log only surfaces when the build fails. */
function buildReference(): string {
  const script = join(HARNESS_DIR, "tools", "build-reference.sh");
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

/** Convert a Typst source to Word beside it. Pandoc runs from the
 *  source's directory so relative bibliography and asset paths in the
 *  .typ resolve as they do when drafting there. */
export async function typeToDocx(args: string[]): Promise<void> {
  const arg = args.find((a) => !a.startsWith("--"));
  if (!arg) fail("usage: abstract typ2docx <file.typ> [--no-floats]");
  const src = resolve(arg);
  if (!src.endsWith(".typ")) fail(`not a .typ file: ${arg}`);
  if (!existsSync(src)) fail(`not found: ${arg}`);
  const noFloats = args.includes("--no-floats");
  const keepScratch = args.includes("--keep-scratch");
  const passesArg = args.find((a) => a.startsWith("--max-passes="));
  const maxPasses = passesArg ? Number(passesArg.split("=")[1]) : 0;

  const cwd = dirname(src);
  const out = src.slice(0, -4) + ".docx";
  const stockDir = buildReference();
  const scratch = mkdtempSync(join(tmpdir(), "typ2docx-floats-"));
  const log = (msg: string) => console.error(`typ2docx: ${msg}`);
  try {
    const referenceDocx = join(stockDir, "reference.docx");
    // Pass 0: source to AST (citeproc and the content filter run here
    // only; the fixpoint and the final render operate on the JSON).
    const astPath = join(scratch, "ast.json");
    run(
      "pandoc",
      [
        src,
        "-f",
        "typst",
        "-t",
        "json",
        "--citeproc",
        "--lua-filter",
        join(DIR, "filter.lua"),
        "-o",
        astPath,
      ],
      cwd,
    );
    let doc = JSON.parse(readFileSync(astPath, "utf8"));
    if (!noFloats) {
      doc = await placeFloats(doc, {
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
      "pandoc",
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
    console.log(`wrote ${out}`);
  } finally {
    rmSync(stockDir, { recursive: true, force: true });
    if (keepScratch) log(`scratch kept at ${scratch}`);
    else rmSync(scratch, { recursive: true, force: true });
  }
}
