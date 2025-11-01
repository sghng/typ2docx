<xsl:stylesheet
  version="3.0"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
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
    equations
  -->
  <xsl:variable
    name="block-markers-a"
    as="element(w:p)*"
    select="$doc-a//w:p[.//w:t[matches(string(.), $marker-pattern)]]"
  />

  <!-- w:p with exactly one w:r containing one w:t matching the pattern -->
  <xsl:variable
    name="block-markers-b"
    as="element(w:p)*"
    select="$doc-b//w:p[count(.//w:t) = 1 and matches(.//w:t, $marker-pattern)]"
  />

  <xsl:variable name="block-math-paragraphs" as="element(w:p)*">
    <xsl:for-each select="$block-markers-b">
      <xsl:if test="position() mod 2 = 1"> <!-- xsl is 1-based, odd = start marker -->
        <xsl:sequence select="following-sibling::w:p[1]"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>

  <!-- dummy empty output to satisfy processor -->
  <xsl:template match="/">
    <math-paragraphs>
      <xsl:copy-of select="$block-math-paragraphs"/>
    </math-paragraphs>
  </xsl:template>
</xsl:stylesheet>
