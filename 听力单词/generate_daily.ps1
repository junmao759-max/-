<#
.SYNOPSIS
  生成考研英语听力单词每日 md 文件（默认每天 40 词，全库去重，不重复生成）。

.DESCRIPTION
  从 bank_part*.tsv 词库中随机挑选未使用过的单词，生成当天日期的：
    - YYYY-MM-DD-考研听力单词.md   （音标/释义/例句/译文/听写清单）
    - YYYY-MM-DD-听写单词.txt      （纯单词列表，一行一个，便于导入听写工具）
  并维护 used_log.csv（已用词表）与 index.md（总索引）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\generate_daily.ps1
  powershell -ExecutionPolicy Bypass -File .\generate_daily.ps1 -Date 2026-09-02
  powershell -ExecutionPolicy Bypass -File .\generate_daily.ps1 -Count 40
#>
param(
  [string]$Date  = (Get-Date -Format 'yyyy-MM-dd'),
  [int]$Count    = 40
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$outMd   = Join-Path $root "$Date-考研听力单词.md"
$outTxt  = Join-Path $root "$Date-听写单词.txt"
$usedFile  = Join-Path $root 'used_log.csv'
$indexFile = Join-Path $root 'index.md'

if (Test-Path $outMd) {
  Write-Host "今日文件已存在：$outMd （已生成过，跳过，避免重复）"
  exit 0
}

# ---------- 1. 读取已用词表 ----------
$usedWords = @{}
if (Test-Path $usedFile) {
  Get-Content $usedFile -Encoding UTF8 | Select-Object -Skip 1 | ForEach-Object {
    $w = (($_ -split ',')[0]).TrimStart([char]0xFEFF).Trim()
    if ($w) { $usedWords[$w] = $true }
  }
}

# ---------- 2. 读取词库（bank_part*.tsv） ----------
$bankFiles = Get-ChildItem -Path $root -Filter 'bank_part*.tsv' -File
if (-not $bankFiles) { throw '未找到词库文件 bank_part*.tsv，请先创建词库。' }

$rows = @()
foreach ($f in $bankFiles) {
  Get-Content $f.FullName -Encoding UTF8 | ForEach-Object { $_.TrimStart([char]0xFEFF) } | Where-Object { $_ -match '\S' } | ForEach-Object {
    $c = $_ -split '\|'
    if ($c.Count -ge 7) {
      $rows += [pscustomobject]@{
        word        = $c[0].Trim()
        phonetic    = $c[1].Trim()
        pos         = $c[2].Trim()
        meaning     = $c[3].Trim()
        example     = $c[4].Trim()
        translation = $c[5].Trim()
        topic       = $c[6].Trim()
      }
    }
  }
}

$avail = @(); $seenAvail = @{}; foreach ($r in @($rows | Where-Object { -not $usedWords.ContainsKey($_.word) })) { $k = $r.word.ToLower(); if (-not $seenAvail.ContainsKey($k)) { $seenAvail[$k] = $true; $avail += $r } }
if ($avail.Count -lt $Count) {
  Write-Warning "词库剩余 $($avail.Count) 词，不足 $Count 个。请新增 bank_part*.tsv 扩充词库（格式见 README）。"
}
$take   = [Math]::Min($Count, $avail.Count)
$picked = @($avail | Get-Random -Count $take)

# ---------- 3. 计算天数 ----------
$existing = @(Get-ChildItem -Path $root -Filter '*-考研听力单词.md' -File |
  Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}' })
$day = $existing.Count + 1

# ---------- 4. 生成 md ----------
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# 考研英语听力单词 · 第 $day 天 · $Date")
$md.Add('')
$md.Add("> 今日 $take 词 ｜ 已累计 $($existing.Count) 天 ｜ 词库剩余 $($avail.Count) 词")
$md.Add('')
$md.Add('## 📋 单词速览')
$md.Add('')
$md.Add('| # | 单词 | 音标 | 词性 | 释义 | 主题 |')
$md.Add('|---|------|------|------|------|------|')
for ($i = 0; $i -lt $picked.Count; $i++) {
  $w = $picked[$i]
  $md.Add("| $($i+1) | $($w.word) | /$($w.phonetic)/ | $($w.pos) | $($w.meaning) | $($w.topic) |")
}
$md.Add('')
$md.Add('## 📖 详细学习')
$md.Add('')
for ($i = 0; $i -lt $picked.Count; $i++) {
  $w = $picked[$i]
  $md.Add("### $($i+1). $($w.word)")
  $md.Add("- **音标**：/$($w.phonetic)/")
  $md.Add("- **词性**：$($w.pos)")
  $md.Add("- **释义**：$($w.meaning)")
  $md.Add("- **例句**：$($w.example)")
  $md.Add("- **译文**：$($w.translation)")
  $md.Add("- **主题**：$($w.topic)")
  $md.Add('')
}
$md.Add('## 🎧 听写清单（复制导入听写工具）')
$md.Add('')
$md.Add('```text')
foreach ($w in $picked) { $md.Add($w.word) }
$md.Add('```')
$md.Add('')
$md.Add('## ✂️ 全部单词（空格分隔 · 一键复制）')
$md.Add('')
$md.Add('```text')
$md.Add(($picked | ForEach-Object { $_.word }) -join ' ')
$md.Add('```')
$md.Add('')
$md.Add('---')
$md.Add('*由 generate_daily.ps1 自动生成 · 已用词自动去重，不会重复*')
$md | Set-Content -Path $outMd -Encoding UTF8

# ---------- 5. 生成 txt 听写清单 ----------
$picked | ForEach-Object { $_.word } | Set-Content -Path $outTxt -Encoding UTF8

# ---------- 6. 更新已用词表 ----------
if (-not (Test-Path $usedFile)) { 'word,date' | Set-Content $usedFile -Encoding UTF8 }
$picked | ForEach-Object { "$($_.word),$Date" } | Add-Content $usedFile -Encoding UTF8

# ---------- 7. 更新总索引 ----------
$idx = New-Object System.Collections.Generic.List[string]
$idx.Add('# 📚 考研英语听力单词 · 总索引')
$idx.Add('')
$idx.Add('| 日期 | 词数 | 学习文件 | 听写清单 |')
$idx.Add('|---|:---:|---|---|')
foreach ($f in (Get-ChildItem -Path $root -Filter '*-考研听力单词.md' -File | Sort-Object Name)) {
  $datePart = (($f.BaseName) -split '-')[0..2] -join '-'
  $txtPath  = Join-Path $root ($datePart + '-听写单词.txt')
  $n = if (Test-Path $txtPath) { (Get-Content $txtPath).Count } else { '?' }
  $idx.Add("| $datePart | $n | [$($f.BaseName)]($($f.Name)) | [听写清单]($datePart-听写单词.txt) |")
}
$idx | Set-Content -Path $indexFile -Encoding UTF8

Write-Host "✅ 已生成：$outMd （$take 词，第 $day 天）"
Write-Host "✅ 听写清单：$outTxt"
