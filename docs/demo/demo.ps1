#Requires -Version 7
# Pantone Pixel 사용법 데모: 명령을 직접 타이핑하듯 보여주면서 실제로 실행해요.
# record-demo.ps1 이 새 Windows Terminal 창에서 이 스크립트를 실행하고, -Record 가 있으면 창을 MP4로 녹화해요.
param([string]$Record)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 녹화 환경에 NO_COLOR 가 있어도 색이 나오게
$env:NO_COLOR = $null; $PSStyle.OutputRendering = 'Ansi'
$E = [char]27
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Import-Module (Join-Path $root 'PantonePixel\PantonePixel.psm1') -Force -DisableNameChecking
$data = Join-Path $HOME '.pantone-pixel'
$wt = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

# ── 사용자 상태 백업 (데모가 끝나면 그대로 복원) ─────────
$stateFiles = 'current', 'character', 'config.json', 'highscore'
$saved = @{}
foreach ($f in $stateFiles) { $p = Join-Path $data $f; if (Test-Path $p) { $saved[$f] = Get-Content $p -Raw } }
$wtJson = Get-Content $wt -Raw | ConvertFrom-Json
$savedOpacity = $wtJson.profiles.defaults.opacity
$savedAcrylic = $wtJson.profiles.defaults.useAcrylic

function Set-WtDefault([string]$Name, $Value) {
    $s = Get-Content $wt -Raw | ConvertFrom-Json
    if ($null -eq $Value) { [void]$s.profiles.defaults.PSObject.Properties.Remove($Name) }
    else { $s.profiles.defaults | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
    ConvertTo-Json -InputObject $s -Depth 32 | Set-Content $wt -Encoding utf8NoBOM
}

# ── 연출 도우미 ──────────────────────────────────────────
function Show-Prompt {
    $p = oh-my-posh print primary --config (Join-Path $data 'current.omp.json') --shell pwsh
    [Console]::Write((($p -join "`n") -replace "$E\][^\a]*\a", '' -replace "$E\][^$E]*$E\\", ''))
}
function Type-Text([string]$Text, [int]$Delay = 65) {
    foreach ($ch in $Text.ToCharArray()) { [Console]::Write($ch); Start-Sleep -Milliseconds ($Delay + (Get-Random -Maximum 45)) }
}
function Say([string]$Comment) {
    Show-Prompt; Start-Sleep -Milliseconds 300
    [Console]::Write("$E[38;2;147;149;151m"); Type-Text "# $Comment" 40; [Console]::Write("$E[0m`n")
    Start-Sleep -Milliseconds 500
}
function Run([string]$Command, [scriptblock]$Action, [int]$After = 2200) {
    Show-Prompt; Start-Sleep -Milliseconds 450
    Type-Text $Command; Start-Sleep -Milliseconds 350; [Console]::WriteLine()
    & $Action
    Start-Sleep -Milliseconds $After
}
function Answer([string]$Question, [string]$Text) {
    [Console]::Write("  ${Question}: "); Start-Sleep -Milliseconds 900
    Type-Text $Text 120; Start-Sleep -Milliseconds 300; [Console]::WriteLine()
}

# 데모용 노을 사진 (pixel-show 로 팬톤 도트 그림이 되는 모습을 보여줘요)
function New-SunsetPhoto([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $w = 640; $h = 400
    $bmp = [System.Drawing.Bitmap]::new($w, $h); $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $sky = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Point]::new(0, 0), [System.Drawing.Point]::new(0, 260),
        [System.Drawing.Color]::FromArgb(40, 30, 90), [System.Drawing.Color]::FromArgb(255, 140, 90))
    $g.FillRectangle($sky, 0, 0, $w, 260)
    $g.FillEllipse([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 220, 110)), 380, 150, 150, 150)
    $sea = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Point]::new(0, 250), [System.Drawing.Point]::new(0, $h),
        [System.Drawing.Color]::FromArgb(230, 110, 100), [System.Drawing.Color]::FromArgb(20, 40, 90))
    $g.FillRectangle($sea, 0, 250, $w, $h - 250)
    $hill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(30, 25, 50))
    $g.FillPolygon($hill, [System.Drawing.Point[]]@([System.Drawing.Point]::new(0, 260), [System.Drawing.Point]::new(120, 170), [System.Drawing.Point]::new(230, 230), [System.Drawing.Point]::new(330, 200), [System.Drawing.Point]::new(420, 262), [System.Drawing.Point]::new(0, 262)))
    for ($i = 0; $i -lt 7; $i++) { $g.FillRectangle([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 210, 120)), 420 + ($i % 2) * 12, 270 + $i * 16, 70 - $i * 6, 4) }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}

# ── 녹화 준비 ────────────────────────────────────────────
$ffmpeg = $null
try {
    # 영상이 깔끔하도록 데모 동안만 창을 불투명하게
    Set-WtDefault opacity 100; Set-WtDefault useAcrylic $false
    Set-Content (Join-Path $data 'current') 'coral-reef'
    Set-Content (Join-Path $data 'character') 'cat'
    Set-Content (Join-Path $data 'config.json') '{ "name": "Pixel" }'
    [System.IO.File]::Delete((Join-Path $data 'highscore'))
    Set-PixelTheme coral-reef -NoGreeting
    $work = Join-Path $HOME 'pixel-demo'   # 프롬프트에 ~\pixel-demo 로 짧게 보여요
    New-Item -ItemType Directory -Force $work | Out-Null
    New-SunsetPhoto (Join-Path $work 'sunset.png')
    Set-Location $work
    Clear-Host
    Start-Sleep -Milliseconds 1500

    if ($Record) {
        Add-Type @'
using System; using System.Runtime.InteropServices;
public static class DemoWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
}
'@
        $r = [DemoWin+RECT]::new()
        [void][DemoWin]::DwmGetWindowAttribute([DemoWin]::GetForegroundWindow(), 9, [ref]$r, 16)   # 그림자를 뺀 실제 창 영역
        $w = ($r.R - $r.L) -band -2; $h = ($r.B - $r.T) -band -2
        $psi = [System.Diagnostics.ProcessStartInfo]::new('ffmpeg')
        $psi.Arguments = "-y -loglevel error -nostats -f gdigrab -framerate 30 -draw_mouse 0 -offset_x $($r.L) -offset_y $($r.T) -video_size ${w}x$h -i desktop -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p `"$Record`""
        $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.CreateNoWindow = $true
        $ffmpeg = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 1200
    }

    # ── 1. 시작 인사말 ──
    Show-PixelGreeting
    Start-Sleep -Milliseconds 2500

    # ── 2. 테마 ──
    Say '팬톤 컬러 테마 7가지를 골라 볼게요'
    Run 'pixel' {
        Show-PixelGallery
        Start-Sleep -Milliseconds 1500
        Answer '테마 번호나 이름 (Enter = 그대로)' '2'
        Set-PixelTheme very-peri
    } 2800
    Say '이름으로 바로 바꿀 수도 있어요 (Tab 자동완성)'
    Run 'pixel greenery' { Set-PixelTheme greenery } 2800

    # ── 3. 캐릭터와 이름 ──
    Say '좋아하는 캐릭터 고르기'
    Run 'pixel-char' {
        Show-CharacterGallery
        Start-Sleep -Milliseconds 1500
        Answer '캐릭터 번호나 이름' 'bunny'
        pixel-char bunny
    } 2600
    Say '인사말에 나오는 이름 바꾸기'
    Run 'pixel-name 픽셀' { pixel-name 픽셀 } 2600

    # ── 4. 터미널 안 이미지 ──
    Say '캐릭터를 진짜 이미지로 띄워요'
    Run 'pixel-show' { pixel-show } 2600
    Say '사진은 테마의 팬톤 색만 쓰는 도트 그림으로 바뀌어요'
    Run 'pixel-show sunset.png -Pixel 5' { pixel-show (Join-Path $work 'sunset.png') -Pixel 5 -Width 44 } 3500

    # ── 5. CRT 효과 ──
    Say 'CRT 주사선 효과'
    Run 'pixel viva-magenta' { Set-PixelTheme viva-magenta } 1800
    Run 'pixel-fx crt' { pixel-fx crt; Start-Sleep -Milliseconds 800; Clear-Host; Show-PixelGreeting } 3500
    Run 'pixel-fx off' { pixel-fx off } 1200

    # ── 6. 미니 게임 ──
    Say '크롬 공룡 게임 같은 미니 게임'
    Run 'pixel-run' { Start-PixelRun -Demo -Frames 480 } 300

    # ── 7. 마무리 ──
    Set-PixelTheme coral-reef
    Start-Sleep -Milliseconds 800
    Say 'pixel-setup 으로 언제든 처음부터 다시 설정할 수 있어요'
    Show-Prompt
    Start-Sleep -Milliseconds 2500
}
finally {
    if ($ffmpeg) { $ffmpeg.StandardInput.Write('q'); $ffmpeg.StandardInput.Close(); [void]$ffmpeg.WaitForExit(20000) }
    # 사용자 상태 복원
    foreach ($f in $stateFiles) {
        $p = Join-Path $data $f
        if ($saved.ContainsKey($f)) { Set-Content $p $saved[$f].TrimEnd() -Encoding utf8NoBOM -NoNewline:$false } elseif (Test-Path $p) { [System.IO.File]::Delete($p) }
    }
    $theme = if ($saved['current']) { $saved['current'].Trim() } else { 'coral-reef' }
    Set-PixelTheme $theme -NoGreeting
    Set-WtDefault opacity $savedOpacity; Set-WtDefault useAcrylic $savedAcrylic
    Set-Location $HOME
    if (Test-Path $work) { [System.IO.File]::Delete((Join-Path $work 'sunset.png')); [System.IO.Directory]::Delete($work) }
    New-Item -ItemType Directory -Force (Join-Path $env:TEMP 'pantone-pixel-demo') | Out-Null
    Set-Content (Join-Path $env:TEMP 'pantone-pixel-demo\done.txt') (Get-Date -Format o)
}

