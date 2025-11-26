// biome-ignore lint/correctness/noUnusedVariables: attached to Acrobat globals
var typ2DocxExport = app.trustedFunction(function (filename) {
	app.beginPriv();
	const path = app.getPath("user", "temp") + "/" + filename;
	this.saveAs({ cPath: path, cConvID: "com.adobe.acrobat.docx" });
	app.endPriv();
});
