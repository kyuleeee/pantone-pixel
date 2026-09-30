#Requires -Version 7
# Pantone Pixel 설치
#   1. 필요한 것 확인 (Oh My Posh, 픽셀 폰트) → 없으면 물어보고 설치
#   2. 기존 Windows Terminal 설정과 PowerShell 프로필 백업
#   3. 모듈 복사, 폰트 설정, 프로필에 시작 코드 추가
#   4. 설정 마법사 실행 (이름 → 테마 → 캐릭터)
param([switch]$SkipFont)
$ErrorActionPreference = 'Stop'

$FontFamily = 'DepartureMono Nerd Font'
$FontZip = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/DepartureMono.zip'
$data = Join-Path $HOME '.pantone-pixel'
$modDest = Join-Path (Split-Path $PROFILE) 'Modules\PantonePixel'
$wt = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

function Ask([string]$Question) { (Read-Host "  $Question [Y/n]") -notmatch '^[nN]' }
function Step([string]$Text) { Write-Host "`n  ▶ $Text" -ForegroundColor Magenta }

Write-Host "`n  ♥ Pantone Pixel 설치" -ForegroundColor Red
if (-not $wt) { Write-Warning 'Windows Terminal 설정 파일을 찾지 못했어요. Windows Terminal을 한 번 실행한 뒤 다시 설치하면 색상까지 적용돼요.' }

# ── 1. Oh My Posh ────────────────────────────────────────
Step 'Oh My Posh 확인'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) { Write-Host '  이미 설치돼 있어요.' }
elseif (Ask '프롬프트를 그려 주는 Oh My Posh가 필요해요. winget으로 설치할까요?') {
    winget install JanDeDobbeleer.OhMyPosh --source winget
    $env:PATH += ";$env:LOCALAPPDATA\Programs\oh-my-posh\bin"
}
else { Write-Warning 'Oh My Posh 없이 설치하면 프롬프트 테마는 적용되지 않아요.' }

# ── 2. 픽셀 폰트 ─────────────────────────────────────────
Step "$FontFamily 확인"
$fontReg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$hasFont = (Get-ItemProperty $fontReg -ErrorAction SilentlyContinue).PSObject.Properties.Name -match 'DepartureMono Nerd Font'
if ($hasFont) { Write-Host '  이미 설치돼 있어요.' }
elseif (-not $SkipFont -and (Ask "$FontFamily(약 4MB, GitHub nerd-fonts 공식 릴리스)를 내려받아 설치할까요?")) {
    $zip = Join-Path $env:TEMP 'DepartureMono.zip'; $dir = Join-Path $env:TEMP 'DepartureMono'
    Invoke-WebRequest $FontZip -OutFile $zip -TimeoutSec 120
    Expand-Archive $zip $dir -Force
    $dest = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force $dest | Out-Null
    Add-Type -AssemblyName PresentationCore
    Get-ChildItem $dir -Recurse -Include *.otf, *.ttf | ForEach-Object {
        Copy-Item $_.FullName $dest -Force
        # 폰트 파일 안에 적힌 실제 글꼴 이름으로 등록해야 Windows Terminal이 찾을 수 있어요.
        $family = ([System.Windows.Media.GlyphTypeface]::new([uri](Join-Path $dest $_.Name))).FamilyNames.Values | Select-Object -First 1
        New-ItemProperty $fontReg -Name "$family (TrueType)" -Value (Join-Path $dest $_.Name) -PropertyType String -Force | Out-Null
    }
    $hasFont = $true
    Write-Host '  설치했어요.'
}

# ── 3. 백업 ──────────────────────────────────────────────
Step '기존 설정 백업'
$backup = Join-Path $data ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $backup | Out-Null
if ($wt) { Copy-Item $wt (Join-Path $backup 'settings.json') }
if (Test-Path $PROFILE) { Copy-Item $PROFILE (Join-Path $backup 'Microsoft.PowerShell_profile.ps1') }
Write-Host "  $backup"

# ── 4. 모듈, 폰트 설정, 프로필 ───────────────────────────
Step '모듈 설치'
New-Item -ItemType Directory -Force $modDest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'PantonePixel\*') $modDest -Recurse -Force
Write-Host "  $modDest"

if ($wt -and $hasFont) {
    $s = Get-Content $wt -Raw | ConvertFrom-Json
    if (-not $s.profiles.defaults) { $s.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $s.profiles.defaults.font) { $s.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) }
    $s.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFamily -Force
    ConvertTo-Json -InputObject $s -Depth 32 | Set-Content $wt -Encoding utf8NoBOM
    Write-Host "  터미널 폰트: $FontFamily"
}

Step 'PowerShell 프로필 수정'
New-Item -ItemType Directory -Force (Split-Path $PROFILE) | Out-Null
$lines = @(if (Test-Path $PROFILE) { Get-Content $PROFILE })
# 다른 oh-my-posh 테마와 겹치지 않게 기존 줄은 주석으로 남겨 둡니다.
$lines = @($lines | ForEach-Object { if ($_ -match '^\s*oh-my-posh init') { "# (Pantone Pixel 설치 전 설정) $_" } else { $_ } })
if (-not ($lines -match 'Start-PantonePixel')) {
    $lines += ''
    $lines += '# Pantone Pixel: pixel(테마) · pixel-char(캐릭터) · pixel-name(이름) · pixel-run(게임) · pixel-setup(처음 설정)'
    $lines += "Import-Module '$modDest\PantonePixel.psm1' -DisableNameChecking"
    $lines += 'Start-PantonePixel'
}
Set-Content $PROFILE $lines -Encoding utf8NoBOM
Write-Host "  $PROFILE"

# ── 5. 설정 마법사 ───────────────────────────────────────
Import-Module (Join-Path $modDest 'PantonePixel.psm1') -Force -DisableNameChecking
Initialize-PantonePixel
Write-Host '  새 탭을 열면 모든 설정이 적용돼요. 되돌리려면 uninstall.ps1 을 실행하세요.' -ForegroundColor DarkGray
