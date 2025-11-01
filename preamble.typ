#let _typ2docx_counter = counter("_typ2docx_counter")
#show math.equation: it => context {
  let val = _typ2docx_counter.display()
  [\@\@MATH#val\@\@]
  it
  [\@\@MATH#val\@\@]
  _typ2docx_counter.step()
}
