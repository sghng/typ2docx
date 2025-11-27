typ2DocxExport = app.trustedFunction(function (port) {
	try {
		app.beginPriv();
		const path =
			app.getPath("user", "temp") + "/" + "typ2docx-" + port + ".docx";
		this.saveAs({ cPath: path, cConvID: "com.adobe.acrobat.docx" });
		app.endPriv();
		typ2DocxReport(port, { status: "ok", path: path });
	} catch (e) {
		typ2DocxReport(port, {
			status: "error",
			message: e.message,
			stack: e.stack,
		});
	}
});

// biome-ignore lint/complexity/useArrowFunction: trusted functions can't be arrow
typ2DocxReport = app.trustedFunction(function (port, msg) {
	const params = {}; // Acrobat doesn't recognize multi-line objects
	params.cVerb = "POST";
	params.cURL = "http://localhost:" + port;
	params.oRequest = Net.streamFromString(JSON.stringify(msg));
	app.beginPriv();
	Net.HTTP.request(params);
	app.endPriv();
});
