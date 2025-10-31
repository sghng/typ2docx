<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="3.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    exclude-result-prefixes="xs w">

    <xsl:output method="xml" indent="yes" encoding="UTF-8" standalone="yes"/>

    <!-- Input parameters: paths to document a and b -->
    <!-- If doc-a-path is provided, use it; otherwise use the primary input document -->
    <xsl:param name="doc-a-path" select="''"/>
    <xsl:param name="doc-b-path" select="'typ2docx.b.d/word/document.xml'"/>
    
    <!-- Load documents -->
    <!-- Doc a: use parameter if provided, otherwise use primary input (current document) -->
    <xsl:variable name="doc-a" select="if ($doc-a-path != '') then document($doc-a-path) else /"/>
    <!-- Doc b: always from parameter -->
    <xsl:variable name="doc-b" select="document($doc-b-path)"/>

    <!-- Match root element: process doc a -->
    <xsl:template match="/">
        <xsl:choose>
            <!-- If doc-a-path is provided, process that document -->
            <xsl:when test="$doc-a-path != ''">
                <xsl:apply-templates select="$doc-a/*"/>
            </xsl:when>
            <!-- Otherwise, process the primary input document -->
            <xsl:otherwise>
                <xsl:apply-templates select="*"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- Identity template -->
    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <!-- BLOCK MATH: Start marker paragraph (contains only marker like @@MATH0@@) -->
    <xsl:template match="w:p[normalize-space(string-join(.//text(), '')) = '@@MATH' or starts-with(normalize-space(string-join(.//text(), '')), '@@MATH')]">
        <xsl:variable name="para-text" select="normalize-space(string-join(.//text(), ''))"/>
        
        <!-- Check if this is a start marker (not preceded by another marker paragraph) -->
        <xsl:variable name="is-start-marker" select="not(preceding-sibling::w:p[normalize-space(string-join(.//text(), '')) = $para-text or starts-with(normalize-space(string-join(.//text(), '')), $para-text)])"/>
        
        <xsl:choose>
            <!-- Start marker paragraph -->
            <xsl:when test="$is-start-marker">
                <!-- Extract marker pattern -->
                <xsl:variable name="marker-pattern" select="$para-text"/>
                <xsl:variable name="marker-num">
                    <xsl:analyze-string select="$marker-pattern" regex="@@MATH(\d+)@@">
                        <xsl:matching-substring>
                            <xsl:value-of select="regex-group(1)"/>
                        </xsl:matching-substring>
                    </xsl:analyze-string>
                </xsl:variable>
                
                <!-- Find position (count preceding start markers in doc a) -->
                <xsl:variable name="pos" select="count(preceding::w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)][not(preceding-sibling::w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)])]) + 1"/>
                
                <!-- Find corresponding start marker paragraph in doc b -->
                <xsl:variable name="ref-start" select="($doc-b//w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)][not(preceding-sibling::w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)])])[$pos]"/>
                
                <!-- Find end marker paragraph in doc b -->
                <xsl:variable name="ref-end" select="$ref-start/following-sibling::w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)][1]"/>
                
                <!-- Copy the ONE paragraph between markers from doc b -->
                <xsl:copy-of select="$ref-start/following-sibling::w:p[. &gt;&gt; $ref-start and . &lt;&lt; $ref-end]"/>
                
                <!-- Skip to after end marker paragraph in source doc a -->
                <xsl:variable name="my-end" select="following-sibling::w:p[normalize-space(string-join(.//text(), '')) = $marker-pattern or starts-with(normalize-space(string-join(.//text(), '')), $marker-pattern)][1]"/>
                <xsl:apply-templates select="$my-end/following-sibling::w:p"/>
            </xsl:when>
            
            <!-- End marker paragraph: skip it -->
            <xsl:otherwise/>
        </xsl:choose>
    </xsl:template>

    <!-- BLOCK MATH: Skip paragraphs between start and end marker -->
    <xsl:template match="w:p[
        preceding-sibling::w:p[normalize-space(string-join(.//text(), '')) = '@@MATH' or starts-with(normalize-space(string-join(.//text(), '')), '@@MATH')][1] and
        not(normalize-space(string-join(.//text(), '')) = '@@MATH') and
        not(starts-with(normalize-space(string-join(.//text(), '')), '@@MATH')) and
        following-sibling::w:p[normalize-space(string-join(.//text(), '')) = '@@MATH' or starts-with(normalize-space(string-join(.//text(), '')), '@@MATH')]
    ]"/>

</xsl:stylesheet>