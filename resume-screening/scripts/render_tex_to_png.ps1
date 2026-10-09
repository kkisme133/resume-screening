<#
通用工具：把一个 .tex 文件编译成 PNG。

渲染链路：xelatex → PDF → pdftoppm → PNG
卡片有专门的 render_card.ps1（读 JSON），这个脚本用于流程图、说明图之类的静态图。

用法：
  powershell -ExecutionPolicy Bypass -File scripts\render_tex_to_png.ps1 `
    -TexFile assets\flow-diagram.tex -OutPng outputs\流程图.png

依赖本机已有的 xelatex（含 ctex 宏包）和 pdftoppm（MiKTeX 自带），且需要沙箱外权限。
#>

param(
    [Parameter(Mandatory = $true)][string]$TexFile,
    [Parameter(Mandatory = $true)][string]$OutPng,
    [int]$Dpi = 150,
    [string]$XelatexPath = '',
    [string]$PdftoppmPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-Tool {
    param([string]$Given, [string]$ToolName)
    if (-not [string]::IsNullOrWhiteSpace($Given) -and (Test-Path -LiteralPath $Given)) { return $Given }
    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "找不到 $ToolName。请先安装 MiKTeX 或 TeX Live，或用参数显式指定完整路径。"
}

$XelatexPath  = Resolve-Tool -Given $XelatexPath  -ToolName 'xelatex'
$PdftoppmPath = Resolve-Tool -Given $PdftoppmPath -ToolName 'pdftoppm'

if (-not (Test-Path -LiteralPath $TexFile)) { throw "找不到 tex 文件：$TexFile" }
$TexFile = (Resolve-Path -LiteralPath $TexFile).Path
$texDir  = Split-Path $TexFile -Parent
$texLeaf = Split-Path $TexFile -Leaf
$base    = [System.IO.Path]::GetFileNameWithoutExtension($TexLeaf)

# 产物统一放在 tex 同目录下的 _build，不污染 assets
$buildDir = Join-Path $texDir '_build'
if (-not (Test-Path -LiteralPath $buildDir)) { New-Item -ItemType Directory -Path $buildDir -Force | Out-Null }

Push-Location $buildDir
try {
    # 注意：PowerShell 不展开 "-output-directory=$var" 这种裸参数，靠 Push-Location 控制产物位置。
    & $XelatexPath -interaction=nonstopmode -halt-on-error $TexFile | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $logPath = Join-Path $buildDir "$base.log"
        $tail = if (Test-Path -LiteralPath $logPath) {
            (Get-Content -LiteralPath $logPath -Encoding UTF8 | Select-Object -Last 25) -join "`n"
        } else { '（没有生成 log 文件）' }
        throw "xelatex 编译失败（退出码 $LASTEXITCODE）。日志末尾：`n$tail"
    }
}
finally {
    Pop-Location
}

$pdfPath = Join-Path $buildDir "$base.pdf"
if (-not (Test-Path -LiteralPath $pdfPath)) { throw "没有生成 PDF：$pdfPath" }

$outDir = Split-Path $OutPng -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$tmpPrefix = Join-Path $buildDir "$base-png"
Get-ChildItem -LiteralPath $buildDir -Filter "$base-png*.png" -ErrorAction SilentlyContinue | Remove-Item -Force
& $PdftoppmPath -png -r $Dpi $pdfPath $tmpPrefix 2>$null
if ($LASTEXITCODE -ne 0) { throw "pdftoppm 转换失败（退出码 $LASTEXITCODE）" }

$produced = @(Get-ChildItem -LiteralPath $buildDir -Filter "$base-png*.png" | Sort-Object Name)
if ($produced.Count -eq 0) { throw "没有生成 PNG" }

if ($produced.Count -gt 1) {
    Write-Warning "PDF 有 $($produced.Count) 页，只取第一页。多页请分别拆分。"
}

Move-Item -LiteralPath $produced[0].FullName -Destination $OutPng -Force

$size = '（无法读取尺寸）'
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $img = [System.Drawing.Image]::FromFile($OutPng)
    $size = "$($img.Width)x$($img.Height)"
    $img.Dispose()
}
catch { }

[pscustomobject]@{
    图片文件 = $OutPng
    尺寸     = $size
    PDF      = $pdfPath
} | Format-List
