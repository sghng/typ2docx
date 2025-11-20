from pathlib import Path

from saxonche import PySaxonProcessor

print(
    (proc := PySaxonProcessor())
    .new_xslt30_processor()
    .compile_stylesheet(
        stylesheet_text=Path(__file__).with_name("merge.xslt").read_text()
    )
    .transform_to_string(xdm_node=proc.parse_xml(xml_text="<root/>"))
)
