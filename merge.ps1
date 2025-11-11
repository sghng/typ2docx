Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

Remove-Item a.d,b.d,out.d -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item out.docx -Force -ErrorAction SilentlyContinue

Expand-Archive -Path a.docx -DestinationPath a.d -Force
Expand-Archive -Path b.docx -DestinationPath b.d -Force

New-Item out.d -ItemType Directory -Force | Out-Null
Copy-Item a.d\* out.d -Recurse -Force

& saxon "-xsl:merge.xslt" "-it:main" "-o:out.d\word\document.xml"

Remove-Item out.docx -Force -ErrorAction SilentlyContinue
Compress-Archive -Path out.d\* -DestinationPath out.docx -Force
