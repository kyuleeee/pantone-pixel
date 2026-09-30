# Pixel Run: 크롬 공룡 게임처럼 내 캐릭터가 장애물을 피하는 미니 게임
# 조작: Space / ↑ 점프, ↓ 숙이기 (공중에서는 빠르게 착지), Q / Esc 종료
# 크롬 게임처럼 100점마다 점수가 깜빡이고, 150점부터 새가 날아오고, 500점마다 밤이 찾아와요.

function Start-PixelRun {
    # -Demo: 캐릭터가 알아서 피하는 구경 모드, -Frames: 지정한 프레임 수만큼 돌고 끝내기(테스트용)
    param([switch]$Demo, [int]$Frames = 0)
    $t = Get-CurrentPixelTheme
    $char = Get-CurrentCharacter $t
    $E = [char]27
    $hiFile = Join-Path $script:DataDir 'highscore'
    $hi = if (Test-Path $hiFile) { [int](Get-Content $hiFile -Raw) } else { 0 }

    # 팔레트 인덱스 (0 = 투명, 터미널 배경이 비쳐요)
    $colors = @($null, $t.roles.a, $t.roles.b, $t.roles.c, $t.roles.w, $t.roles.k, $t.roles.g,
        $t.prompt.git[0], $t.prompt.muted, $t.prompt.path[0], $t.prompt.error, $t.roles.c, $t.roles.w, $t.prompt.dirty[0])
    $CACTUS = 7; $GROUND = 8; $SCORE = 9; $DEAD = 10; $STAR = 11; $MOON = 12; $BIRD = 13
    $fg = @(''); $bg = @('')
    for ($i = 1; $i -lt $colors.Count; $i++) { $fg += "$E[38;2;$(Rgb $colors[$i])m"; $bg += "$E[48;2;$(Rgb $colors[$i])m" }
    $charMap = @{ a = 1; b = 2; c = 3; w = 4; k = 5; g = 6 }
    $deadMap = @{ a = $DEAD; b = $DEAD; c = $DEAD; w = $DEAD; k = $DEAD; g = $DEAD }

    # ── 스프라이트 ──
    $cactusS = @('..c..', 'c.c..', 'c.c.c', 'ccc.c', '..ccc', '..c..', '..c..', '..c..')
    $cactusL = @('...c...', '..ccc..', '..ccc.c', 'c.ccc.c', 'c.ccc.c', 'c.ccccc', 'ccccc..', '..ccc..', '..ccc..', '..ccc..', '..ccc..')
    $birdA = @('......#.....', '......##....', '......###...', '.##...####..', '############', '.....#######', '............', '............')
    $birdB = @('............', '............', '.##.........', '############', '.....#######', '......###...', '......##....', '......#.....')
    $cloud = @('...ggg.....', '.ggggggg...', 'gggggggggg.')
    $moon = @('..ww...', '.www...', 'www....', 'www....', 'www....', '.www...', '..ww...')
    $restartIcon = @('..#####..', '.#.....##', '#.....###', '#........', '#........', '#.......#', '.#.....#.', '..#####..')
    $font = @{
        '0' = @('###', '#.#', '#.#', '#.#', '###'); '1' = @('.#.', '##.', '.#.', '.#.', '###')
        '2' = @('###', '..#', '###', '#..', '###'); '3' = @('###', '..#', '###', '..#', '###')
        '4' = @('#.#', '#.#', '###', '..#', '..#'); '5' = @('###', '#..', '###', '..#', '###')
        '6' = @('###', '#..', '###', '#.#', '###'); '7' = @('###', '..#', '.#.', '.#.', '.#.')
        '8' = @('###', '#.#', '###', '#.#', '###'); '9' = @('###', '#.#', '###', '..#', '###')
        'H' = @('#.#', '#.#', '###', '#.#', '#.#'); 'I' = @('###', '.#.', '.#.', '.#.', '###')
        'G' = @('###', '#..', '#.#', '#.#', '###'); 'A' = @('.#.', '#.#', '###', '#.#', '#.#')
        'M' = @('#.#', '###', '###', '#.#', '#.#'); 'E' = @('###', '#..', '##.', '#..', '###')
        'O' = @('###', '#.#', '#.#', '#.#', '###'); 'V' = @('#.#', '#.#', '#.#', '#.#', '.#.')
        'R' = @('##.', '#.#', '##.', '#.#', '#.#')
    }
    # 숙이기: 두 줄을 한 줄로 눌러서 키를 절반으로
    $duckRows = for ($r = 0; $r -lt $char.rows.Count; $r += 2) {
        $top = $char.rows[$r]; $bot = $char.rows[$r + 1]
        -join (0..($top.Length - 1) | ForEach-Object { if ($top[$_] -ne '.') { $top[$_] } else { $bot[$_] } })
    }

    try { $W = [Math]::Min([Console]::WindowWidth - 4, 90) } catch { $W = 80 }
    $TEXT_ROWS = 18; $H = $TEXT_ROWS * 2; $G = $H - 4
    $buf = [int[]]::new($W * $H)
    # 캐릭터 폭(16px)을 넉넉히 넘도록 높고 길게 뛰어요: 최고 높이 약 21px, 체공 약 29프레임
    $JUMP = -2.9; $GRAVITY = 0.2
    $sb = [System.Text.StringBuilder]::new()

    # 스프라이트를 버퍼에 찍고, 장애물과 겹친 픽셀이 있으면 true를 돌려줍니다.
    function Blit($rows, [int]$x, [int]$y, $map, [switch]$Hit) {
        $collided = $false
        for ($r = 0; $r -lt $rows.Count; $r++) {
            $yy = $y + $r
            if ($yy -lt 0 -or $yy -ge $H) { continue }
            $line = $rows[$r]
            for ($c = 0; $c -lt $line.Length; $c++) {
                $ch = [string]$line[$c]
                if ($ch -eq '.') { continue }
                $xx = $x + $c
                if ($xx -lt 0 -or $xx -ge $W) { continue }
                $idx = $yy * $W + $xx
                if ($Hit) { $v = $buf[$idx]; if ($v -eq $CACTUS -or $v -eq $BIRD) { $collided = $true } }
                $buf[$idx] = $map[$ch]
            }
        }
        $collided
    }

    function Draw-Text([string]$s, [int]$x, [int]$y, [int]$color) {
        foreach ($ch in $s.ToCharArray()) {
            if ($ch -ne ' ') { [void](Blit $font["$ch"] $x $y @{ '#' = $color }) }
            $x += 4
        }
    }

    function Set-Pixel([int]$x, [int]$y, [int]$color) {
        if ($x -ge 0 -and $x -lt $W -and $y -ge 0 -and $y -lt $H) { $buf[$y * $W + $x] = $color }
    }

    function Render([string]$footer) {
        [void]$sb.Clear(); [void]$sb.Append("$E[H`n")
        for ($row = 0; $row -lt $TEXT_ROWS; $row++) {
            [void]$sb.Append('  '); $prev = ''
            $o1 = 2 * $row * $W; $o2 = $o1 + $W
            for ($x = 0; $x -lt $W; $x++) {
                $a = $buf[$o1 + $x]; $b = $buf[$o2 + $x]
                if ($a -eq 0 -and $b -eq 0) { $code = "$E[0m"; $ch = ' ' }
                elseif ($a -eq 0) { $code = "$E[0m" + $fg[$b]; $ch = '▄' }
                elseif ($b -eq 0) { $code = "$E[0m" + $fg[$a]; $ch = '▀' }
                else { $code = $fg[$a] + $bg[$b]; $ch = '▀' }
                if ($code -ne $prev) { [void]$sb.Append($code); $prev = $code }
                [void]$sb.Append($ch)
            }
            [void]$sb.Append("$E[0m$E[K`n")
        }
        [void]$sb.Append("`n  $footer$E[0m$E[K")
        [Console]::Write($sb.ToString())
    }

    $muted = $fg[$GROUND]; $accent = $fg[$SCORE]
    $stars = 1..12 | ForEach-Object { @{ x = Get-Random -Maximum $W; y = 2 + (Get-Random -Maximum 12); p = Get-Random -Maximum 40 } }

    # 한국어 콘솔(CP949)에는 ▀▄ 문자가 없어서 게임 동안만 UTF-8로 출력합니다.
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::Write("$E[?1049h$E[?25l$E[2J")
    try {
        $state = if ($Demo) { 'run' } else { 'ready' }; $quit = $false; $total = 0
        while (-not $quit) {
            # ── 새 판 준비 ──
            $dy = 0.0; $vy = 0.0; $speed = 1.8; $dist = 0.0; $frame = 0; $anim = 0
            $score = 0; $milestone = 0; $flash = 0; $duck = 0; $overFrames = 0
            $dead = $false; $restart = $false
            $obstacles = [System.Collections.Generic.List[object]]::new()
            $clouds = @(@{ x = [double]($W * 0.3); y = 6 }, @{ x = [double]($W * 0.8); y = 9 })
            # 지평선 위 작은 돌기(G-1)와 아래 조약돌(G+1~G+3)
            $pebbles = 1..14 | ForEach-Object { @{ x = [double](Get-Random -Maximum $W); y = (@(($G - 1), ($G + 1), ($G + 2), ($G + 3)))[(Get-Random -Maximum 4)] } }
            $nextGap = 30

            while (-not $quit -and -not $restart) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $anim++

                $total++
                if ($Frames -and $total -gt $Frames) { $quit = $true; break }

                # ── 데모 자동 조종: 앞에 장애물이 오면 점프하거나 숙여요 ──
                if ($Demo) {
                    if ($state -eq 'over' -and $overFrames -gt 30) { $restart = $true; $state = 'run'; break }
                    $next = $obstacles | Where-Object { $_.x -gt 0 } | Select-Object -First 1
                    if ($next -and $state -eq 'run') {
                        $gap = $next.x - 20
                        $width = if ($next.kind -eq 'bird') { 12 } else { $next.rows[0].Length }
                        $jumpAt = $speed * 14.5 - (16 + $width) / 2
                        if ($next.kind -eq 'bird' -and $next.y -eq ($G - 15)) { if ($gap -lt 12) { $duck = 18 } }
                        elseif (-not ($next.kind -eq 'bird' -and $next.y -lt ($G - 15)) -and $gap -lt $jumpAt -and $gap -gt -4 -and $dy -eq 0) { $vy = $JUMP }
                    }
                }

                # ── 입력 ──
                while (-not $Demo -and $(try { [Console]::KeyAvailable } catch { $false })) {
                    $key = [Console]::ReadKey($true).Key.ToString()
                    if ($key -in 'Q', 'Escape') { $quit = $true }
                    elseif ($key -in 'Spacebar', 'UpArrow', 'W') {
                        if ($state -eq 'over') { if ($overFrames -gt 12) { $restart = $true; $state = 'run' } }
                        else {
                            if ($state -eq 'ready') { $state = 'run' }
                            if ($dy -eq 0) { $vy = $JUMP; $duck = 0 }
                        }
                    }
                    elseif ($key -in 'DownArrow', 'S' -and $state -eq 'run') {
                        if ($dy -lt 0) { $vy += 1.6 } else { $duck = 18 }
                    }
                }
                if ($restart -or $quit) { break }

                # ── 움직임 ──
                if ($state -eq 'run') {
                    $frame++
                    $speed = [Math]::Min(4.0, $speed + 0.0012)
                    $dist += $speed
                    if ($duck -gt 0) { $duck-- }
                    if ($dy -lt 0 -or $vy -lt 0) { $vy += $GRAVITY; $dy += $vy; if ($dy -ge 0) { $dy = 0; $vy = 0 } }
                    foreach ($o in $obstacles) { $o.x -= $speed }
                    while ($obstacles.Count -and $obstacles[0].x -lt -14) { $obstacles.RemoveAt(0) }
                    $last = if ($obstacles.Count) { $obstacles[$obstacles.Count - 1].x } else { -999 }
                    if ($W - $last -gt $nextGap) {
                        if ($score -gt 150 -and (Get-Random -Maximum 4) -eq 0) {
                            # 낮은 새는 점프, 중간 새는 숙이기, 높은 새는 그냥 지나가요
                            $birdTop = (@(($G - 9), ($G - 15), ($G - 27)))[(Get-Random -Maximum 3)]
                            $obstacles.Add(@{ x = [double]$W; kind = 'bird'; y = $birdTop })
                        }
                        else {
                            $spr = if ((Get-Random -Maximum 3) -eq 0) { $cactusL } else { $cactusS }
                            $obstacles.Add(@{ x = [double]$W; kind = 'cactus'; rows = $spr; y = $G - $spr.Count })
                            if ((Get-Random -Maximum 4) -eq 0) { $obstacles.Add(@{ x = [double]($W + 6); kind = 'cactus'; rows = $cactusS; y = $G - $cactusS.Count }) }
                        }
                        $nextGap = 34 + (Get-Random -Maximum 40) + [int]($speed * 8)
                    }
                    foreach ($c in $clouds) { $c.x -= $speed * 0.25; if ($c.x -lt -12) { $c.x = $W + (Get-Random -Maximum 30); $c.y = 5 + (Get-Random -Maximum 6) } }
                    foreach ($p in $pebbles) { $p.x -= $speed; if ($p.x -lt 0) { $p.x += $W } }
                    $score = [int]($dist / 6)
                    if ([int][Math]::Floor($score / 100) -gt $milestone) { $milestone = [int][Math]::Floor($score / 100); $flash = 36 }
                    if ($flash -gt 0) { $flash-- }
                }
                elseif ($state -eq 'over') { $overFrames++ }

                # ── 그리기 ──
                [Array]::Clear($buf, 0, $buf.Length)
                if (([int][Math]::Floor($score / 500)) % 2 -eq 1) {
                    [void](Blit $moon ($W - 36) 8 @{ w = $MOON })
                    foreach ($s in $stars) { if ((($anim + $s.p) % 40) -lt 28) { Set-Pixel $s.x $s.y $STAR } }
                }
                foreach ($c in $clouds) { [void](Blit $cloud ([int]$c.x) $c.y @{ g = $GROUND }) }
                for ($x = 0; $x -lt $W; $x++) { $buf[$G * $W + $x] = $GROUND }
                foreach ($p in $pebbles) { Set-Pixel ([int][Math]::Floor($p.x)) $p.y $GROUND }
                foreach ($o in $obstacles) {
                    if ($o.kind -eq 'bird') {
                        $wing = if ((($anim -shr 3) -band 1) -eq 0) { $birdA } else { $birdB }
                        [void](Blit $wing ([int]$o.x) $o.y @{ '#' = $BIRD })
                    }
                    else { [void](Blit $o.rows ([int]$o.x) $o.y @{ c = $CACTUS }) }
                }

                $rows = if ($duck -gt 0 -and $dy -eq 0) { $duckRows } else { $char.rows }
                $bob = if ($state -eq 'run' -and $dy -eq 0 -and ($frame -band 4)) { -1 } else { 0 }
                $top = $G - $rows.Count + [int]$dy + $bob
                $hit = Blit $rows 4 $top ($dead ? $deadMap : $charMap) -Hit
                if ($state -eq 'run' -and $hit) {
                    $dead = $true; $state = 'over'; $overFrames = 0
                    if (-not $Demo -and $score -gt $hi) { $hi = $score; Set-Content $hiFile $hi }
                    [void](Blit $rows 4 $top $deadMap)
                }

                if ($flash -eq 0 -or (($flash -shr 2) -band 1) -eq 0) { Draw-Text ('{0:D5}' -f $score) ($W - 21) 1 $SCORE }
                if ($hi -gt 0) { Draw-Text ('HI {0:D5}' -f $hi) ($W - 55) 1 $GROUND }
                if ($state -eq 'over') {
                    Draw-Text 'GAME OVER' ([int](($W - 35) / 2)) 9 $SCORE
                    [void](Blit $restartIcon ([int](($W - 9) / 2)) 16 @{ '#' = $SCORE })
                }

                $footer = switch ($state) {
                    'ready' { "$accent$($t.icon) PIXEL RUN$E[0m  ${muted}Space/↑ 시작 · ↓ 숙이기 · Q 종료" }
                    'run' { "$accent$($t.icon) $($char.name)$E[0m  ${muted}Space/↑ 점프 · ↓ 숙이기 · Q 종료" }
                    'over' { "$($fg[$DEAD])GAME OVER$E[0m  ${muted}점수 $score · 최고 $hi · Space 다시 · Q 종료" }
                }
                Render $footer
                $wait = 33 - $sw.ElapsedMilliseconds
                if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
            }
        }
    }
    finally {
        [Console]::Write("$E[0m$E[?25h$E[?1049l")
        [Console]::OutputEncoding = $oldEncoding
    }
}



