# kitty 스타일: 여백, 픽셀 아트 배경, 블록 커서, 컴팩트 탭, 터미널 안 이미지(Sixel), CRT 효과

Add-Type -AssemblyName System.Drawing

function Get-RgbArray([string]$hex) {
    $h = $hex.TrimStart('#')
    @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

# 두 색을 섞어요. k = 0이면 a, 1이면 b
function Mix-Color([string]$a, [string]$b, [double]$k) {
    $x = Get-RgbArray $a; $y = Get-RgbArray $b
    '#{0:X2}{1:X2}{2:X2}' -f [int]($x[0] + ($y[0] - $x[0]) * $k), [int]($x[1] + ($y[1] - $x[1]) * $k), [int]($x[2] + ($y[2] - $x[2]) * $k)
}

# ── 픽셀 아트 배경 ───────────────────────────────────────
# 16:9 캔버스(160×90 도트)에 풍경을 그리고 12배 확대한 PNG를 만들어요. 하늘은 투명해서 터미널 배경색이 비쳐요.
# 터미널이 창 크기에 맞춰 그림을 늘리고 줄이므로(uniformToFill), 창을 줄이면 풍경도 같은 비율로 작아져요.
function Save-ThemeBackground($t, $Character) {
    $dir = Join-Path $script:DataDir 'bg'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $path = Join-Path $dir "$($t.id)-$($Character.id)-v2.png"
    if (Test-Path $path) { return $path }

    $AW = 160; $AH = 90; $S = 12
    $art = [System.Drawing.Bitmap]::new($AW, $AH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $seed = 7; foreach ($ch in $t.id.ToCharArray()) { $seed = ($seed * 31 + [int]$ch) % 2147483647 }
    $rng = [System.Random]::new($seed)
    $col = @{}
    function Put([int]$x, [int]$y, [string]$hex) {
        if ($x -lt 0 -or $x -ge $AW -or $y -lt 0 -or $y -ge $AH) { return }
        if (-not $col.ContainsKey($hex)) { $col[$hex] = [System.Drawing.ColorTranslator]::FromHtml($hex) }
        $art.SetPixel($x, $y, $col[$hex])
    }
    $bg = $t.scheme.background
    $far = Mix-Color $t.roles.b $bg 0.35
    $near = Mix-Color $t.roles.a $bg 0.3
    $ground = Mix-Color $t.roles.a $bg 0.6

    for ($i = 0; $i -lt 18; $i++) { Put ($rng.Next($AW)) ($rng.Next(48)) $t.roles.w }                 # 별
    for ($dy = -6; $dy -le 6; $dy++) { for ($dx = -6; $dx -le 6; $dx++) {                               # 해(달)
            if ($dx * $dx + $dy * $dy -le 38) { Put (128 + $dx) (24 + $dy) $t.roles.c } } }
    $hill = @{}
    for ($x = 0; $x -lt $AW; $x++) {
        $m = 60 + [int](7 * [Math]::Abs((($x + 10) % 36) - 18) / 18) + [int](2 * [Math]::Sin($x / 5.0))   # 먼 산
        for ($y = $m; $y -lt $AH; $y++) { Put $x $y $far }
        $h = 71 + [int][Math]::Round(3 * [Math]::Sin($x / 9.0) + 1.5 * [Math]::Sin($x / 3.7))            # 가까운 언덕
        $hill[$x] = $h
        for ($y = $h; $y -lt $AH; $y++) { Put $x $y $near }
        for ($y = 80; $y -lt $AH; $y++) { Put $x $y $ground }
    }
    # 언덕 위에 서 있는 내 캐릭터
    $cx = 40; $top = $hill[$cx + 8] - $Character.rows.Count + 1
    for ($r = 0; $r -lt $Character.rows.Count; $r++) {
        $line = $Character.rows[$r]
        for ($c = 0; $c -lt $line.Length; $c++) { $hex = $t.roles."$($line[$c])"; if ($hex) { Put ($cx + $c) ($top + $r) $hex } }
    }

    $big = [System.Drawing.Bitmap]::new($AW * $S, $AH * $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($art, 0, 0, $AW * $S, $AH * $S)
    $big.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $big.Dispose(); $art.Dispose()
    $path
}

# ── Windows Terminal 설정에 kitty 스타일 반영 ─────────────
function Set-WtProp($obj, [string]$name, $value) {
    if ($null -eq $value) { [void]$obj.PSObject.Properties.Remove($name) }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}

function Set-KittyStyle($s, $t) {
    $cfg = Get-PixelConfig
    $d = $s.profiles.defaults
    if (($cfg.style ?? 'kitty') -eq 'kitty') {
        Set-WtProp $d padding '20, 16'
        Set-WtProp $d cursorShape 'filledBox'
        Set-WtProp $d backgroundImage (Save-ThemeBackground $t (Get-CurrentCharacter $t))
        Set-WtProp $d backgroundImageAlignment 'bottom'
        Set-WtProp $d backgroundImageStretchMode 'uniformToFill'
        Set-WtProp $d backgroundImageOpacity 0.3
        Set-WtProp $s tabWidthMode 'compact'
    }
    else {
        foreach ($n in 'padding', 'cursorShape', 'backgroundImage', 'backgroundImageAlignment', 'backgroundImageStretchMode', 'backgroundImageOpacity') { Set-WtProp $d $n $null }
        Set-WtProp $s tabWidthMode $null
    }
    switch ($cfg.fx ?? 'off') {
        'crt' { Set-WtProp $d 'experimental.pixelShaderPath' (Join-Path $PSScriptRoot 'crt.hlsl'); Set-WtProp $d 'experimental.retroTerminalEffect' $null }
        'retro' { Set-WtProp $d 'experimental.retroTerminalEffect' $true; Set-WtProp $d 'experimental.pixelShaderPath' $null }
        default { Set-WtProp $d 'experimental.pixelShaderPath' $null; Set-WtProp $d 'experimental.retroTerminalEffect' $null }
    }
}

# pixel-style kitty | plain   → 여백·배경·블록 커서·컴팩트 탭 켜고 끄기
function pixel-style {
    param([Parameter(Position = 0)][ValidateSet('kitty', 'plain')][string]$Style = 'kitty')
    $cfg = Get-PixelConfig; $cfg.style = $Style; Save-PixelConfig $cfg
    Update-WtSettings (Get-CurrentPixelTheme)
    Write-Host "  스타일: $Style"
}

# pixel-fx crt | retro | off   → CRT 주사선 효과 (crt = 팬톤 픽셀 전용 셰이더, retro = 터미널 기본 효과)
function pixel-fx {
    param([Parameter(Position = 0)][ValidateSet('crt', 'retro', 'off')][string]$Effect = 'crt')
    $cfg = Get-PixelConfig; $cfg.fx = $Effect; Save-PixelConfig $cfg
    Update-WtSettings (Get-CurrentPixelTheme)
    Write-Host "  화면 효과: $Effect"
}

# ── 터미널 안 이미지 (Sixel) ──────────────────────────────
# $Pixels: 팔레트 번호 배열(-1 = 투명), 한 픽셀을 $Scale배로 키워서 출력해요.
function Write-Sixel([int[]]$Pixels, [int]$W, [int]$H, [string[]]$Palette, [int]$Scale = 1) {
    $E = [char]27
    $outW = $W * $Scale; $outH = $H * $Scale
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("${E}P0;1;0q`"1;1;$outW;$outH")
    for ($i = 0; $i -lt $Palette.Count; $i++) {
        $c = Get-RgbArray $Palette[$i]
        [void]$sb.Append("#$i;2;$([int]($c[0] * 100 / 255));$([int]($c[1] * 100 / 255));$([int]($c[2] * 100 / 255))")
    }
    $rle = [System.Text.RegularExpressions.MatchEvaluator] { param($m) '!' + $m.Length + $m.Value[0] }
    for ($band = 0; $band -lt $outH; $band += 6) {
        $bits = @{}
        for ($r = 0; $r -lt 6; $r++) {
            $oy = $band + $r
            if ($oy -ge $outH) { break }
            $row = [int][Math]::Floor($oy / $Scale) * $W
            for ($x = 0; $x -lt $W; $x++) {
                $c = $Pixels[$row + $x]
                if ($c -lt 0) { continue }
                if (-not $bits.ContainsKey($c)) { $bits[$c] = [int[]]::new($W) }
                $bits[$c][$x] = $bits[$c][$x] -bor (1 -shl $r)
            }
        }
        $first = $true
        foreach ($c in $bits.Keys) {
            if (-not $first) { [void]$sb.Append('$') }
            $first = $false
            $line = [System.Text.StringBuilder]::new()
            foreach ($v in $bits[$c]) { [void]$line.Append([char](63 + $v), $Scale) }
            $data = [regex]::Replace($line.ToString().TrimEnd('?'), '(.)\1{3,}', $rle)
            [void]$sb.Append("#$c$data")
        }
        [void]$sb.Append('-')
    }
    [void]$sb.Append("$E\")
    [Console]::Write($sb.ToString())
    [Console]::WriteLine()
}

# Sixel을 지원하지 않는 터미널에서는 반블록 문자로 그려요.
function Write-HalfBlockImage([int[]]$Pixels, [int]$W, [int]$H, [string[]]$Palette) {
    $R = $script:R
    for ($y = 0; $y -lt $H; $y += 2) {
        $sb = [System.Text.StringBuilder]::new('  ')
        for ($x = 0; $x -lt $W; $x++) {
            $a = $Pixels[$y * $W + $x]; $b = if ($y + 1 -lt $H) { $Pixels[($y + 1) * $W + $x] } else { -1 }
            if ($a -lt 0 -and $b -lt 0) { [void]$sb.Append(' ') }
            elseif ($a -lt 0) { [void]$sb.Append("$(Fg $Palette[$b])▄$R") }
            elseif ($b -lt 0) { [void]$sb.Append("$(Fg $Palette[$a])▀$R") }
            else { [void]$sb.Append("$(Fg $Palette[$a])$(Bg $Palette[$b])▀$R") }
        }
        Write-Host $sb.ToString()
    }
}

# pixel-show               → 지금 캐릭터를 큰 이미지로
# pixel-show photo.jpg     → 사진을 테마의 팬톤 색만 쓰는 도트 그림으로 바꿔서 보여줘요
#   -Width 40   가로 칸 수    -Pixel 4   도트 하나의 크기(클수록 더 도트 느낌)
#   -Original   팬톤 색 대신 원래 색에 가깝게(216색)    -Blocks   이미지 대신 문자로 그리기
#   -NoDither   디더링 끄기 (기본은 4×4 바이어 디더링으로 적은 색으로도 그라데이션을 표현해요)
function pixel-show {
    param([Parameter(Position = 0)][string]$Path, [int]$Width = 36, [int]$Pixel = 4, [switch]$Original, [switch]$Blocks, [switch]$NoDither)
    $t = Get-CurrentPixelTheme
    $useSixel = -not $Blocks -and $env:WT_SESSION

    if (-not $Path) {
        $c = Get-CurrentCharacter $t
        $keys = @('a', 'b', 'c', 'w', 'k', 'g')
        $palette = [string[]]($keys | ForEach-Object { $t.roles.$_ })
        $W = $c.rows[0].Length; $H = $c.rows.Count
        $px = [int[]]::new($W * $H)
        for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { $px[$y * $W + $x] = [array]::IndexOf($keys, [string]$c.rows[$y][$x]) } }
        if ($useSixel) { Write-Sixel $px $W $H $palette 12 } else { Write-HalfBlockImage $px $W $H $palette }
        return
    }

    $full = (Resolve-Path $Path -ErrorAction Stop).Path
    $src = [System.Drawing.Bitmap]::new($full)
    $sw = [Math]::Max(1, [int]($Width * 10 / $Pixel))
    if (-not $useSixel) { $sw = $Width }
    $sh = [Math]::Max(1, [int]($src.Height * $sw / $src.Width))
    $small = [System.Drawing.Bitmap]::new($sw, $sh, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, 0, 0, $sw, $sh)
    $g.Dispose(); $src.Dispose()
    $lock = $small.LockBits([System.Drawing.Rectangle]::new(0, 0, $sw, $sh), 'ReadOnly', 'Format32bppArgb')
    $bytes = [byte[]]::new($lock.Stride * $sh)
    [System.Runtime.InteropServices.Marshal]::Copy($lock.Scan0, $bytes, 0, $bytes.Length)
    $stride = $lock.Stride
    $small.UnlockBits($lock); $small.Dispose()

    if ($Original) {
        $palette = [string[]](0..215 | ForEach-Object { '#{0:X2}{1:X2}{2:X2}' -f ([int][Math]::Floor($_ / 36) * 51), (([int][Math]::Floor($_ / 6) % 6) * 51), (($_ % 6) * 51) })
    }
    else {
        # 테마의 팬톤 색 전부(터미널 16색 + 배경·글자 + 캐릭터 색)
        $palette = [string[]](@($t.scheme.PSObject.Properties | Where-Object Name -notin 'cursorColor', 'selectionBackground' | ForEach-Object Value) + @($t.roles.PSObject.Properties.Value) | Select-Object -Unique)
    }
    $rgb = $palette | ForEach-Object { , (Get-RgbArray $_) }
    $cache = @{}
    $bayer = @(0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5)
    $px = [int[]]::new($sw * $sh)
    for ($y = 0; $y -lt $sh; $y++) {
        for ($x = 0; $x -lt $sw; $x++) {
            $o = $y * $stride + $x * 4
            if ($bytes[$o + 3] -lt 128) { $px[$y * $sw + $x] = -1; continue }
            $b = [int]$bytes[$o]; $gg = [int]$bytes[$o + 1]; $r = [int]$bytes[$o + 2]
            if (-not $NoDither) {
                $shift = [int](($bayer[($y % 4) * 4 + ($x % 4)] / 16.0 - 0.47) * 56)
                $r = [Math]::Clamp($r + $shift, 0, 255); $gg = [Math]::Clamp($gg + $shift, 0, 255); $b = [Math]::Clamp($b + $shift, 0, 255)
            }
            if ($Original) { $px[$y * $sw + $x] = [int][Math]::Round($r / 51) * 36 + [int][Math]::Round($gg / 51) * 6 + [int][Math]::Round($b / 51); continue }
            $key = (($r -shr 3) -shl 10) -bor (($gg -shr 3) -shl 5) -bor ($b -shr 3)
            if (-not $cache.ContainsKey($key)) {
                $best = 0; $bestD = [double]::MaxValue
                for ($i = 0; $i -lt $rgb.Count; $i++) {
                    $dr = $r - $rgb[$i][0]; $dg = $gg - $rgb[$i][1]; $db = $b - $rgb[$i][2]
                    $dist = 2 * $dr * $dr + 4 * $dg * $dg + 3 * $db * $db
                    if ($dist -lt $bestD) { $bestD = $dist; $best = $i }
                }
                $cache[$key] = $best
            }
            $px[$y * $sw + $x] = $cache[$key]
        }
    }
    if ($useSixel) { Write-Sixel $px $sw $sh $palette $Pixel } else { Write-HalfBlockImage $px $sw $sh $palette }
}


