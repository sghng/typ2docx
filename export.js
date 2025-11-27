// biome-ignore lint/correctness/noUnusedVariables: invoked with setTimeOut
const main = () => {
	console.println("TYP2DOCX: self exporting to .docx");
	if (typeof typ2Docx === "undefined") {
		app.alert({
			cMsg:
				"Typ2Docx function not found. " +
				"Make sure you've installed the trusted function!",
		});
		return;
	}
	// try {
	typ2Docx.call(this, PORT);
	// } catch (e) {
	// 	// TODO: send these back to CLI
	// 	console.println("Error exporting to .docx:", e);
	// }
	this.closeDoc();
};

app.setTimeOut("main()", 1); // queue the function call
