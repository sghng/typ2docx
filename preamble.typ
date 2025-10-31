#let _typ2docx_counter = state("_typ2docx_counter", 0)
#show math.equation: it => context {
  let counter = _typ2docx_counter
  let val = counter.get()
  [\@\@MATH#val\@\@]
  it
  [\@\@MATH#val\@\@]
  counter.update(val + 1)
}
