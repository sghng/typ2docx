<!--
  Do leave a lot of comments in this file, otherwise it becomes completely
  unreadable and unmaintainable!
-->

<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:local="local"
>
  <!-- Document paths are relative to the stylesheet location (base_dir) -->
  <xsl:variable
    name="doc-a"
    select="document('a.d/word/document.xml')"
  ></xsl:variable>
  <xsl:variable
    name="doc-b"
    select="document('b.d/word/document.xml')"
  ></xsl:variable>

  <!-- OBTAIN MATH ELEMENTS FROM B -->

  <!-- Block math paragraphs contain m:oMathPara -->
  <xsl:variable
    name="math-block"
    as="element(w:p)*"
    select="$doc-b//w:p[m:oMathPara]"
  />
  <!--
    Inline math is a <m:oMath> child of <w:p> (there can be several), that is
    not in m:oMathPara.
  -->
  <xsl:variable
    name="math-inline"
    as="element(m:oMath)*"
    select="$doc-b//w:p/m:oMath[not(parent::m:oMathPara)]"
  />

  <!-- FIND MARKERS IN A -->

  <!--
    Inline marker, when in its own paragraph, can look exactly like a block
    marker, i.e. can't be distinguished by examining the ancestors. Hence we
    need two distinct markers.

    - Block marker always has anchors (for whole-paragraph matching).
    - Inline marker never has anchors (multiple can appear together in <w:t>).
    - Capture groups are included for index extraction.
  -->
  <xsl:variable name="marker-block" select="'^@@MATH:BLOCK:(\d+)@@$'"/>
  <xsl:variable name="marker-inline" select="'@@MATH:INLINE:(\d+)@@'"/>

  <!--
    Block math marker is the only <w:t> child of the only <w:r> child of <w:p>.
    We capture and swap the whole <w:p>.
  -->
  <xsl:function name="local:is-block" as="xs:boolean">
    <xsl:param name="p" as="element(w:p)"/>
    <xsl:sequence
      select="count($p//w:t) = 1 and matches($p//w:t, $marker-block)"
    />
  </xsl:function>

  <!--
    Inline math marker could be in the same <w:t> with other text when there's
    no space around. We capture the <w:t> for future processing.
  -->
  <xsl:function name="local:is-inline" as="xs:boolean">
    <xsl:param name="t" as="element(w:t)"/>
    <xsl:sequence select="matches($t, $marker-inline)"/>
  </xsl:function>

  <!--
    Split text on markers, returning a sequence of strings alternating between
    marker strings and regular text segments.
  -->
  <xsl:function name="local:split-on-marker" as="xs:string*">
    <xsl:param name="text" as="xs:string"/>
    <xsl:analyze-string select="$text" regex="{$marker-inline}">
      <xsl:matching-substring>
        <xsl:sequence select="."/>
      </xsl:matching-substring>
      <xsl:non-matching-substring>
        <xsl:sequence select="."/>
      </xsl:non-matching-substring>
    </xsl:analyze-string>
  </xsl:function>

  <!-- PROCESSING -->

  <!-- Direct processor to process A, the entry point -->
  <xsl:template name="main" match="/">
    <xsl:apply-templates select="$doc-a/w:document"/>
  </xsl:template>

  <!--
    Identity template that copies everything from A by default. Lowest
    specificity.
  -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!--
    A util function to extract index from marker, works for both BLOCK and
    INLINE markers.
  -->
  <xsl:function name="local:extract-marker-index" as="xs:integer">
    <xsl:param name="marker" as="xs:string"/>
    <xsl:variable
      name="pattern"
      select="replace($marker-block, 'BLOCK', '(?:BLOCK|INLINE)')"
    />
    <xsl:sequence select="xs:integer(replace($marker, $pattern, '$1'))"/>
  </xsl:function>

  <!--
    If it's a block marker paragraph in A, we replace it with the actual math
    paragraph from B.
  -->
  <xsl:template match="w:p[local:is-block(.)]">
    <xsl:variable
      name="index"
      select="local:extract-marker-index(string(.//w:t))"
    />
    <xsl:copy-of select="$math-block[$index + 1]"/>
  </xsl:template>

  <!-- HACK: This is vibecoded, I have no idea how it worked. -->

  <!-- Handle w:r elements that contain inline markers -->
  <xsl:template match="w:r[w:t[matches(., $marker-inline)]]">
    <xsl:variable name="rPr" select="w:rPr"/>
    <xsl:for-each select="w:t">
      <xsl:variable name="t" select="."/>
      <xsl:choose>
        <xsl:when test="matches(normalize-space($t), $marker-inline)">
          <!-- This w:t contains only a marker (normalized), output math -->
          <xsl:variable name="marker-num" select="local:extract-marker-index(normalize-space($t))"/>
          <xsl:copy-of select="$math-inline[$marker-num + 1]"/>
        </xsl:when>
        <xsl:when test="matches($t, $marker-inline)">
          <!-- This w:t contains markers mixed with other text, split it -->
          <xsl:variable name="segments" select="local:split-on-marker(string($t))"/>
          <xsl:for-each select="$segments">
            <xsl:variable name="segment" select="."/>
            <xsl:choose>
              <xsl:when test="matches($segment, $marker-inline)">
                <!-- This is a marker, extract its number and output math -->
                <xsl:variable name="marker-num" select="local:extract-marker-index($segment)"/>
                <xsl:copy-of select="$math-inline[$marker-num + 1]"/>
              </xsl:when>
              <xsl:otherwise>
                <!-- Regular text, create new w:r if segment is not empty -->
                <xsl:if test="normalize-space($segment) ne ''">
                  <xsl:element name="w:r">
                    <xsl:copy-of select="$rPr"/>
                    <xsl:element name="w:t">
                      <xsl:copy-of select="$t/@*"/>
                      <xsl:value-of select="$segment"/>
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
