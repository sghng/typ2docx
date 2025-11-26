// ExportToWord.js - Folder-Level Script for Adobe Acrobat
// Place in: ~/Library/Application Support/Adobe/Acrobat/DC/JavaScripts/

ExportToWord = app.trustedFunction(function () {
  var outputPath =
    "/Macintosh HD/Users/sghuang/Library/Containers/com.adobe.Acrobat.Pro/Data/tmp/test.docx";
  app.beginPriv();
  doc.saveAs({
    cPath: outputPath,
    cConvID: "com.adobe.acrobat.docx",
    bPromptToOverwrite: false,
  });
  app.endPriv();
});
