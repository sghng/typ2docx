#!/usr/bin/env python3
"""
PDF JavaScript Injector - Simplified

Injects JavaScript into PDF that calls the folder-level ExportToWord() trusted function.

Usage:
    python pdf_js_injector.py input.pdf [output.pdf]
"""

import sys
from pathlib import Path
from typing import Optional

try:
    from pypdf import PdfReader, PdfWriter
except ImportError:
    print("Error: pypdf is not installed. Install it with: pip install pypdf")
    sys.exit(1)


def inject_export_call(
    input_pdf: Path,
    output_pdf: Optional[Path] = None,
) -> None:
    """
    Inject JavaScript that calls ExportToWord() folder-level trusted function.

    Args:
        input_pdf: Path to the input PDF file
        output_pdf: Path to save the modified PDF
    """
    if output_pdf is None:
        output_pdf = input_pdf.parent / f"{input_pdf.stem}_auto_export.pdf"

    reader = PdfReader(input_pdf)
    writer = PdfWriter()

    # Copy all pages
    for page in reader.pages:
        writer.add_page(page)

    # Copy metadata if present
    if reader.metadata:
        writer.add_metadata(reader.metadata)

    # JavaScript that calls the trusted function with a delay
    # The delay ensures the document is fully loaded before attempting export
    javascript = """
    // Add a delay to ensure document is fully loaded and not locked
    app.setTimeOut("delayedExport()", 1000);

    function delayedExport() {
        try {
            if (typeof ExportToWord === "function") {
                ExportToWord.call(this);
            } else {
                app.alert({
                    cMsg: "ExportToWord function not found.\\n\\n" +
                          "Install ExportToWord.js to:\\n" +
                          "  macOS: ~/Library/Application Support/Adobe/Acrobat/DC/JavaScripts/\\n" +
                          "  Windows: %APPDATA%\\\\Adobe\\\\Acrobat\\\\DC\\\\JavaScripts\\\\\\n\\n" +
                          "Then restart Acrobat.",
                    cTitle: "Trusted Function Not Found",
                    nIcon: 1
                });
            }
        } catch (e) {
            app.alert({
                cMsg: "Error calling ExportToWord:\\n\\n" + e.toString(),
                cTitle: "Error",
                nIcon: 0
            });
        }
    }
    """

    # Add JavaScript that runs on document open
    writer.add_js(javascript)

    # Write the modified PDF
    with open(output_pdf, "wb") as output_file:
        writer.write(output_file)

    print(f"✓ JavaScript injected successfully")
    print(f"  Input:  {input_pdf}")
    print(f"  Output: {output_pdf}")


def main():
    """Command-line interface."""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python pdf_js_injector.py <input.pdf> [output.pdf]")
        print()
        print("Example:")
        print("  python pdf_js_injector.py document.pdf")
        print()
        print("Requires:")
        print("  ExportToWord.js installed in Acrobat's JavaScripts folder")
        print("  macOS: ~/Library/Application Support/Adobe/Acrobat/DC/JavaScripts/")
        print("  Windows: %APPDATA%\\Adobe\\Acrobat\\DC\\JavaScripts\\")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None

    if not input_path.exists():
        print(f"Error: Input file does not exist: {input_path}")
        sys.exit(1)

    inject_export_call(input_path, output_path)
    print()
    print("Open the PDF in Acrobat to trigger automatic export to Word.")


if __name__ == "__main__":
    main()
