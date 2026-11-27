# Builds docs/M2_Jefferson.pdf from m2_report.html + the Verilog source files.
$docs = $PSScriptRoot
$root = Split-Path $docs -Parent

function ConvertTo-CodeBlock($title, $path) {
    $text = [System.IO.File]::ReadAllText($path)
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    return "<div class=`"code`"><h3>$title</h3><pre>$text</pre></div>"
}

$code  = "<h2 style=`"page-break-before: always;`">4. Code</h2>`n"
$code += ConvertTo-CodeBlock 'logic_analyzer.v' (Join-Path $root 'logic_analyzer.v')
$code += "`n" + (ConvertTo-CodeBlock 'vga_display.v' (Join-Path $root 'vga_display.v'))
$code += "`n" + (ConvertTo-CodeBlock 'sim/tb_vga.v' (Join-Path $root 'sim\tb_vga.v'))

$html = [System.IO.File]::ReadAllText((Join-Path $docs 'm2_report.html')).Replace('<!--CODE-->', $code)
$built = Join-Path $docs 'm2_report_built.html'
[System.IO.File]::WriteAllText($built, $html, (New-Object System.Text.UTF8Encoding $false))

$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $edge)) { $edge = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
$pdf = Join-Path $docs 'M2_Jefferson.pdf'
& $edge --headless=new --disable-gpu --no-pdf-header-footer "--print-to-pdf=$pdf" ("file:///" + ($built -replace '\\', '/')) | Out-Null
Start-Sleep -Seconds 3
Remove-Item $built
Get-Item $pdf | Select-Object Name, Length, LastWriteTime
