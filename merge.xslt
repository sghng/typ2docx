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
    A util function to extract index (digits between the last : and @@) from
    marker, works for both BLOCK and INLINE markers.
  -->
  <xsl:function name="local:extract-marker-index" as="xs:integer">
    <xsl:param name="marker" as="xs:string"/>
    <xsl:sequence select="xs:integer(replace($marker, '.*:(.+)@@.*', '$1'))"/>
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
    <xsl:copy-of select="$math-block[$index]"/>
  </xsl:template>

  <!--
    Helper function to split w:t on markers and return a sequence of elements:

    - Marker segments replaced with the corresponding m:oMath
    - Non-marker segments wrapped in w:r elements, with rPr included
  -->
  <xsl:function name="local:process-t" as="element()*">
    <xsl:param name="t" as="element(w:t)"/>
    <xsl:param name="rPr" as="element(w:rPr)?"/> <!-- Keep track of run properties -->
    <xsl:analyze-string select="string($t)" regex="{$marker-inline}">
      <!-- Marker segment: replace with math element -->
      <xsl:matching-substring>
        <xsl:variable name="marker" select="."/>
        <xsl:copy-of select="$math-inline[local:extract-marker-index($marker)]"/>
      </xsl:matching-substring>
      <!-- Non-marker segment: create a new run with rPr -->
      <xsl:non-matching-substring>
        <w:r>
          <xsl:copy-of select="$rPr"/>
          <w:t><xsl:value-of select="."/></w:t>
        </w:r>
      </xsl:non-matching-substring>
    </xsl:analyze-string>
  </xsl:function>

  <!--
    Handle w:r elements that contain inline markers.

    This'll create more runs than needed, which doesn't interfere with the
    functionality of Word, but helps keep the code simple.
  -->
  <xsl:template match="w:r[w:t[matches(., $marker-inline)]]">
    <xsl:variable name="rPr" select="w:rPr"/> <!-- Keep track of run properties -->
    <xsl:for-each select="*"> <!-- Iterate the run -->
      <xsl:choose>
        <xsl:when test="self::w:rPr"></xsl:when> <!-- Skip w:rPr -->
        <!-- Process w:t, works the same w/ or w/out markers -->
        <xsl:when test="self::w:t">
          <xsl:copy-of select="local:process-t(., $rPr)"/>
        </xsl:when>
        <!-- Other elements: copy as-is in a new w:r -->
        <xsl:otherwise>
          <w:r>
            <xsl:copy-of select="$rPr"/>
            <xsl:copy-of select="."/>
          </w:r>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

</xsl:stylesheet>
