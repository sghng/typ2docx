typ2DocxVersion = "0.6.0";
typ2DocxExport = app.trustedFunction(function (filename) {
	app.beginPriv();
	path = app.getPath("user", "temp") + "/" + filename;
	app.alert(path);
	this.saveAs({ cPath: path });
	app.endPriv();
});
