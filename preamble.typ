#let _typ2docx_counter = counter("_typ2docx_counter")
#show math.equation: it => context {
  if it.block {
    [\@\@MATH#_typ2docx_counter.display()\@\@]
    _typ2docx_counter.step()
  } else { it }
}
