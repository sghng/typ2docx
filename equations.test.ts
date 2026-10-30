import { describe, expect, test } from "bun:test";
import {
  collectEquations,
  equationContentBounds,
  equationLayoutProblem,
  equationTableFractions,
  hasAuthoredMultiline,
  injectEquationTokens,
  parseEquationBbox,
} from "./equations.ts";
import type { PandocDoc } from "./floats.ts";

const math = (mathtype: string, tex: string) => ({
  t: "Math",
  c: [{ t: mathtype }, tex],
});

const displayMath = (tex: string) => math("DisplayMath", tex);

describe("equation manifest", () => {
  test("collects display math and aligned anchor labels", () => {
    const doc: PandocDoc = {
      "pandoc-api-version": [1, 23],
      meta: {},
      blocks: [
        {
          t: "Para",
          c: [
            math("InlineMath", "x"),
            displayMath("a = b"),
            { t: "Span", c: [["eq:first", [], []], []] },
          ],
        },
        {
          t: "Div",
          c: [
            ["", ["mark"], []],
            [
              {
                t: "Para",
                c: [
                  displayMath("\\\\begin{aligned}a &= b\\\\\\\\c &= d\\\\end{aligned}"),
                  { t: "Span", c: [["eq:aligned", [], []], []] },
                ],
              },
              { t: "Note", c: [[{ t: "Para", c: [displayMath("ignored = 1")] }]] },
            ],
          ],
        },
      ],
    };
    const equations = collectEquations(doc, {
      equations: [
        { key: "eq:first", number: "(1)" },
        { key: "eq:aligned", number: "(2)" },
      ],
    });
    expect(equations).toHaveLength(2);
    expect(equations[0]).toMatchObject({
      index: 0,
      tex: "a = b",
      label: "eq:first",
      number: "(1)",
      authoredMultiline: false,
    });
    expect(equations[1]).toMatchObject({
      index: 1,
      label: "eq:aligned",
      number: "(2)",
      authoredMultiline: true,
    });
  });

  test("withholds anchor numbers when equation counts disagree", () => {
    const doc: PandocDoc = {
      "pandoc-api-version": [1, 23],
      meta: {},
      blocks: [{ t: "Para", c: [displayMath("a = b")] }],
    };
    const equations = collectEquations(doc, { equations: [] });
    expect(equations[0].label).toBe("");
    expect(equations[0].number).toBe("");
  });

  test("keeps actual labels but withholds numbers on key mismatch", () => {
    const doc: PandocDoc = {
      "pandoc-api-version": [1, 23],
      meta: {},
      blocks: [{
        t: "Para",
        c: [
          displayMath("a = b"),
          { t: "Span", c: [["eq:actual", [], []], []] },
        ],
      }],
    };
    const equations = collectEquations(doc, {
      equations: [{ key: "eq:different", number: "(1)" }],
    });
    expect(equations[0].label).toBe("eq:actual");
    expect(equations[0].number).toBe("");
  });
});

describe("authored multiline math", () => {
  test("recognizes explicit rows and alignment environments", () => {
    expect(hasAuthoredMultiline("a = b")).toBe(false);
    expect(hasAuthoredMultiline("\\frac{a}{b}")).toBe(false);
    expect(hasAuthoredMultiline("a = b\\\\c = d")).toBe(true);
    expect(hasAuthoredMultiline("\\begin{split}a &= b\\end{split}")).toBe(true);
    expect(hasAuthoredMultiline("\\begin{cases}a&b\\end{cases}")).toBe(true);
    expect(hasAuthoredMultiline("\\begin{pmatrix}a&b\\end{pmatrix}")).toBe(true);
    expect(hasAuthoredMultiline("\\substack{a\\atop b}")).toBe(true);
  });
});

describe("DOCX equation markers", () => {
  test("marks only display-math paragraphs and preserves their contents", () => {
    const display = "<m:oMathPara><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></m:oMathPara>";
    const inline = "<m:oMath><m:r><m:t>x</m:t></m:r></m:oMath>";
    const xml =
      '<w:document><w:body><w:p><w:pPr><w:pStyle w:val="BodyText"/></w:pPr>' +
      display +
      '</w:p><w:p><w:r><w:t>Before </w:t></w:r>' +
      inline +
      '</w:p><w:p><w:r><w:t>&#x200B;</w:t></w:r>' +
      inline +
      '</w:p><w:p><w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr></w:r>' +
      inline +
      '</w:p><w:p data-probe="attributes">' +
      display +
      "</w:p></w:body></w:document>";
    const result = injectEquationTokens(xml);
    expect(result.count).toBe(2);
    expect(result.xml).toContain("</w:pPr><w:r><w:rPr>");
    expect(result.xml).toContain("XQ000");
    expect(result.xml).toContain("XQ001");
    expect(result.xml).toContain("XQ002");
    expect(result.xml).toContain("XQ003");
    expect(result.xml).not.toContain("XQ004");
    expect(result.xml.match(/<m:oMath>/g)).toHaveLength(5);
    expect(result.xml).toContain('<w:t>Before </w:t>');
    expect(result.xml).toContain('<w:t>&#x200B;</w:t>');
  });

  test("marks the equation cell but not its visible number cell", () => {
    const xml =
      '<w:document><w:body><w:tbl><w:tr><w:tc><w:p>' +
      '<m:oMathPara><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></m:oMathPara>' +
      '</w:p></w:tc><w:tc><w:p><w:r><w:t>(1)</w:t></w:r></w:p>' +
      '</w:tc></w:tr></w:tbl></w:body></w:document>';
    const result = injectEquationTokens(xml);
    expect(result.count).toBe(1);
    const numberPara = result.xml.match(
      /<w:p><w:r><w:t>\(1\)<\/w:t><\/w:r>.*?<\/w:p>/,
    )?.[0];
    expect(numberPara).toBeDefined();
    expect(numberPara).not.toContain("XQ");
    expect(result.xml).toContain("XQ000");
    expect(result.xml).toContain("XQ001");
  });
});

describe("layout verdicts", () => {
  const point = (page = 1, xMin = 72, xMax = 100) => ({
    page,
    xMin,
    xMax,
    yMin: 100,
    yMax: 112,
  });

  test("ignores same-page displacement but reports a page split", () => {
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1), 612,
    )).toBeNull();
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(2), 612,
    )).toBe("wrap");
  });

  test("skips authored multiline math and detects page overflow", () => {
    expect(equationLayoutProblem(
      { authoredMultiline: true }, point(1), point(2), 612,
    )).toBeNull();
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1, 500, 545), 612,
    )).toBe("overflow");
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1, 60, 80), point(1), 612,
    )).toBe("overflow");
  });

  test("uses equation content bounds before marker displacement", () => {
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1), 612,
      { xMin: 95, xMax: 616 },
    )).toBe("overflow");
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1), 612,
      { xMin: 95, xMax: 500 },
    )).toBeNull();
  });

  test("checks numbered equations against their table-cell boundaries", () => {
    const cell = { left: 0.06, right: 0.94 };
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1), 612,
      { xMin: 100, xMax: 520 }, cell,
    )).toBe("cell-overflow");
    expect(equationLayoutProblem(
      { authoredMultiline: false }, point(1), point(1), 612,
      { xMin: 101, xMax: 510 }, cell,
    )).toBeNull();
  });
});

describe("equation table geometry", () => {
  test("reads center-cell fractions without duplicating column policy", () => {
    const xml =
      '<w:document><w:body><w:tbl><w:tblPr>' +
      '<w:tblStyle w:val="Equation" /></w:tblPr><w:tblGrid>' +
      '<w:gridCol w:w="60" /><w:gridCol w:w="880" /><w:gridCol w:w="60" />' +
      '</w:tblGrid></w:tbl><w:tbl><w:tblPr>' +
      '<w:tblStyle w:val="Table" /></w:tblPr></w:tbl></w:body></w:document>';
    expect(equationTableFractions(xml)).toEqual([{ left: 0.06, right: 0.94 }]);
  });
});

describe("PDF word geometry", () => {
  test("records page and horizontal bounds in document order", () => {
    const xml = `<?xml version="1.0"?>
      <doc><page width="612.000000" height="792.000000">
      <line xMin="72" yMin="100" xMax="300" yMax="112">
      <word xMin="72" yMin="101" xMax="91" yMax="111">startXQ000</word>
      </line>
      <line xMin="80" yMin="130" xMax="540" yMax="145">
      <word xMin="500" yMin="133" xMax="540" yMax="142">XQ001end</word>
      </line>
      </page></doc>`;
    const { tokens, words, pageWidths } = parseEquationBbox(xml);
    expect(pageWidths.get(1)).toBe(612);
    expect(equationContentBounds(words, 0)).toEqual({ xMin: 72, xMax: 540 });
    expect(tokens.get("XQ000")).toEqual({
      page: 1, xMin: 72, xMax: 91, yMin: 100, yMax: 112,
    });
    expect(tokens.get("XQ001")).toEqual({
      page: 1, xMin: 500, xMax: 540, yMin: 130, yMax: 145,
    });
  });

  test("rejects a token-only pair with no measurable equation content", () => {
    const xml = `<doc><page width="612" height="792">
      <line xMin="100" yMin="100" xMax="120" yMax="110">
      <word xMin="100" yMin="100" xMax="120" yMax="110">XQ000XQ001</word>
      </line>
      </page></doc>`;
    const { words } = parseEquationBbox(xml);
    expect(equationContentBounds(words, 0)).toBeNull();
  });

  test("excludes the visible number and neighboring prose from math bounds", () => {
    const xml = `<doc><page width="612" height="792">
      <line xMin="300" yMin="100" xMax="310" yMax="112"><word xMin="300" yMin="100" xMax="310" yMax="112">XQ000</word></line>
      <line xMin="400" yMin="104" xMax="500" yMax="116"><word xMin="400" yMin="104" xMax="500" yMax="116">x</word></line>
      <line xMin="527" yMin="100" xMax="540" yMax="112"><word xMin="527" yMin="100" xMax="540" yMax="112">(1)</word></line>
      <line xMin="520" yMin="200" xMax="560" yMax="212"><word xMin="520" yMin="200" xMax="560" yMax="212">prose</word></line>
      <line xMin="310" yMin="114" xMax="320" yMax="126"><word xMin="310" yMin="114" xMax="320" yMax="126">XQ001</word></line>
      </page></doc>`;
    const { words } = parseEquationBbox(xml);
    expect(equationContentBounds(words, 0, "(1)"))
      .toEqual({ xMin: 300, xMax: 500 });
  });
});
