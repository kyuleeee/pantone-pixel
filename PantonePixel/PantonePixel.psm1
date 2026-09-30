#Requires -Version 7
# PantonePixel: 팬톤 컬러 조합으로 Windows Terminal 색상, 프롬프트, 인사말을 한 번에 바꾸는 모듈

$script:ThemesFile = Join-Path $PSScriptRoot 'themes.json'
$script:DataDir    = Join-Path $HOME '.pantone-pixel'
$script:StateFile  = Join-Path $script:DataDir 'current'
$script:CharFile   = Join-Path $script:DataDir 'character'
$script:CharsFile  = Join-Path $PSScriptRoot 'characters.json'
$script:OmpFile    = Join-Path $script:DataDir 'current.omp.json'
$script:ConfigFile = Join-Path $script:DataDir 'config.json'
# Windows Terminal 설치 방식(스토어, Preview, 직접 설치)마다 설정 파일 위치가 달라요.
$script:WtSettings = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$script:E = [char]27
$script:R = "$([char]27)[0m"
New-Item -ItemType Directory -Force $script:DataDir | Out-Null

# ── 색 도우미 ─────────────────────────────────────────────
function Rgb([string]$hex) {
    $h = $hex.TrimStart('#')
    '{0};{1};{2}' -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
}
function Fg([string]$hex) { "$script:E[38;2;$(Rgb $hex)m" }
function Bg([string]$hex) { "$script:E[48;2;$(Rgb $hex)m" }

# 문자열 스프라이트를 반블록(▀▄) 문자로 바꿔 한 칸에 픽셀 두 개씩 그립니다.
function ConvertTo-HalfBlocks($rows, $colors) {
    for ($r = 0; $r -lt $rows.Count; $r += 2) {
        $top = $rows[$r]
        $bot = if ($r + 1 -lt $rows.Count) { $rows[$r + 1] } else { '.' * $top.Length }
        $sb = [System.Text.StringBuilder]::new()
        for ($i = 0; $i -lt $top.Length; $i++) {
            $t = $colors."$($top[$i])"; $b = $colors."$($bot[$i])"
            if (-not $t -and -not $b) { [void]$sb.Append(' ') }
            elseif (-not $t) { [void]$sb.Append("$(Fg $b)▄$script:R") }
            elseif (-not $b) { [void]$sb.Append("$(Fg $t)▀$script:R") }
            else { [void]$sb.Append("$(Fg $t)$(Bg $b)▀$script:R") }
        }
        $sb.ToString()
    }
}

# ── 사용자 설정 (이름 등) ────────────────────────────────
function Get-PixelConfig {
    if (Test-Path $script:ConfigFile) { Get-Content $script:ConfigFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
}
function Save-PixelConfig([hashtable]$Config) {
    ConvertTo-Json -InputObject $Config | Set-Content $script:ConfigFile -Encoding utf8NoBOM
}

# 번호(1부터)나 id로 목록에서 하나를 고릅니다.
function Resolve-Choice($Items, [string]$Answer) {
    $Items = @($Items)
    if ($Answer -match '^\d+$' -and [int]$Answer -ge 1 -and [int]$Answer -le $Items.Count) { return $Items[[int]$Answer - 1] }
    $Items | Where-Object id -eq $Answer | Select-Object -First 1
}

# ── 테마 읽기 ─────────────────────────────────────────────
function Get-PixelThemes { @(Get-Content $script:ThemesFile -Raw | ConvertFrom-Json) }

function Get-CurrentPixelTheme {
    $id = if (Test-Path $script:StateFile) { (Get-Content $script:StateFile -Raw).Trim() } else { 'coral-reef' }
    $all = Get-PixelThemes
    ($all | Where-Object id -eq $id) ?? $all[0]
}

# ── 캐릭터 ───────────────────────────────────────────────
function Get-PixelCharacters {
    $raw = Get-Content $script:CharsFile -Raw | ConvertFrom-Json
    foreach ($p in $raw.PSObject.Properties) {
        if ($p.Name -notlike '_*') { [pscustomobject]@{ id = $p.Name; name = $p.Value.name; rows = @($p.Value.rows) } }
    }
}

# 직접 고른 캐릭터가 있으면 그것을, 없으면 테마 기본 캐릭터를 씁니다.
function Get-CurrentCharacter($Theme = (Get-CurrentPixelTheme)) {
    $all = @(Get-PixelCharacters)
    $id = if (Test-Path $script:CharFile) { (Get-Content $script:CharFile -Raw).Trim() } else { $Theme.character }
    ($all | Where-Object id -eq $id) ?? ($all | Where-Object id -eq $Theme.character) ?? $all[0]
}

function Get-CharacterArt($Character, $Theme) { @(ConvertTo-HalfBlocks $Character.rows $Theme.roles) }

# ── Oh My Posh 설정 생성 ──────────────────────────────────
function New-OmpConfig($t) {
    $p = $t.prompt
    $sym = [string][char]0xE0C6   # Nerd Font 픽셀 계단 구분자
    $branch = [string][char]0xE0A0
    $py = [string][char]0xE235
    function Seg($type, $pair, $tpl, $extra) {
        $s = [ordered]@{ type = $type; style = 'powerline'; powerline_symbol = $sym; background = $pair[0]; foreground = $pair[1]; template = $tpl }
        if ($extra) { foreach ($k in $extra.Keys) { $s[$k] = $extra[$k] } }
        $s
    }
    $dirty = '{{ if or (.Working.Changed) (.Staging.Changed) }}'
    [ordered]@{
        '$schema'              = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json'
        version                = 3
        final_space            = $true
        console_title_template = "$($t.icon) {{ .Folder }}"
        blocks                 = @(
            [ordered]@{
                type = 'prompt'; alignment = 'left'
                segments = @(
                    (Seg 'text' $p.icon " $($t.icon) "),
                    (Seg 'path' $p.path ' {{ .Path }} ' @{ properties = @{ style = 'agnoster_short'; max_depth = 3 } }),
                    (Seg 'git' $p.git " $branch {{ .HEAD }}{{ if .Working.Changed }} ✎{{ .Working.String }}{{ end }}{{ if .Staging.Changed }} ✚{{ .Staging.String }}{{ end }} " @{
                        properties           = @{ fetch_status = $true }
                        background_templates = @("$dirty$($p.dirty[0]){{ end }}")
                        foreground_templates = @("$dirty$($p.dirty[1]){{ end }}")
                    }),
                    (Seg 'python' $p.lang " $py {{ if .Venv }}{{ .Venv }} {{ end }}{{ .Major }}.{{ .Minor }} "),
                    (Seg 'executiontime' $p.time ' ⧗ {{ .FormattedMs }} ' @{ properties = @{ threshold = 2000; style = 'austin' } })
                )
            },
            [ordered]@{
                type = 'prompt'; alignment = 'right'
                segments = @([ordered]@{ type = 'time'; style = 'plain'; foreground = $p.muted; properties = @{ time_format = '15:04' }; template = '▪ {{ .CurrentDate | date .Format }} ' })
            },
            [ordered]@{
                type = 'prompt'; alignment = 'left'; newline = $true
                segments = @([ordered]@{
                        type = 'status'; style = 'plain'; foreground = $p.char
                        foreground_templates = @("{{ if gt .Code 0 }}$($p.error){{ end }}")
                        properties = @{ always_enabled = $true }
                        template = '{{ if gt .Code 0 }}✖ {{ end }}▶▶'
                    })
            }
        )
    }
}

function Save-OmpConfig($t) {
    New-OmpConfig $t | ConvertTo-Json -Depth 12 | Set-Content $script:OmpFile -Encoding utf8NoBOM
}

function Initialize-PixelPrompt {
    if (-not (Test-Path $script:OmpFile)) { Save-OmpConfig (Get-CurrentPixelTheme) }
    $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()   # 새 세션 ID로 캐시된 설정을 버립니다
    oh-my-posh init pwsh --config $script:OmpFile | Invoke-Expression
}

# ── Windows Terminal 설정 반영 ────────────────────────────
function Update-WtSettings($t) {
    if (-not $script:WtSettings) { Write-Warning 'Windows Terminal 설정 파일을 찾지 못해서 프롬프트만 바꿨어요.'; return }
    $s = Get-Content $script:WtSettings -Raw | ConvertFrom-Json
    $all = Get-PixelThemes

    $schemes = foreach ($x in $all) {
        $o = [ordered]@{ name = "Pantone $($x.name)" }
        foreach ($pr in $x.scheme.PSObject.Properties) { $o[$pr.Name] = $pr.Value }
        [pscustomobject]$o
    }
    $themes = foreach ($x in $all) {
        $bg = $x.scheme.background
        [pscustomobject][ordered]@{
            name   = "Pantone $($x.name)"
            tab    = [ordered]@{ background = "$($x.tab)FF"; unfocusedBackground = "$($bg)FF"; showCloseButton = 'hover' }
            tabRow = [ordered]@{ background = "$($bg)FF"; unfocusedBackground = "$($bg)FF" }
            window = [ordered]@{ applicationTheme = $x.mode; useMica = $false }
        }
    }
    $keepS = @($s.schemes | Where-Object { $_ -and $_.name -notlike 'Pantone *' })
    $keepT = @($s.themes | Where-Object { $_ -and $_.name -notlike 'Pantone *' })
    $s | Add-Member -NotePropertyName schemes -NotePropertyValue (@($keepS) + @($schemes)) -Force
    $s | Add-Member -NotePropertyName themes -NotePropertyValue (@($keepT) + @($themes)) -Force
    $s | Add-Member -NotePropertyName theme -NotePropertyValue "Pantone $($t.name)" -Force
    $s.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue "Pantone $($t.name)" -Force
    Set-KittyStyle $s $t
    ConvertTo-Json -InputObject $s -Depth 32 | Set-Content $script:WtSettings -Encoding utf8NoBOM
}

# ── 화면 출력 ────────────────────────────────────────────
function Show-PixelGreeting {
    param($Theme = (Get-CurrentPixelTheme))
    $t = $Theme; $p = $t.prompt; $R = $script:R
    # NO_COLOR 등으로 색이 꺼져 있으면 도트 그림이 줄무늬로 보이므로 글자로만 인사해요.
    if ($PSStyle.OutputRendering -eq 'PlainText') { Write-Host "`n  $($t.icon) 안녕하세요, $((Get-PixelConfig).name ?? $env:USERNAME)! ($($t.name))`n"; return }
    $art = Get-CharacterArt (Get-CurrentCharacter $t) $t
    $h = (Get-Date).Hour
    $greet = if ($h -lt 6) { '늦은 밤이에요' } elseif ($h -lt 12) { '좋은 아침이에요' } elseif ($h -lt 18) { '좋은 오후예요' } else { '좋은 저녁이에요' }
    $sw = (@($p.icon[0], $p.path[0], $p.git[0], $p.dirty[0], $p.lang[0], $p.time[0]) | ForEach-Object { "$(Fg $_)██" }) -join ''
    $info = @(
        ''
        "$(Fg $p.char)$script:E[1m$greet, $((Get-PixelConfig).name ?? $env:USERNAME) $($t.icon)$R"
        "$(Fg $p.muted)$(Get-Date -Format 'yyyy.MM.dd ddd  HH:mm')$R"
        "$sw$R  $(Fg $p.muted)$($t.name)$R"
        "$(Fg $p.muted)pixel 테마 · pixel-char 캐릭터 · pixel-show 그림 · pixel-run 게임$R"
    )
    Write-Host ''
    for ($i = 0; $i -lt $art.Count; $i++) { Write-Host ('  ' + $art[$i] + '   ' + $info[$i]) }
    Write-Host ''
}

function Show-PixelGallery {
    $cur = (Get-CurrentPixelTheme).id; $R = $script:R; $gray = Fg '#939597'; $i = 0
    Write-Host ''
    foreach ($t in Get-PixelThemes) {
        $i++
        $art = Get-CharacterArt (Get-CurrentCharacter $t) $t
        $bg = Bg $t.scheme.background
        $labels = @{ icon = $t.icon; path = '~/code'; git = 'main'; lang = 'py'; time = '2s' }
        $pill = $bg + ' ' + ((@('icon', 'path', 'git', 'lang', 'time') | ForEach-Object {
                    $pair = $t.prompt.$_; "$(Bg $pair[0])$(Fg $pair[1]) $($labels[$_]) "
                }) -join '') + $bg + ' ' + (Fg $t.prompt.char) + '▶▶ ' + (Fg $t.scheme.foreground) + 'ls  ' + $R
        $pairs = @('black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white')
        $swatch = $bg + ' ' + (($pairs | ForEach-Object {
                    $bright = 'bright' + $_.Substring(0, 1).ToUpper() + $_.Substring(1)
                    "$(Fg $t.scheme.$_)$(Bg $t.scheme.$bright)▀▀"
                }) -join '') + $bg + ' ' + $R
        $mark = if ($t.id -eq $cur) { "$(Fg $t.tab)▶$R" } else { ' ' }
        $info = @(
            ''
            "$mark $script:E[1m$i. $($t.name)$R  $gray$($t.id)$R"
            "  $gray$($t.pantone)$R"
            "  $pill"
            "  $swatch"
        )
        for ($line = 0; $line -lt $art.Count; $line++) { Write-Host ('  ' + $art[$line] + '  ' + $info[$line]) }
        Write-Host ''
    }
}

# ── 공개 명령 ────────────────────────────────────────────
function Set-PixelTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Name, [switch]$NoGreeting)
    $t = Get-PixelThemes | Where-Object id -eq $Name
    if (-not $t) { Write-Warning "'$Name' 테마가 없어요. pixel 을 입력하면 목록을 볼 수 있어요."; return }
    Set-Content $script:StateFile $t.id -Encoding utf8NoBOM
    Save-OmpConfig $t
    Update-WtSettings $t
    # Oh My Posh는 세션마다 설정을 캐시하므로 현재 탭은 다시 초기화합니다. (다른 탭은 새로 열면 반영)
    if (Get-Module oh-my-posh-core) { Initialize-PixelPrompt }
    if (-not $NoGreeting) { Clear-Host; Show-PixelGreeting $t }
}

function Start-PantonePixel {
    $interactive = $Host.Name -eq 'ConsoleHost' -and -not $env:PANTONE_PIXEL_QUIET
    # 처음 실행이면 설정 마법사부터
    if ($interactive -and -not (Test-Path $script:ConfigFile)) { Initialize-PantonePixel }
    elseif ($interactive) { Show-PixelGreeting }
    Initialize-PixelPrompt
}

# 처음 설정: 이름 → 테마 → 캐릭터. 언제든 pixel-setup 으로 다시 실행할 수 있어요.
function Initialize-PantonePixel {
    $R = $script:R; $gray = Fg '#939597'; $cfg = Get-PixelConfig
    $t0 = Get-CurrentPixelTheme
    Clear-Host
    Write-Host ''
    Write-Host "  $(Fg $t0.tab)$script:E[1m$($t0.icon) Pantone Pixel 설정$R"
    Write-Host "  ${gray}팬톤 컬러로 꾸미는 픽셀 터미널이에요. 세 가지만 정하면 끝나요.$R"
    Write-Host ''
    $default = $cfg.name ?? $env:USERNAME
    $name = Read-Host "  1/3  뭐라고 불러드릴까요? (Enter = $default)"
    $cfg.name = if ($name) { $name.Trim() } else { $default }
    Save-PixelConfig $cfg

    Show-PixelGallery
    $themes = Get-PixelThemes
    $t = (Resolve-Choice $themes (Read-Host '  2/3  테마 번호나 이름 (Enter = 1)')) ?? $themes[0]
    Set-PixelTheme $t.id -NoGreeting

    Show-CharacterGallery
    $c = Resolve-Choice (Get-PixelCharacters) (Read-Host '  3/3  캐릭터 번호나 이름 (Enter = 테마 기본)')
    if ($c) { Set-Content $script:CharFile $c.id -Encoding utf8NoBOM }
    elseif (Test-Path $script:CharFile) { [System.IO.File]::Delete($script:CharFile) }

    Clear-Host
    Show-PixelGreeting
    Write-Host "  ${gray}설정 완료! 이름은 pixel-name, 전체 설정은 pixel-setup 으로 언제든 바꿀 수 있어요.$R"
    Write-Host ''
}

# pixel-name 로벨리   → 인사말에 쓰일 이름 바꾸기
function pixel-name {
    param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Name)
    $cfg = Get-PixelConfig
    $new = if ($Name) { ($Name -join ' ').Trim() } else { Read-Host "  새 이름 (지금: $($cfg.name ?? $env:USERNAME))" }
    if (-not $new) { return }
    $cfg.name = $new; Save-PixelConfig $cfg
    Clear-Host; Show-PixelGreeting
}

# pixel            → 테마 갤러리를 보여주고 번호나 이름으로 고르기
# pixel greenery   → 바로 전환
function pixel {
    param([Parameter(Position = 0)][string]$Name)
    if ($Name) { Set-PixelTheme $Name; return }
    Show-PixelGallery
    $ans = Read-Host '  테마 번호나 이름 (Enter = 그대로)'
    if (-not $ans) { return }
    $all = Get-PixelThemes
    $t = if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $all.Count) { $all[[int]$ans - 1] } else { $all | Where-Object id -eq $ans }
    if ($t) { Set-PixelTheme $t.id } else { Write-Warning "'$ans' 테마가 없어요." }
}

function Show-CharacterGallery {
    $t = Get-CurrentPixelTheme; $cur = (Get-CurrentCharacter $t).id; $R = $script:R; $gray = Fg '#939597'
    $chars = @(Get-PixelCharacters)
    Write-Host ''
    # 한 줄에 캐릭터 4개씩 나란히 그립니다. 캐릭터 폭 16칸 + 여백 4칸 = 20칸
    for ($start = 0; $start -lt $chars.Count; $start += 4) {
        $group = @($chars[$start..([Math]::Min($start + 3, $chars.Count - 1))])
        $arts = @($group | ForEach-Object { , (Get-CharacterArt $_ $t) })
        for ($line = 0; $line -lt 5; $line++) { Write-Host ('  ' + (($arts | ForEach-Object { $_[$line] + '    ' }) -join '')) }
        $labels = for ($i = 0; $i -lt $group.Count; $i++) {
            $c = $group[$i]
            $label = "$($start + $i + 1). $($c.name) $gray$($c.id)$R"
            $width = ($start + $i + 1).ToString().Length + 2 + $c.name.Length * 2 + 1 + $c.id.Length
            $mark = if ($c.id -eq $cur) { "$(Fg $t.tab)▶$R" } else { ' ' }
            $mark + $label + (' ' * [Math]::Max(1, 19 - $width))
        }
        Write-Host (' ' + ($labels -join ''))
        Write-Host ''
    }
}

# pixel-char         → 캐릭터 갤러리를 보여주고 고르기
# pixel-char bunny   → 바로 바꾸기
# pixel-char auto    → 테마 기본 캐릭터로 되돌리기
function pixel-char {
    param([Parameter(Position = 0)][string]$Name)
    $all = @(Get-PixelCharacters)
    if (-not $Name) {
        Show-CharacterGallery
        $Name = Read-Host '  캐릭터 번호나 이름 (auto = 테마 기본, Enter = 그대로)'
        if (-not $Name) { return }
    }
    if ($Name -eq 'auto') {
        if (Test-Path $script:CharFile) { [System.IO.File]::Delete($script:CharFile) }
        Update-WtSettings (Get-CurrentPixelTheme)
        Clear-Host; Show-PixelGreeting; return
    }
    $c = if ($Name -match '^\d+$' -and [int]$Name -ge 1 -and [int]$Name -le $all.Count) { $all[[int]$Name - 1] } else { $all | Where-Object id -eq $Name }
    if (-not $c) { Write-Warning "'$Name' 캐릭터가 없어요."; return }
    Set-Content $script:CharFile $c.id -Encoding utf8NoBOM
    Update-WtSettings (Get-CurrentPixelTheme)   # 배경 그림 속 캐릭터도 바꿔요
    Clear-Host; Show-PixelGreeting
}

$charCompleter = {
    param($cmd, $param, $word)
    @(Get-PixelCharacters) + @([pscustomobject]@{ id = 'auto'; name = '테마 기본' }) | Where-Object id -like "$word*" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.id, $_.id, 'ParameterValue', $_.name)
    }
}
Register-ArgumentCompleter -CommandName pixel-char -ParameterName Name -ScriptBlock $charCompleter

$completer = {
    param($cmd, $param, $word)
    Get-PixelThemes | Where-Object id -like "$word*" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.id, $_.id, 'ParameterValue', $_.name)
    }
}
Register-ArgumentCompleter -CommandName pixel, Set-PixelTheme -ParameterName Name -ScriptBlock $completer

. (Join-Path $PSScriptRoot 'PixelRun.ps1')
. (Join-Path $PSScriptRoot 'KittyStyle.ps1')
Set-Alias pixel-run Start-PixelRun
Set-Alias pixel-setup Initialize-PantonePixel

Export-ModuleMember -Alias pixel-run, pixel-setup -Function Initialize-PantonePixel, pixel-name, pixel-style, pixel-fx, pixel-show, pixel, pixel-char, Show-CharacterGallery, Get-PixelCharacters, Get-CurrentCharacter, Set-PixelTheme, Start-PantonePixel, Show-PixelGreeting, Show-PixelGallery, Get-PixelThemes, Get-CurrentPixelTheme, Start-PixelRun




