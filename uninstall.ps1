#Requires -Version 7
# Pantone Pixel 되돌리기: 가장 처음 만든 백업으로 Windows Terminal 설정과 프로필을 복원합니다.
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$first = Get-ChildItem (Join-Path $HOME '.pantone-pixel') -Directory -Filter 'backup-*' | Sort-Object Name | Select-Object -First 1
if (-not $first) { Write-Warning '백업을 찾지 못했어요.'; return }
Copy-Item (Join-Path $first.FullName 'settings.json') $wt -Force
$prof = Join-Path $first.FullName 'Microsoft.PowerShell_profile.ps1'
if (Test-Path $prof) { Copy-Item $prof $PROFILE -Force }
Write-Host "복원 완료 ($($first.Name)). 새 탭을 열면 예전 모습으로 돌아와요."
Write-Host "모듈 폴더는 그대로 남아 있어요: $(Join-Path (Split-Path $PROFILE) 'Modules\PantonePixel')"
