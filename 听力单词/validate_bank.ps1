<#
.SYNOPSIS
  校验并清洗词库 bank_part*.tsv：检查字段数、word 合法性、重复词，输出统计。
  默认只报告不动文件；加 -Fix 参数才会把清洗结果写回文件。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\validate_bank.ps1
  powershell -ExecutionPolicy Bypass -File .\validate_bank.ps1 -Fix
#>
param([switch]$Fix)
$root = $PSScriptRoot

$badLines = 0
$total = 0
$allWords = @()
foreach ($f in (Get-ChildItem -Path $root -Filter 'bank_part*.tsv' | Sort-Object Name)) {
  $lines = @(Get-Content $f.FullName -Encoding UTF8)
  $valid = @()
  foreach ($line in $lines) {
    $c = $line -split '\|'
    if ($c.Count -ne 7) { $badLines++; continue }
    $w = $c[0].TrimStart([char]0xFEFF).Trim()
    if ($w -notmatch '^[A-Za-z][A-Za-z'' -]*$') { $badLines++; continue }
    $valid += $line
  }
  $seen = @{}
  $out = foreach ($line in $valid) {
    $key = (($line -split '\|')[0]).Trim().ToLower()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $line
  }
  if ($Fix) { $out | Set-Content $f.FullName -Encoding UTF8 }
  $total += $out.Count
  $allWords += @($out | ForEach-Object { (($_ -split '\|')[0]).Trim().ToLower() })
  Write-Host ("{0}: {1} 行（有效 {2} / 去重后 {3}）" -f $f.Name, $lines.Count, $valid.Count, $out.Count)
}

$used = @()
if (Test-Path (Join-Path $root 'used_log.csv')) {
  $used = @(Get-Content (Join-Path $root 'used_log.csv') -Encoding UTF8 | Select-Object -Skip 1 | Where-Object { $_ -match '\S' } | ForEach-Object { ($_ -split ',')[0].Trim().ToLower() })
}
$unique = @($allWords | Sort-Object -Unique)
Write-Host ("词库总计 {0} 条 / {1} 唯一词 | 已用 {2} | 剩余 {3}" -f $total, $unique.Count, $used.Count, ($unique.Count - $used.Count))
if ($badLines -gt 0) { Write-Host "⚠️ 发现 $badLines 行异常数据（字段数错误或 word 非法）" } else { Write-Host '✅ 无异常数据行' }
