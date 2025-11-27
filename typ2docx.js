// biome-ignore lint/correctness/noUnusedVariables: attached to Acrobat globals
const typ2Docx = app.trustedFunction(function (port) {
	app.beginPriv();
	const path = app.getPath("user", "temp") + "/" + "typ2docx-" + port + ".docx";
	this.saveAs({ cPath: path, cConvID: "com.adobe.acrobat.docx" });
	const params = {}; // Acrobat doesn't recognize multi-line objects
	params.cVerb = "POST";
	params.cURL = "http://localhost:" + port;
	params.oRequest = Net.streamFromString(path);
	Net.HTTP.request(params);
	app.endPriv();
});
