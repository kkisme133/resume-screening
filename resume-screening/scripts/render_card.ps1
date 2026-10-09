<#
把一位候选人的筛选结果渲染成 PNG 卡片。

渲染链路：LaTeX（ctex / xelatex）→ PDF → pdftoppm → PNG
不要用 AI 生图工具——中文会画错、数字对不上。

输入是一份 JSON 数据文件（UTF-8）。用 JSON 而不是命令行参数，是因为中文长句、
标点和逗号走命令行很容易被拆分或转义出错。

JSON 结构（键名固定，数组顺序即卡片上的顺序）：
{
  "岗位": "某公司 HR 招聘实习生",
  "批次": "2026-10-01",
  "姓名": "张三",
  "副标题": "西南财经大学 · 财政学 · 大四",
  "总分": 79,
  "评级": "基本匹配",
  "门槛结果": "通过（符合 L1：本科及以上在读）",
  "建议": "约面",
  "优势": ["...", "...", "..."],
  "风险": ["...", "..."],
  "维度": [
    { "名称": "硬技能",   "得分": 17, "满分": 25 },
    { "名称": "相关经历", "得分": 16, "满分": 25 }
  ],
  "软性观察": ["进取心 ●●●", "抗压 ●●●"],
  "待验证项": ["Excel 熟练度", "PPT 汇报经验"]
}

用法：
  & scripts\render_card.ps1 -DataFile outputs\cards\张三.json -OutDir outputs

依赖本机已有的 xelatex（含 ctex 宏包）和 pdftoppm（MiKTeX 自带）。
两者都需要在沙箱外执行。
#>

param(
    [Parameter(Mandatory = $true)][string]$DataFile,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$FileBase = '',
    [int]$Dpi = 150,
    [double]$BarTotalMm = 116.0,
    [string]$XelatexPath = '',
    [string]$PdftoppmPath = ''
)

$ErrorActionPreference = 'Stop'

function ConvertTo-LatexText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text
    $t = $t -replace '\\', '\textbackslash{}'
    $t = $t -replace '([&%$#_{}])', '\$1'
    $t = $t -replace '~', '\textasciitilde{}'
    $t = $t -replace '\^', '\textasciicircum{}'
    return $t
}

function Get-Field {
    param($Obj, [string]$Key, $Default = '')
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Resolve-Tool {
    param([string]$Given, [string]$ToolName)
    if (-not [string]::IsNullOrWhiteSpace($Given) -and (Test-Path -LiteralPath $Given)) { return $Given }
    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "找不到 $ToolName。请先安装 MiKTeX 或 TeX Live，或用参数显式指定完整路径。"
}

$XelatexPath  = Resolve-Tool -Given $XelatexPath  -ToolName 'xelatex'
$PdftoppmPath = Resolve-Tool -Given $PdftoppmPath -ToolName 'pdftoppm'

if (-not (Test-Path -LiteralPath $DataFile)) { throw "数据文件不存在：$DataFile" }
$json = [System.IO.File]::ReadAllText($DataFile, [System.Text.Encoding]::UTF8)
$d = $json | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
$cardDir = Join-Path $OutDir 'cards'
$srcDir  = Join-Path $cardDir '_src'
if (-not (Test-Path -LiteralPath $cardDir)) { New-Item -ItemType Directory -Path $cardDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $srcDir))  { New-Item -ItemType Directory -Path $srcDir  -Force | Out-Null }

$Name   = [string](Get-Field $d '姓名')
$Rating = [string](Get-Field $d '评级')
$Score  = [int](Get-Field $d '总分' 0)

if ([string]::IsNullOrWhiteSpace($FileBase)) {
    $FileBase = if ([string]::IsNullOrWhiteSpace($Name)) { 'card' } else { $Name }
}

# 评级决定主色
$scoreColor = switch -Wildcard ($Rating) {
    '*高度匹配*' { 'okgreen' }
    '*基本匹配*' { 'brand' }
    '*勉强匹配*' { 'warnorange' }
    '*不匹配*'   { 'badred' }
    default      { 'brand' }
}

# ---- 优势 / 风险 ----
function Format-ItemBlock {
    param($Items, [string]$Color)
    $out = @()
    $i = 1
    foreach ($s in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $out += "{\color{$Color}\bfseries $i}　$(ConvertTo-LatexText ([string]$s))\par\vspace{2.4mm}"
        $i++
    }
    return ($out -join "`n")
}
$strengthsBlock = Format-ItemBlock -Items (Get-Field $d '优势' @()) -Color 'brand'
$risksBlock     = Format-ItemBlock -Items (Get-Field $d '风险' @()) -Color 'badred'

# ---- 维度条形图（数学在 PowerShell 里算好，避免 LaTeX 除法）----
$barRows = @()
foreach ($dim in @(Get-Field $d '维度' @())) {
    $label = ConvertTo-LatexText ([string](Get-Field $dim '名称'))
    $got   = [double](Get-Field $dim '得分' 0)
    $max   = [double](Get-Field $dim '满分' 0)
    if ($max -le 0) { continue }
    $ratio = $got / $max
    if ($ratio -lt 0) { $ratio = 0 }
    if ($ratio -gt 1) { $ratio = 1 }
    $filled = [math]::Round($BarTotalMm * $ratio, 1)
    $rest   = [math]::Round($BarTotalMm - $filled, 1)
    $barColor = if ($ratio -ge 0.85) { 'okgreen' } elseif ($ratio -ge 0.6) { 'brand' } elseif ($ratio -ge 0.45) { 'warnorange' } else { 'badred' }
    # 用 \textcolor 给 \rule 上色；若用 \colorbox 包 \rule，rule 会按当前文字色（黑）绘制，盖掉背景色。
    $barRows += "$label & {\setlength{\fboxsep}{0pt}\textcolor{$barColor}{\rule{${filled}mm}{3.4mm}}\textcolor{bandlight}{\rule{${rest}mm}{3.4mm}}} & \textbf{$got / $max} \\[1.8mm]"
}
$barsBlock = ($barRows -join "`n")

# ---- 软性观察 / 待验证 ----
$softLine    = ((@(Get-Field $d '软性观察' @()) | Where-Object { $_ }) | ForEach-Object { ConvertTo-LatexText ([string]$_) }) -join '　　'
$pendingLine = ((@(Get-Field $d '待验证项' @()) | Where-Object { $_ }) | ForEach-Object { ConvertTo-LatexText ([string]$_) }) -join '、'

$softParts = @()
if ($softLine) {
    $softParts += "{\color{brand}\bfseries 软性观察}{\color{muted}（来自简历行为证据，非自评）}\par\vspace{1.8mm}"
    $softParts += "$softLine"
}
if ($pendingLine) {
    $softParts += "\par\vspace{4mm}"
    $softParts += "{\color{brand}\bfseries 待验证项}\par\vspace{1.8mm}"
    $softParts += "$pendingLine"
}
$softBlock = ($softParts -join "`n")

$template = @'
\documentclass[fontset=windows,11pt]{ctexart}
\usepackage[a4paper,top=13mm,bottom=11mm,left=12mm,right=12mm]{geometry}
\usepackage{xcolor}
\usepackage{array}
\usepackage{colortbl}
\usepackage{tabularx}
\definecolor{brand}{HTML}{1F4E79}
\definecolor{bandlight}{HTML}{E7EEF6}
\definecolor{okgreen}{HTML}{2E7D32}
\definecolor{warnorange}{HTML}{E65100}
\definecolor{badred}{HTML}{C62828}
\definecolor{muted}{HTML}{6B7785}
\definecolor{linegrey}{HTML}{D6DEE7}
% 把实心/空心圆等符号交给中文字体，否则 xelatex 会用拉丁字体渲染而缺字形
\xeCJKDeclareCharClass{CJK}{"25CF, "25CB, "25A0, "25A1, "2605, "2606, "25AA, "25AB}
\pagestyle{empty}
\setlength{\parindent}{0pt}
\linespread{1.15}
\begin{document}

\colorbox{brand}{\parbox{\dimexpr\textwidth-2\fboxsep\relax}{\color{white}\bfseries 岗位：@@JOB@@ \hfill 批次：@@BATCH@@}}

\vspace{5mm}
{\fontsize{26}{30}\selectfont\bfseries @@NAME@@}\\[1.5mm]
{\color{muted} @@SUBTITLE@@}

\vspace{5mm}
\noindent
\begin{minipage}[c]{46mm}
\centering
{\setlength{\fboxsep}{3mm}\colorbox{@@SCORECOLOR@@}{\parbox[c][24mm][c]{36mm}{\centering{\color{white}\fontsize{32}{34}\selectfont\bfseries @@SCORE@@}\\[0.5mm]{\color{white}\small / 100}}}}
\end{minipage}\hfill
\begin{minipage}[c]{\dimexpr\textwidth-50mm\relax}
{\large 评级：\textbf{\textcolor{@@SCORECOLOR@@}{@@RATING@@}}}\\[3mm]
门槛结果：@@GATE@@\\[3mm]
建议：@@ADVICE@@
\end{minipage}

\vspace{5mm}
\noindent\textcolor{linegrey}{\rule{\textwidth}{0.6pt}}
\vspace{4mm}

\noindent
\begin{minipage}[t]{0.485\textwidth}
{\color{brand}\bfseries 优势}\par\vspace{2.8mm}
@@STRENGTHS@@
\end{minipage}\hfill
\begin{minipage}[t]{0.485\textwidth}
{\color{badred}\bfseries 风险 / 待确认}\par\vspace{2.8mm}
@@RISKS@@
\end{minipage}

\vspace{5mm}
\noindent\textcolor{linegrey}{\rule{\textwidth}{0.6pt}}
\vspace{4mm}

{\color{brand}\bfseries 维度得分}\par\vspace{3.5mm}
\noindent
\begin{tabular}{@{}p{24mm}@{}p{118mm}@{}r@{}}
@@BARS@@
\end{tabular}

\vspace{5mm}
\noindent\textcolor{linegrey}{\rule{\textwidth}{0.6pt}}
\vspace{4mm}

@@SOFT@@

\vfill
{\color{muted}\small ※ AI 辅助建议，最终录用判断以面试为准。本卡片未使用性别、年龄、婚育、籍贯、民族、照片等与岗位无关的信息。}

\end{document}
'@

$tex = $template
$tex = $tex.Replace('@@JOB@@',        (ConvertTo-LatexText ([string](Get-Field $d '岗位'))))
$tex = $tex.Replace('@@BATCH@@',      (ConvertTo-LatexText ([string](Get-Field $d '批次'))))
$tex = $tex.Replace('@@NAME@@',       (ConvertTo-LatexText $Name))
$tex = $tex.Replace('@@SUBTITLE@@',   (ConvertTo-LatexText ([string](Get-Field $d '副标题'))))
$tex = $tex.Replace('@@SCORE@@',      "$Score")
$tex = $tex.Replace('@@SCORECOLOR@@', $scoreColor)
$tex = $tex.Replace('@@RATING@@',     (ConvertTo-LatexText $Rating))
$tex = $tex.Replace('@@GATE@@',       (ConvertTo-LatexText ([string](Get-Field $d '门槛结果'))))
$tex = $tex.Replace('@@ADVICE@@',     (ConvertTo-LatexText ([string](Get-Field $d '建议'))))
$tex = $tex.Replace('@@STRENGTHS@@',  $strengthsBlock)
$tex = $tex.Replace('@@RISKS@@',      $risksBlock)
$tex = $tex.Replace('@@BARS@@',       $barsBlock)
$tex = $tex.Replace('@@SOFT@@',       $softBlock)

$texPath = Join-Path $srcDir "$FileBase.tex"
[System.IO.File]::WriteAllText($texPath, $tex, (New-Object System.Text.UTF8Encoding($false)))

Push-Location $srcDir
try {
    # 注意：PowerShell 不会展开 "-output-directory=$var" 这种裸参数里的变量，
    # 会被原样传给 xelatex。这里靠 Push-Location 让产物落在当前目录，不传该参数。
    $logPath = Join-Path $srcDir "$FileBase.log"
    & $XelatexPath -interaction=nonstopmode -halt-on-error (Split-Path $texPath -Leaf) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $tail = if (Test-Path -LiteralPath $logPath) {
            (Get-Content -LiteralPath $logPath -Encoding UTF8 | Select-Object -Last 25) -join "`n"
        } else { '（没有生成 log 文件）' }
        throw "xelatex 编译失败（退出码 $LASTEXITCODE）。日志末尾：`n$tail"
    }
}
finally {
    Pop-Location
}

$pdfPath = Join-Path $srcDir "$FileBase.pdf"
if (-not (Test-Path -LiteralPath $pdfPath)) { throw "没有生成 PDF：$pdfPath" }

$pngPrefix = Join-Path $srcDir "$FileBase-out"
& $PdftoppmPath -png -r $Dpi $pdfPath $pngPrefix 2>$null
if ($LASTEXITCODE -ne 0) { throw "pdftoppm 转换失败（退出码 $LASTEXITCODE）" }

$produced = @(Get-ChildItem -LiteralPath $srcDir -Filter "$FileBase-out*.png" | Sort-Object Name)
if ($produced.Count -eq 0) { throw "没有生成 PNG" }

$finalPng = Join-Path $cardDir "$FileBase.png"
Move-Item -LiteralPath $produced[0].FullName -Destination $finalPng -Force
foreach ($extra in ($produced | Select-Object -Skip 1)) { Remove-Item -LiteralPath $extra.FullName -Force }

$size = '（无法读取尺寸）'
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $img = [System.Drawing.Image]::FromFile($finalPng)
    $size = "$($img.Width)x$($img.Height)"
    $img.Dispose()
}
catch { }

[pscustomobject]@{
    候选人   = $Name
    卡片文件 = $finalPng
    尺寸     = $size
    LaTeX源  = $texPath
} | Format-List
