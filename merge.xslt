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
  <xsl:variable name="doc-a" select="document('a.d/word/document.xml')"/>
  <xsl:variable name="doc-b" select="document('b.d/word/document.xml')"/>

  <!-- OBTAIN MATH ELEMENTS FROM B -->

  <!-- Block math paragraphs contain m:oMathPara -->
  <xsl:variable
    name="math-block"
    as="element(w:p)*"
    select="$doc-b//w:p[m:oMathPara]"
  />
  <!-- Block math content as m:oMath, used when marker isn't isolated. -->
  <xsl:variable
    name="math-block-inline"
    as="element(m:oMath)*"
    select="$doc-b//w:p[m:oMathPara]/m:oMathPara/m:oMath"
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
  -->
  <xsl:variable name="marker-block" select="'@@MATH:BLOCK:\d+@@'"/>
  <xsl:variable name="marker-inline" select="'@@MATH:INLINE:\d+@@'"/>

  <!--
    Block math marker is the only <w:t> child of the only <w:r> child of <w:p>.
    We capture and swap the whole <w:p>.
  -->
  <xsl:function name="local:is-block" as="xs:boolean">
    <xsl:param name="p" as="element(w:p)"/>
    <xsl:sequence
      select="matches(string-join($p//w:t, ''), concat('^', $marker-block, '$'))"
    />
  </xsl:function>

  <!-- PROCESSING -->

  <!-- Direct processor to process A, the entry point -->
  <xsl:template name="main" match="/">
    <xsl:apply-templates select="$doc-a/w:document"/>
  </xsl:template>

  <!-- Identity template that copies everything from A by default. -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Extract index (digits between : and @@) from marker. -->
  <xsl:function name="local:extract-marker-index" as="xs:integer">
    <xsl:param name="marker" as="xs:string"/>
    <xsl:variable name="index" select="replace($marker, '.*:(\d+)@@', '$1')"/>
    <xsl:sequence select="xs:integer($index)"/>
  </xsl:function>

  <!--
    If it's a block marker paragraph in A, replace it with the actual math
    paragraph from B.
  -->
  <xsl:template match="w:p[local:is-block(.)]">
    <xsl:variable name="marker" select="string(.//w:t)"/>
    <xsl:copy-of select="$math-block[local:extract-marker-index($marker)]"/>
  </xsl:template>

  <!--
    Split w:t on inline markers and return a sequence of elements:

    - Marker segments replaced with the corresponding m:oMath
    - Non-marker segments wrapped in w:r elements, with rPr included
  -->
  <xsl:function name="local:process-t" as="element()*">
    <xsl:param name="t" as="element(w:t)"/>
    <xsl:param name="rPr" as="element(w:rPr)?"/>
    <xsl:analyze-string select="string($t)" regex="{$marker-inline}">
      <xsl:matching-substring>
        <xsl:variable name="marker" select="."/>
        <xsl:copy-of select="$math-inline[local:extract-marker-index($marker)]"/>
      </xsl:matching-substring>
      <xsl:non-matching-substring>
        <w:r>
          <xsl:copy-of select="$rPr"/>
          <w:t><xsl:value-of select="."/></w:t>
        </w:r>
      </xsl:non-matching-substring>
    </xsl:analyze-string>
  </xsl:function>

  <!--
    Split w:t on block markers and replace marker segments with corresponding
    m:oMath. This is a fallback for converters that merge neighboring content
    and marker into one paragraph.
  -->
  <xsl:function name="local:process-t-block" as="element()*">
    <xsl:param name="t" as="element(w:t)"/>
    <xsl:param name="rPr" as="element(w:rPr)?"/>
    <xsl:analyze-string select="string($t)" regex="{$marker-block}">
      <xsl:matching-substring>
        <xsl:variable name="marker" select="."/>
        <xsl:copy-of
          select="$math-block-inline[local:extract-marker-index($marker)]"
        />
      </xsl:matching-substring>
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
    <xsl:variable name="rPr" select="w:rPr"/>
    <xsl:for-each select="*">
      <xsl:choose>
        <xsl:when test="self::w:rPr"/>
        <xsl:when test="self::w:t">
          <xsl:copy-of select="local:process-t(., $rPr)"/>
        </xsl:when>
        <xsl:otherwise>
          <w:r>
            <xsl:copy-of select="$rPr"/>
            <xsl:copy-of select="."/>
          </w:r>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

  <!--
    Fallback for block markers that appear inside a mixed-content paragraph.
    We inject m:oMath at marker position to avoid leaving raw marker text.
  -->
  <xsl:template match="w:r[w:t[matches(., $marker-block)]]" priority="2">
    <xsl:variable name="rPr" select="w:rPr"/>
    <xsl:for-each select="*">
      <xsl:choose>
        <xsl:when test="self::w:rPr"/>
        <xsl:when test="self::w:t">
          <xsl:copy-of select="local:process-t-block(., $rPr)"/>
        </xsl:when>
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
