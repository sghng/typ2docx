<xsl:stylesheet
  version="3.0"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
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

  <xsl:variable name="block-math-paragraphs" as="element(w:p)*">
    <xsl:for-each select="$block-markers-b">
      <!-- xsl is 1-based, odd = start marker -->
      <xsl:if test="position() mod 2 = 1">
        <xsl:sequence select="following-sibling::w:p[1]"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>

  <!-- Output the merged document -->
  <xsl:template match="/">
    <xsl:apply-templates select="$doc-a//w:document"/>
  </xsl:template>

  <!-- Copy document structure -->
  <xsl:template match="w:document">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates select="w:body"/>
    </xsl:copy>
  </xsl:template>

  <!-- Process body, replacing marker sections -->
  <xsl:template match="w:body">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:variable name="body-paras" select="w:p[not(self::w:sectPr)]"/>
      <xsl:variable name="sect-pr" select="w:sectPr"/>
      
      <!-- Build start marker list (ordered by appearance in doc-a) -->
      <xsl:variable name="start-markers" select="$block-markers-a[position() mod 2 = 1]"/>
      
      <!-- Process paragraphs sequentially -->
      <xsl:for-each select="$body-paras">
        <xsl:variable name="para" select="."/>
        <xsl:variable name="pos" select="position()"/>
        
        <!-- Check if this paragraph is a start marker by element identity -->
        <xsl:variable name="is-start-marker" select="some $m in $start-markers satisfies ($m is $para)"/>
        
        <!-- Check if this paragraph is any marker -->
        <xsl:variable name="is-marker" select="some $m in $block-markers-a satisfies ($m is $para)"/>
        
        <!-- Check if this paragraph is an end marker -->
        <xsl:variable name="is-end-marker" select="$is-marker and not($is-start-marker)"/>
        
        <!-- Count unmatched start markers by checking all preceding paragraphs -->
        <xsl:variable name="preceding-starts-count" as="xs:integer*">
          <xsl:for-each select="preceding-sibling::w:p">
            <xsl:if test="some $m in $start-markers satisfies ($m is .)">
              <xsl:sequence select="1"/>
            </xsl:if>
          </xsl:for-each>
        </xsl:variable>
        
        <xsl:variable name="preceding-ends-count" as="xs:integer*">
          <xsl:for-each select="preceding-sibling::w:p">
            <xsl:if test="some $m in $block-markers-a satisfies ($m is .) and not(some $s in $start-markers satisfies ($s is .))">
              <xsl:sequence select="1"/>
            </xsl:if>
          </xsl:for-each>
        </xsl:variable>
        
        <xsl:variable name="unmatched-starts" select="count($preceding-starts-count) - count($preceding-ends-count)"/>
        <xsl:variable name="in-range" select="$unmatched-starts &gt; 0"/>
        
        <xsl:choose>
          <xsl:when test="$is-start-marker">
            <!-- This is a start marker - count how many start markers we've seen before it -->
            <xsl:variable name="marker-index" select="count($preceding-starts-count) + 1"/>
            <xsl:if test="$marker-index &lt;= count($block-math-paragraphs)">
              <xsl:copy-of select="$block-math-paragraphs[$marker-index]"/>
            </xsl:if>
            <!-- Skip this marker paragraph -->
          </xsl:when>
          <xsl:when test="$in-range">
            <!-- This paragraph is between start and end markers - skip it -->
          </xsl:when>
          <xsl:when test="$is-end-marker">
            <!-- This is an end marker - skip it -->
          </xsl:when>
          <xsl:otherwise>
            <!-- This paragraph is outside marker ranges - copy it -->
            <xsl:copy-of select="$para"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      
      <xsl:copy-of select="$sect-pr"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
