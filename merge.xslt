<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:local="local"
>
  <!-- Document paths are relative to the stylesheet location (base_dir) -->
  <xsl:variable name="doc-a" select="document('a.d/word/document.xml')"></xsl:variable>
  <xsl:variable name="doc-b" select="document('b.d/word/document.xml')"></xsl:variable>

  <!-- Block math paragraphs contain m:oMathPara -->
  <xsl:variable name="math-block" as="element(w:p)*" select="$doc-b//w:p[m:oMathPara]"/>
  <!-- Inline math is a <m:oMath> child of <w:p> (there can be several), but not in m:oMathPara -->
  <xsl:variable name="math-inline" as="element(m:oMath)*" select="$doc-b//w:p/m:oMath[not(parent::m:oMathPara)]"/>

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

  <!-- Tokenize text by splitting on inline markers, returning marker positions -->
  <xsl:function name="local:tokenize-inline-text" as="xs:string*">
    <xsl:param name="text" as="xs:string"/>
    <xsl:variable name="pattern" select="'@@MATH:INLINE:\d+@@'"/>
    <xsl:analyze-string select="$text" regex="({$pattern})">
      <xsl:matching-substring>
        <xsl:value-of select="."/>
      </xsl:matching-substring>
      <xsl:non-matching-substring>
        <xsl:value-of select="."/>
      </xsl:non-matching-substring>
    </xsl:analyze-string>
  </xsl:function>

  <!-- Direct processor to process doc-a, the entry point -->
  <xsl:template name="main" match="/">
    <xsl:apply-templates select="$doc-a/w:document"/>
  </xsl:template>

  <!-- Identity template that copies everything by default. Lowest specificity -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- If it's block marker paragraph, we replace it with the actual math paragraph. -->
  <xsl:template match="w:p[local:is-block(.)]">
    <xsl:variable name="marker-num" select="local:extract-marker-number(string(.//w:t))"/>
    <xsl:copy-of select="$math-block[$marker-num + 1]"/>
  </xsl:template>

  <!-- Extract marker number from marker text (works for both BLOCK and INLINE) -->
  <xsl:function name="local:extract-marker-number" as="xs:integer">
    <xsl:param name="marker" as="xs:string"/>
    <xsl:sequence select="xs:integer(replace($marker, '^@@MATH:(?:BLOCK|INLINE):(\d+)@@$', '$1'))"/>
  </xsl:function>

  <!-- Handle w:r elements that contain inline markers -->
  <xsl:template match="w:r[w:t[matches(., '@@MATH:INLINE:\d+@@')]]">
    <xsl:variable name="rPr" select="w:rPr"/>
    <xsl:for-each select="w:t">
      <xsl:variable name="t" select="."/>
      <xsl:choose>
        <xsl:when test="matches(normalize-space($t), $marker-inline)">
          <!-- This w:t contains only a marker (normalized), output math -->
          <xsl:variable name="marker-num" select="local:extract-marker-number(normalize-space($t))"/>
          <xsl:copy-of select="$math-inline[$marker-num + 1]"/>
        </xsl:when>
        <xsl:when test="matches($t, '@@MATH:INLINE:\d+@@')">
          <!-- This w:t contains markers mixed with other text, tokenize it -->
          <xsl:variable name="tokens" select="local:tokenize-inline-text(string($t))"/>
          <xsl:for-each select="$tokens">
            <xsl:variable name="token" select="."/>
            <xsl:choose>
              <xsl:when test="matches($token, $marker-inline)">
                <!-- This is a marker, extract its number and output math -->
                <xsl:variable name="marker-num" select="local:extract-marker-number($token)"/>
                <xsl:copy-of select="$math-inline[$marker-num + 1]"/>
              </xsl:when>
              <xsl:otherwise>
                <!-- Regular text, create new w:r if token is not empty -->
                <xsl:if test="normalize-space($token) ne ''">
                  <xsl:element name="w:r">
                    <xsl:copy-of select="$rPr"/>
                    <xsl:element name="w:t">
                      <xsl:copy-of select="$t/@*"/>
                      <xsl:value-of select="$token"/>
                    </xsl:element>
                  </xsl:element>
                </xsl:if>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:for-each>
        </xsl:when>
        <xsl:otherwise>
          <!-- This w:t doesn't contain markers, just copy it in a new w:r -->
          <xsl:element name="w:r">
            <xsl:copy-of select="$rPr"/>
            <xsl:copy-of select="$t"/>
          </xsl:element>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

</xsl:stylesheet>
