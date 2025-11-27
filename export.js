// biome-ignore lint/correctness/noUnusedVariables: invoked with setTimeOut
const main = () => {
	console.println("TYP2DOCX: self exporting to .docx");
	if (typeof typ2DocxExport === "undefined") {
		app.alert({
			cMsg:
				"Typ2Docx function not found. " +
				"Make sure you've installed the trusted function!",
		});
		return;
	}
	try {
		typ2DocxExport.call(this, PORT);
	} finally {
		this.closeDoc();
	}
};

app.setTimeOut("main()", 1); // queue the function call
