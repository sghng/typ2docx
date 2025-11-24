#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
'a', 'b' | ForEach-Object {
    Remove-Item "$_.d" -Recurse -ErrorAction SilentlyContinue
    Copy-Item "$_.docx" "$_.zip" -Force
    Expand-Archive "$_.zip" "$_.d"
}
robocopy "a.d" "out.d" /mir | Out-Null
python -m saxon | Out-File "out.d/word/document.xml"
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
Push-Location "out.d"
Compress-Archive -Force "*" "../out.docx"
