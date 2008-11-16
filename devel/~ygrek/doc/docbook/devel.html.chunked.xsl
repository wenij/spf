<?xml version="1.0" encoding="windows-1251"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:import href="http://docbook.sourceforge.net/release/xsl/current/html/chunk.xsl"/>

  <xsl:include href="devel.basic.xsl"/>

  <!-- ������� ��� ���������� html ������ -->
  <xsl:param name="base.dir" select="'chunked/'"></xsl:param>

  <!-- ��� �����-����� -->
  <xsl:param name="root.filename" select="'index'"></xsl:param>

  <xsl:param name="toc.section.depth" select="1"/>
  <xsl:param name="toc.max.depth">2</xsl:param>
  <xsl:param name="chunk.section.depth" select="1"></xsl:param>
  <xsl:param name="chunk.first.sections" select="0"></xsl:param>

  <!-- ��������� ���������� ��� ��������� �������� ������ -->
  <xsl:param name="generate.toc">
  book toc
  chapter toc
  section nop
  </xsl:param>



</xsl:stylesheet>
