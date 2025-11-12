#let eq = $ frac(pi, 2) $

// block math

#lorem(20)

$ Gamma(z) = integral_0^infinity t^{z-1}e^(-t) d t $

#lorem(20)

#eq // define first, invoke later

#lorem(20)

// included math

#include "../include.typ" // tests including from parent dirs

#lorem(20)

$ "pure text block math" $

#lorem(20) Empty block math follows:

$$ // considered block math

// inline math

#lorem(10) $frac(pi, 2)$ #lorem(5) $sum_(i=1)^K$ #lorem(5)
text$"no space inline math"$text $"pure text inline math"$
$k$-means

$pi$ // inline math on its own paragraph

empty inline math $$ emtpy.

text #text(fill: red)[some text, and a $"equation" sum$, and more text] text
