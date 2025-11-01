// #let _typ2docx_counter = counter("_typ2docx_counter")
// #show math.equation: it => context {
//   let val = _typ2docx_counter.display()
//   _typ2docx_counter.step()
//   [\@\@MATH#val\@\@]
//   it
//   [\@\@MATH#val\@\@]
// }
//
#let eq = $ frac(pi, 2) $

// block math

#lorem(20)

$ Gamma(z) = integral_0^infinity t^{z-1}e^(-t) d t $

#lorem(20)

#eq // define first, invoke later

#lorem(20)

// included math

#include "include.typ"

#lorem(20)

$ "pure text block math" $

#lorem(20)

$$ // empty block math

// inline math

#lorem(10) $frac(pi, 2)$ #lorem(5) $sum_(i=1)^K$ #lorem(5)
text$"no space inline math"$text $"pure text inline math"$
$k$-means
