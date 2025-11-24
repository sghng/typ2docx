#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
'a', 'b' | ForEach-Object {
    Remove-Item "$_.d" -Recurse -ErrorAction SilentlyContinue
    Copy-Item "$_.docx" "$_.zip"
    Expand-Archive "$_.zip" "$_.d"
}
robocopy a.d out.d /mir > $null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
python -m saxon > "out.d/word/document.xml"
if ($LASTEXITCODE -ne 0) { throw "python/saxon failed with exit code $LASTEXITCODE" }
Push-Location out.d
try { Compress-Archive * ../out.zip -Force } finally { Pop-Location }
Move-Item out.zip out.docx -Force
