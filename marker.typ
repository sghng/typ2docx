// adds unique markers around math
#let marker(doc) = {
  let counter = state("math", 0)
  show math.equation: it => context {
    let val = counter.get()
    [\@\@MATH#val\@\@]
    it
    [\@\@MATH#val\@\@]
    counter.update(val + 1)
  }
  doc
}
