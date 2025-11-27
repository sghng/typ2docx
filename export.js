// biome-ignore lint/correctness/noUnusedVariables: invoked with setTimeOut
function main() {
	console.println("TYP2DOCX: self exporting to .docx");
	if (typeof typ2Docx === "undefined") {
		app.alert({
			cMsg:
				"Typ2Docx function not found. " +
				"Make sure you've installed the trusted function!",
		});
		return;
	}
	console.println(
		"TYP2DOCX: installed trusted function version: " + typ2DocxVersion
	);
	typ2Docx.call(this, "typ2docx.docx");
}

app.setTimeOut("main()", 1); // queue the function call
