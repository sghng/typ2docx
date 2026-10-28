// Evaluate Typst's own counters for the Word export. The JSON carries
// heading and equation sequences for AST alignment, plus the displayed
// text of every referenceable label. Locations are used only for counters,
// never for page geometry.
{
  let refs = (:)
  let headings = ()
  let equations = ()
  let with-prefix = (prefix, n) => if prefix == "" { n } else { prefix + " " + n }
  let content-text = x => {
    if type(x) == str { x }
    else if type(x) == content and x.has("text") { x.text }
    else { "" }
  }

  let c = (l1: 0, l2: 0, l3: 0, l4: 0, l5: 0, l6: 0)
  let previous-scheme = none
  for h in query(heading) {
    if h.numbering != previous-scheme {
      c = (l1: 0, l2: 0, l3: 0, l4: 0, l5: 0, l6: 0)
      previous-scheme = h.numbering
    }
    let key = if h.has("label") { str(h.label) } else { "" }
    let n = ""
    if h.numbering != none {
      let k = "l" + str(h.level)
      c.insert(k, c.at(k) + 1)
      for i in range(h.level + 1, 7) { c.insert("l" + str(i), 0) }
      n = numbering(h.numbering, ..range(1, h.level + 1).map(i => c.at("l" + str(i))))
      if key != "" {
        let supplement = content-text(h.supplement)
        if h.supplement != none and type(h.supplement) != content and supplement == "" {
          supplement = "Section"
        }
        refs.insert(key, with-prefix(supplement, n.trim(".")))
      }
    }
    headings.push((key: key, level: h.level, number: n))
  }

  for f in query(figure) {
    if f.has("label") and f.numbering != none {
      let n = numbering(f.numbering, ..counter(figure.where(kind: f.kind)).at(f.location()))
      let supplement = content-text(f.supplement)
      if f.supplement != none and type(f.supplement) != content and supplement == "" {
        supplement = if f.kind == table { "Table" } else { "Figure" }
      }
      refs.insert(str(f.label), with-prefix(supplement, n))
    }
  }

  for e in query(math.equation) {
    if e.block {
      let key = if e.has("label") { str(e.label) } else { "" }
      let n = if e.numbering == none { "" } else {
        numbering(e.numbering, ..counter(math.equation).at(e.location()))
      }
      equations.push((key: key, number: n))
      if key != "" and n != "" {
        let supplement = if e.supplement == none { "" } else { content-text(e.supplement) }
        if e.supplement != none and type(e.supplement) != content and supplement == "" {
          supplement = "Equation"
        }
        // Typst displays the delimiters on the equation but omits them in
        // a reference. Manuscript prose supplies its own parentheses.
        let refn = n.trim("(").trim(")")
        refs.insert(key, with-prefix(supplement, refn))
      }
    }
  }

  (refs: refs, headings: headings, equations: equations)
}
