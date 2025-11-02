<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:local="local"
>
  <!-- TODO: pass real paths -->
  <xsl:variable
    name="doc-a" select="document('typ2docx.a.d/word/document.xml')"
  ></xsl:variable>
  <xsl:variable
    name="doc-b" select="document('typ2docx.b.d/word/document.xml')"
  ></xsl:variable>

  <xsl:variable name="marker-pattern" select="'^@@MATH\d+@@$'"/>

  <xsl:variable
    name="math-paragraphs-b"
    as="element(w:p)*"
    select="$doc-b//w:p"
  />

  <xsl:function name="local:is-marker" as="xs:boolean">
    <xsl:param name="p" as="element(w:p)"/>
    <xsl:sequence select="count($p//w:t) = 1 and matches($p//w:t, $marker-pattern)"/>
  </xsl:function>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/">
    <xsl:apply-templates select="$doc-a/w:document"/>
  </xsl:template>

  <xsl:accumulator name="marker-index" as="xs:integer" initial-value="0">
    <xsl:accumulator-rule match="w:p[local:is-marker(.)]" select="$value + 1"/>
  </xsl:accumulator>

  <xsl:template match="w:p[local:is-marker(.)]">
    <xsl:variable name="index" select="accumulator-after('marker-index')"/>
    <xsl:copy-of select="$math-paragraphs-b[$index]"/>
  </xsl:template>
</xsl:stylesheet>
