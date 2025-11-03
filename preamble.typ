#let _typ2docx_counter = counter("_typ2docx_counter")
#show math.equation: it => context {
  if it.body == [] { it } else {
    let kind = if it.block { "BLOCK" } else { "INLINE" }
    [\@\@MATH:#kind:#_typ2docx_counter.display()\@\@]
    _typ2docx_counter.step()
  }
}
