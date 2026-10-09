<#
批量把简历 PDF 转成 UTF-8 文本，供后续结构化提取使用。

用法：
  powershell -File scripts/extract_pdf_text.ps1 -InputDir "D:\简历" -OutputDir "work\extracted"
  powershell -File scripts/extract_pdf_text.ps1 -InputDir "D:\简历" -OutputDir "work\extracted" -Recurse

依赖本机已有的 pdftotext（MiKTeX 自带）。
#>

param(
    [Parameter(Mandatory = $true)][string]$InputDir,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [switch]$Recurse,
    [string]$PdftotextPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputDir)) {
    throw "输入目录不存在：$InputDir"
}

if ([string]::IsNullOrWhiteSpace($PdftotextPath) -or -not (Test-Path -LiteralPath $PdftotextPath)) {
    $fallback = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($fallback) {
        $PdftotextPath = $fallback.Source
    }
    else {
        throw "找不到 pdftotext。请先安装 MiKTeX 或 Poppler，或用 -PdftotextPath 指定完整路径。"
    }
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$pdfs = Get-ChildItem -LiteralPath $InputDir -Filter '*.pdf' -File -Recurse:$Recurse
if ($pdfs.Count -eq 0) {
    Write-Warning "在 $InputDir 中没有找到 PDF 文件。"
    return
}

$results = @()

foreach ($pdf in $pdfs) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pdf.Name)
    $outFile  = Join-Path $OutputDir ($baseName + '.txt')

    # 同名的不同简历会互相覆盖，加序号避免。
    $i = 1
    while (Test-Path -LiteralPath $outFile) {
        $outFile = Join-Path $OutputDir ($baseName + "_$i.txt")
        $i++
    }

    & $PdftotextPath -layout -enc UTF-8 $pdf.FullName $outFile 2>$null

    $text  = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 } else { '' }
    $chars = if ($text) { ($text -replace '\s', '').Length } else { 0 }

    $results += [pscustomobject]@{
        简历文件 = $pdf.Name
        文本文件 = if (Test-Path -LiteralPath $outFile) { Split-Path $outFile -Leaf } else { '' }
        有效字符 = $chars
        状态     = if ($chars -ge 100) { 'OK' } elseif ($chars -gt 0) { '文本过少，需人工确认' } else { '空文本-可能是扫描件，需人工查看' }
    }
}

$results | Format-Table -AutoSize

$bad = $results | Where-Object { $_.状态 -ne 'OK' }
if ($bad) {
    Write-Warning ("有 {0} 份简历未能正常提取文本。本机没有 OCR 工具，这些文件需要人工查看，不要凭文件名推测内容。" -f $bad.Count)
}
