---
name: resume-screening
description: 按 JD 和 HR 确认的筛选标准批量初筛实习简历，输出可排序、可追溯的 Excel 汇总表、单人卡片和深度报告。当需要从一批 PDF 简历中筛选实习生候选人时使用。
---

# 简历筛选（实习）

把"凭感觉筛简历"变成"按规则执行"。输入一份 JD + 一批 PDF 简历，输出排序后的候选人名单。

## 不适用

- 面试评估与录用决策（本 skill 只做简历初筛，输出的是**建议**）
- 社招（当前版本只针对实习场景）

## 前置条件

- JD 文本或截图
- 一个文件夹里的 PDF 简历

## 流程

### Step 1　收 JD，跑问卷（不可跳过）

拿到 JD 后**不要直接开始筛简历**。先读 [references/intake-questionnaire.md](references/intake-questionnaire.md)，把问卷呈现给 HR 确认。

- 从 JD 自动填充 Q1、Q2、Q3、Q8 以及 Q12 的候选清单
- 其余题目给出默认推荐值，让 HR 点选或修改
- 允许"不确定 / 跳过"，**跳过的项不进门槛**

HR 答复后生成**岗位画像卡**，存为 `outputs/<岗位名>-画像卡.md`，同岗位后续批次直接复用。

画像卡上每条门槛都要标注来源：`JD原文` / `HR确认` / `默认推断`。这是复核时判断"这条规则该不该存在"的依据。

### Step 2　批量提取简历文本

运行 `scripts/extract_pdf_text.ps1`，把 PDF 批量转成 UTF-8 文本。

```powershell
powershell -File scripts/extract_pdf_text.ps1 -InputDir "<简历文件夹>" -OutputDir "<输出文件夹>"
```

转换后**检查每份文本是否为空**。文本为空的说明是扫描件/图片型 PDF，本机没有 OCR 工具，需要单独标注为"需人工查看"，不要凭文件名猜内容。

### Step 3　结构化提取

按 [references/scoring-rubric.md](references/scoring-rubric.md) 中的字段定义，把每份简历抽成结构化档案。

**只抄事实，不做判断。** 抓不到就写"简历未体现"，不要推断。

### Step 4　门槛判断

对照画像卡的 **门槛 + 雷区**，逐条核对，给出三个结果之一：

- **通过**：所有门槛项都满足，且未命中雷区
- **待定**：门槛项在简历中缺少判断依据（例如没写学历、没写毕业年份）
- **淘汰**：明确违反门槛，或命中雷区

**核心原则：门槛只能建立在"结构性内容"上**

简历里的信息分两种：

| 类型 | 内容 | 能否当门槛 |
|---|---|---|
| **结构性内容** | 教育背景、实习/项目经历、起止时间、证书 | **可以**。"不写"这个判断可靠——不写等于没内容 |
| **可选内容** | 技能栏、自我评价、期望地点、到岗时间 | **不可以**。写不写看个人习惯，"没写"说明不了任何问题 |

**门槛只放三类内容**

1. **资质**：学历、在读状态、毕业年份、专业
2. **证书**：JD 明确要求、且有客观判定标准（考试通过 / 发证机构认证）的
3. **经历**：JD 原文出现"必须 / 要求 / 需具备"措辞的

**明确不能当门槛的**

- **所有技能**（Excel 熟练、Python 精通……）：技能是"水平"，简历里写了不代表会（越会包装越爱写"精通"），没写也不代表不会。只在打分时加分 + 列入面试验证，**没写不扣分**。
- **到岗时间、可实习时长、每周到岗天数、期望城市、薪资期望**：招聘平台字段，求职者在平台填过一次就够了，简历里没有是正常的，不扣分、不淘汰、也不判"待定"。写入画像卡的"平台筛选条件"区块，由 HR 在平台侧筛或面试确认。
- **JD 写"优先 / 为佳"的经历**：进加分项，不淘汰任何人。

> **为什么门槛要设得这么窄**：门槛设错的代价是漏人，而且是**不可见的漏**——你永远不会知道被淘汰的那批人里有没有好的。降成加分项之后，人还留在表里，只是排在后面，你还看得见、能回头捞。
>
> 这两条规则都是真实试跑后修正的：早期版本把可实习时长当门槛，结果一份各项条件都不错的简历被卡在"待定"；中期版本把技能当门槛，同样会误伤不擅长写简历的人。

### Step 5　打分

**通过和待定的候选人都要打分**，只有"淘汰"不打分。按 5 个维度共 100 分，依据和分档锚点见 [references/scoring-rubric.md](references/scoring-rubric.md)。

待定的候选人，分数前面标注**"条件性得分"**，并在报告里写清楚是哪一项缺依据、需要确认什么。这样 HR 看到的不是一个没有信息量的"待定"两个字，而是一个分数加一个明确的待办问题。

软性素质**不占分**，只做两件事：用行为代理指标打标签（强证据 / 间接证据 / 未体现），并为每项生成一个面试验证问题。

每个维度的得分都要附**简历原文依据**。无证据的维度记 0 分并标注"简历未体现"。

**措辞纪律**：遇到"简历里没写"，只描述事实，不下能力结论。写"简历中未提及 Excel 的具体使用场景，建议面试确认"，不写"不具备 Excel 能力"。

### Step 6　输出

按 [references/output-format.md](references/output-format.md) 生成，优先级：

1. **Excel 汇总表**（CSV，UTF-8 BOM）
2. **单人图片卡片**（写 JSON → 跑 `scripts/render_card.ps1` → PNG）
3. **单份深度报告**（Markdown）

### Step 7　校准（每 1-2 批做一次）

把 HR 的最终决定（约面 / 淘汰）与 skill 的判断对比：

- 判断一致 → 不动
- HR 推翻了 skill 的判断 → 找到对应的权重或锚点，在画像卡上调整
- 同一维度连续出错 → 调整该维度的权重

修改记录追加到画像卡末尾的"校准日志"。

## 硬约束

1. **可追溯**：每条结论都要有简历原文支撑，标注原文出处。抓不到证据的写"简历未体现"。
2. **不脑补**：不替候选人补充经历，不根据学校名气、姓名、籍贯做任何推断。
3. **合规**：性别、年龄、婚育状况、籍贯、民族、照片**不参与评分，也不出现在排序逻辑中**。
4. **可复现**：同一份简历 + 同一份画像卡，两次运行结果应基本一致。打分必须对照锚点表，不凭印象给分。
5. **AI 只出建议**：输出中必须保留"AI 辅助建议，最终录用判断以面试为准"的声明。

## References

- **问卷与画像卡**：[references/intake-questionnaire.md](references/intake-questionnaire.md) — Step 1 使用
- **评分规则与字段定义**：[references/scoring-rubric.md](references/scoring-rubric.md) — Step 3、5 使用
- **输出格式规范**：[references/output-format.md](references/output-format.md) — Step 6 使用

## 本机环境约束

这台机器上没有 Python、Node、OCR 工具，实现时不要依赖它们。

| 能力 | 可用工具 |
|---|---|
| PDF → 文本 | `pdftotext`（需在 PATH 中，或安装 MiKTeX / Poppler） |
| PDF → 图片 / 卡片转 PNG | `pdftoppm`（同上） |
| 中文卡片渲染 | `xelatex` + `ctex` 宏包 |
| Excel 汇总表 | 输出 CSV（UTF-8 BOM），Excel 可直接打开 |
| 编程环境 | PowerShell + .NET（`dotnet`） |

Excel / Word COM 接口在受限环境下可能调不起来，不要把它作为必要依赖。

## 已知的坑

**1. `.ps1` 脚本必须保存为「UTF-8 带 BOM」**
Windows PowerShell 5.1 默认按 GBK 解析脚本文件。不带 BOM 的 UTF-8 脚本里只要有中文，就会全部乱码并报语法错误。
用 `apply_patch` 新建脚本后，需要重新存一次：

```powershell
$p = '<脚本路径>'
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))
```

**2. `pdftotext` 需要沙箱外权限**
它是 MiKTeX 的封装程序，启动时会写注册表和用户配置目录。在受限沙箱里会报"拒绝访问"或"fresh TeX installation"。
调用它的命令需要以非沙箱方式执行。

**3. CSV 要带 BOM**
输出 CSV 时必须用 `UTF8Encoding($true)`，否则 Excel 打开是乱码。

**4. 不要用逗号分隔的命令行参数传数组**
`powershell -File script.ps1 -Dims a,b,c` 里的 `a,b,c` 会被当成**一个字符串**，不是三元素数组。
需要传多条中文数据时，改用 JSON 数据文件（`render_card.ps1` 就是这么做的）。

**5. PowerShell 不展开 `-参数=$变量` 这种裸参数**
`& $exe -output-directory=$someVar` 会把 `$someVar` **原样**传给程序。先把参数拼成变量再传，或改用 `Push-Location` 让程序在当前目录写产物。

**6. LaTeX 里给 `\rule` 上色要用 `\textcolor`，不能用 `\colorbox`**
`\colorbox` 设置的是背景色，里面的 `\rule` 仍按当前文字色（默认黑）绘制，会盖掉背景。
正确写法：`\textcolor{brand}{\rule{30mm}{3.4mm}}`。

**7. LaTeX 里的圆点、方块等符号要用 `\xeCJKDeclareCharClass` 交给中文字体**
否则 xelatex 会用拉丁字体渲染 ●、○、■ 等字符，日志报 `Missing character`，图上直接空白。

```latex
\xeCJKDeclareCharClass{CJK}{"25CF, "25CB, "25A0, "25A1, "2605, "2606}
```
