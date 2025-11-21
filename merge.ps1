#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
Remove-Item "a.d", "b.d", "out.d" -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive "a.docx" -DestinationPath "a.d" -Force
Expand-Archive "b.docx" -DestinationPath "b.d" -Force
robocopy "a.d" "out.d" /MIR | Out-Null
python -m saxon | Out-File "out.d/word/document.xml"
Push-Location "out.d"
Compress-Archive "*" -DestinationPath "../out.docx" -Force
