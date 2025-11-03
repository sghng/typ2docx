<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:local="local"
>
  <!-- TODO: pass real paths -->
  <xsl:variable name="doc-a" select="document('typ2docx.a.d/word/document.xml')"></xsl:variable>
  <xsl:variable name="doc-b" select="document('typ2docx.b.d/word/document.xml')"></xsl:variable>

  <!-- Block math is the single m:oPara child of <w:p> -->
  <xsl:variable name="math-block" as="element(w:p)*" select="$doc-b//w:p"/>
  <!-- Inline math is a <m:oMath> child of <w:p> (there can be several) -->
  <xsl:variable name="math-inline" as="element(m:oMath)*" select="$doc-b//w:p/m:oMath"/>

  <!--
    Inline math can look exactly like a block marker in its own paragraph.
    Hence we need two distinct markers.
  -->
  <xsl:variable name="marker-block" select="'^@@MATH:BLOCK:\d+@@$'"/>
  <xsl:variable name="marker-inline" select="'^@@MATH:INLINE:\d+@@$'"/>

  <!--
    Block math marker is the only <w:t> child of the only <w:r> child of <w:p>.
    We capture and swap the whole <w:p>.
  -->
  <xsl:function name="local:is-block" as="xs:boolean">
    <xsl:param name="p" as="element(w:p)"/>
    <xsl:sequence select="count($p//w:t) = 1 and matches($p//w:t, $marker-block)"/>
  </xsl:function>
  <!--
    Inline math marker could be in the same <w:t> with other text when there's no space around.
    We capture the <w:t> for future processing.
  -->
  <xsl:function name="local:is-inline" as="xs:boolean">
    <xsl:param name="t" as="element(w:t)"/>
    <xsl:sequence select="matches($t, $marker-inline)"/>
  </xsl:function>

  <!-- Identity template that copies everything by default. Lowest specificity -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Direct processor to process doc-a -->
  <xsl:template match="/">
    <xsl:apply-templates select="$doc-a/w:document"/>
  </xsl:template>

  <!-- Accumulators to track the index. Regular variables are immutable.-->
  <xsl:accumulator name="index-block" as="xs:integer" initial-value="0">
    <xsl:accumulator-rule match="w:p[local:is-block(.)]" select="$value + 1"/>
  </xsl:accumulator>
  <xsl:accumulator name="index-inline" as="xs:integer" initial-value="0">
    <xsl:accumulator-rule match="w:t[local:is-inline(.)]" select="$value + 1"/>
  </xsl:accumulator>

  <!-- If it's block marker paragraph, we replace it with the actual math paragraph. -->
  <xsl:template match="w:p[local:is-block(.)]">
    <xsl:variable name="index" select="accumulator-after('index-block')"/>
    <xsl:copy-of select="$math-block[$index]"/>
  </xsl:template>

  <!-- When inline math marker takes the whole run, we replace that run with m:oMath. -->
  <xsl:template match="w:r[count(w:t) = 1 and w:t[local:is-inline(.)]]">
    <xsl:variable name="index" select="accumulator-after('index-inline')"/>
    <xsl:copy-of select="$math-inline[$index]"/>
  </xsl:template>

  <!-- TODO: handle multiple inline markers in the same run -->
  <!--
    If it's not in its own run, we need to split that run from the marker, and
   insert w:oMath between the two separated runs.
  -->

</xsl:stylesheet>
