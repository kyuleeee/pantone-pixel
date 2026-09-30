#Requires -Version 7
# 새 Windows Terminal 창을 열어 demo.ps1 을 실행하고, 그 창을 MP4로 녹화해요. (ffmpeg 필요)
# 녹화하는 동안(약 1분 30초) 창 위로 다른 창을 올리지 마세요.
param([string]$Output = (Join-Path $PSScriptRoot 'pantone-pixel-demo.mp4'))
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Write-Warning 'ffmpeg가 필요해요: winget install Gyan.FFmpeg'; return }
$done = Join-Path $env:TEMP 'pantone-pixel-demo\done.txt'
if (Test-Path $done) { [System.IO.File]::Delete($done) }
$demo = Join-Path $PSScriptRoot 'demo.ps1'
wt.exe -w new --size 104,32 --title 'Pantone Pixel' --suppressApplicationTitle pwsh -NoProfile -ExecutionPolicy Bypass -File "$demo" -Record "$Output"
Write-Host '녹화 중... 끝나면 창이 그대로 남아요.'
while (-not (Test-Path $done)) { Start-Sleep -Seconds 1 }
Write-Host "완료: $Output"
