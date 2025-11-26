// ExportToWord.js - Folder-Level Script for Adobe Acrobat
// Place in: ~/Library/Application Support/Adobe/Acrobat/DC/JavaScripts/

ExportToWord = app.trustedFunction(function () {
  app.beginPriv();

  var doc = this;
  var docPath = doc.path;
  var pathSep = docPath.indexOf("\\") >= 0 ? "\\" : "/";
  var lastSep = docPath.lastIndexOf(pathSep);
  var docDir = docPath.substring(0, lastSep);
  var docName = docPath.substring(lastSep + 1);
  var baseName = docName.replace(/\.pdf$/i, "");
  var outputPath = docDir + pathSep + baseName + ".docx";

  doc.saveAs({
    cPath: outputPath,
    cConvID: "com.adobe.acrobat.docx",
    bPromptToOverwrite: false,
  });

  app.endPriv();
});
