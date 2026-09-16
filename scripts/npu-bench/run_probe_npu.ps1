# run_probe_npu.ps1 — PC 侧一键跑板端 NPU 体检（Windows PowerShell）
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\npu-bench\run_probe_npu.ps1 [板子别名]
# 默认走 board-lan（局域网，SSH 别名需自行配置）；直连网线时传 board
param([string]$Board = 'board-lan')
$ErrorActionPreference = 'Continue'
chcp 65001 > $null
# 本脚本与 probe_board_npu.sh 同目录，直接用 $PSScriptRoot

Write-Host '--- 1) 本机以太网/链路检查（可选）---'
try { $ok = Test-Connection -ComputerName <direct-ip> -Count 2 -Quiet -ErrorAction Stop } catch { $ok = $false }
if (-not $ok) { Write-Host '直连地址 <direct-ip> 不可达（没插网线？）——继续尝试 ' -NoNewline; Write-Host $Board }

Write-Host '--- 2) 推送并执行板端体检脚本 ---'
scp -o ConnectTimeout=8 "$PSScriptRoot\probe_board_npu.sh" "${Board}:/tmp/probe_board_npu.sh"
if ($LASTEXITCODE -ne 0) { Write-Error "scp 失败，$Board 不可达"; exit 1 }
ssh -o ConnectTimeout=8 $Board 'bash /tmp/probe_board_npu.sh'
