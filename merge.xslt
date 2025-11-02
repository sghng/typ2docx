<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:local="local-functions"
>
  <!-- Load documents -->
  <!-- TODO: pass real paths -->
  <xsl:variable
    name="doc-a" select="document('typ2docx.a.d/word/document.xml')"
  ></xsl:variable>
  <xsl:variable
    name="doc-b" select="document('typ2docx.b.d/word/document.xml')"
  ></xsl:variable>

  <xsl:variable name="marker-pattern" select="'^@@MATH\d+@@$'"/>

  <!-- Pre-index all block math markers -->

  <!--
    In src document, opening markers may be in the same paragraph with pure text
    equations. It's not pretty printed either, trailing spaces may be present.
  -->
  <xsl:variable
    name="block-markers-a"
    as="element(w:p)*"
    select="$doc-a//w:p[.//w:t[
      matches(normalize-space(string(.)), $marker-pattern)
    ]]"
  />

  <!-- w:p with exactly one w:r containing one w:t matching the pattern -->
  <xsl:variable
    name="block-markers-b"
    as="element(w:p)*"
    select="$doc-b//w:p[count(.//w:t) = 1 and matches(.//w:t, $marker-pattern)]"
  />

  <xsl:variable name="block-math-paragraphs" as="element(w:p)*"
    select="for $i in (1 to count($block-markers-b))[. mod 2 = 1]
            return $block-markers-b[$i]/following-sibling::w:p[1]"/>

  <!-- Build start marker list (ordered by appearance in doc-a) -->
  <xsl:variable name="start-markers" select="$block-markers-a[position() mod 2 = 1]"/>

  <!-- Function to check if a paragraph is a marker -->
  <xsl:function name="local:is-start-marker" as="xs:boolean">
    <xsl:param name="para" as="element(w:p)"/>
    <xsl:sequence select="some $m in $start-markers satisfies ($m is $para)"/>
  </xsl:function>

  <xsl:function name="local:is-end-marker" as="xs:boolean">
    <xsl:param name="para" as="element(w:p)"/>
    <xsl:sequence select="some $m in $block-markers-a satisfies ($m is $para) and not(local:is-start-marker($para))"/>
  </xsl:function>

  <!-- Default: copy everything as-is -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Start transformation from document -->
  <xsl:template match="/">
    <xsl:apply-templates select="$doc-a//w:document"/>
  </xsl:template>

  <!-- Accumulator for state machine: track if we're in a marker range -->
  <xsl:accumulator name="in-range" as="xs:boolean" initial-value="false()">
    <xsl:accumulator-rule match="w:p[local:is-start-marker(.)]" select="true()"/>
    <xsl:accumulator-rule match="w:p[local:is-end-marker(.)]" select="false()"/>
  </xsl:accumulator>

  <!-- Accumulator for marker index -->
  <xsl:accumulator name="marker-index" as="xs:integer" initial-value="0">
    <xsl:accumulator-rule match="w:p[local:is-start-marker(.)]" select="$value + 1"/>
  </xsl:accumulator>

  <!-- w:body: copy as-is, but process direct children in merge mode -->
  <xsl:template match="w:body">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="*" mode="merge"/>
    </xsl:copy>
  </xsl:template>

  <!-- Start marker paragraph: insert replacement, skip marker -->
  <xsl:template match="w:p[local:is-start-marker(.)]" mode="merge">
    <xsl:variable name="index" select="accumulator-after('marker-index')"/>
    <xsl:if test="$index &lt;= count($block-math-paragraphs)">
      <xsl:copy-of select="$block-math-paragraphs[$index]"/>
    </xsl:if>
  </xsl:template>

  <!-- End marker paragraph: skip -->
  <xsl:template match="w:p[local:is-end-marker(.)]" mode="merge"/>

  <!-- Default: if in range, skip; otherwise copy as-is -->
  <xsl:template match="*" mode="merge">
    <xsl:if test="not(accumulator-before('in-range'))">
      <xsl:copy-of select="."/>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
