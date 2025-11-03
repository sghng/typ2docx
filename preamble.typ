#let _typ2docx_counter_block = counter("_typ2docx_counter_block")
#let _typ2docx_counter_inline = counter("_typ2docx_counter_inline")
#show math.equation: it => context {
  if it.body == [] { it } else {
    let kind = if it.block { "BLOCK" } else { "INLINE" }
    let counter = if it.block { _typ2docx_counter_block } else {
      _typ2docx_counter_inline
    }
    [\@\@MATH:#kind:#counter.display()\@\@]
    counter.step()
  }
}
