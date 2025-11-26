#!/usr/bin/env python3
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter

input_pdf = Path(sys.argv[1])
script_dir = Path(__file__).parent
template = (script_dir / "export.js").read_text()

docx_filename = input_pdf.stem + ".docx"
output_path = f"/Macintosh HD/Users/sghuang/Library/Containers/com.adobe.Acrobat.Pro/Data/tmp/{docx_filename}"

# javascript = template.replace('"TEMPLATE_OUTPUT_PATH"', f'"{output_path}"')

reader = PdfReader(input_pdf)
writer = PdfWriter()

for page in reader.pages:
    writer.add_page(page)

if reader.metadata:
    writer.add_metadata(reader.metadata)

writer.add_js(template)

with open("injected.pdf", "wb") as f:
    writer.write(f)

print(f"Created injected.pdf - DOCX will be at: {output_path}")
