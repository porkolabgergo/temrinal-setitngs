# PowerShell profile — works in Windows PowerShell 5.1 and PowerShell 7+
# Built-ins only. Features needing PowerShell 7 / newer PSReadLine switch on automatically.
#
# Profile locations (each shell reads its own file):
#   PowerShell 7:   Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#   Windows PS 5.1: Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
# Tip: save one copy, and make the other just contain:  . "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

$esc   = [char]27
$isPS7 = $PSVersionTable.PSVersion.Major -ge 7

# ---------------------------------------------------------------------------
# Palette (Kanagawa Dragon, matches the Windows Terminal scheme)
# ---------------------------------------------------------------------------
function rgb([int]$hex) { "$esc[38;2;$(($hex -shr 16) -band 255);$(($hex -shr 8) -band 255);$($hex -band 255)m" }
$c = @{
    fg     = rgb 0xC5C9C5
    dim    = rgb 0x737070
    faint  = rgb 0x5C5A58
    red    = rgb 0xC4746E
    green  = rgb 0x8A9A7B
    yellow = rgb 0xC4B28A
    teal   = rgb 0x8EA4A2
    violet = rgb 0xA292A3
    gold   = rgb 0xE6C384
    bold   = "$esc[1m"
    selbg  = "$esc[48;2;58;56;54m"
    reset  = "$esc[0m"
}

# ---------------------------------------------------------------------------
# File listing / output colors (PowerShell 7.2+ only; 5.1 has no $PSStyle)
# ---------------------------------------------------------------------------
if ($PSStyle -and $PSStyle.FileInfo) {
    $PSStyle.FileInfo.Directory    = $c.yellow + $c.bold     # no background highlight
    $PSStyle.FileInfo.SymbolicLink = $c.teal
    $PSStyle.FileInfo.Executable   = $c.green
    $PSStyle.FileInfo.Extension.Clear()
    foreach ($ext in '.zip', '.7z', '.tar', '.gz', '.rar') { $PSStyle.FileInfo.Extension[$ext] = $c.red }
    foreach ($ext in '.ps1', '.psm1', '.psd1', '.bat', '.cmd') { $PSStyle.FileInfo.Extension[$ext] = $c.green }
    foreach ($ext in '.json', '.yml', '.yaml', '.xml', '.toml', '.config') { $PSStyle.FileInfo.Extension[$ext] = $c.violet }

    $PSStyle.Formatting.TableHeader  = $c.gold + $c.bold
    $PSStyle.Formatting.FormatAccent = $c.teal
    $PSStyle.Formatting.Error        = $c.red
    $PSStyle.Formatting.Warning      = $c.yellow
    $PSStyle.Formatting.Verbose      = $c.dim
    $PSStyle.Formatting.Debug        = $c.dim
    $PSStyle.Progress.Style          = $c.teal
    $PSStyle.Progress.View           = 'Minimal'
}

# ---------------------------------------------------------------------------
# PSReadLine — history, suggestions, editing
# 5.1 ships PSReadLine 2.0 (no suggestions). Suggestions need 2.1+, list view 2.2+.
# ---------------------------------------------------------------------------
Import-Module PSReadLine -ErrorAction SilentlyContinue
$psrl = (Get-Module PSReadLine).Version

Set-PSReadLineOption -EditMode Windows -BellStyle None -HistoryNoDuplicates `
    -HistorySearchCursorMovesToEnd -MaximumHistoryCount 20000 -ShowToolTips

$colors = @{
    Command   = $c.gold
    Parameter = $c.teal
    Operator  = $c.violet
    Variable  = $c.red
    String    = $c.green
    Number    = $c.violet
    Member    = $c.fg
    Type      = $c.yellow
    Keyword   = $c.violet
    Comment   = $c.dim
    Default   = $c.fg
    Selection = $c.selbg
    Error     = $c.red
}
if ($psrl -ge [version]'2.1') {
    Set-PSReadLineOption -PredictionSource History
    $colors.InlinePrediction = $c.faint
}
if ($psrl -ge [version]'2.2') {
    Set-PSReadLineOption -PredictionViewStyle InlineView
    $colors.ListPrediction         = $c.yellow
    $colors.ListPredictionSelected = $c.selbg
    # F2: toggle inline suggestion <-> dropdown list
    Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
}
Set-PSReadLineOption -Colors $colors

# Up/Down: search history for lines starting with what you've typed
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
# Tab: menu of completions you can arrow through
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious
# Ctrl+F accepts one word of a suggestion (Right arrow accepts all)
Set-PSReadLineKeyHandler -Key Ctrl+f    -Function ForwardWord
# Ctrl+D on an empty line exits, like bash
Set-PSReadLineKeyHandler -Key Ctrl+d    -Function DeleteCharOrExit

# Don't save obvious secrets to history
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    return $line -notmatch '(password|passwd|secret|token|apikey|api_key)\s*[=:]'
}

# ---------------------------------------------------------------------------
# Prompt — short path, git branch (read from .git\HEAD, no git.exe call),
# red marker on failure, tab title = folder name, Windows Terminal shell
# integration (same-folder splits + green/red command marks on the scrollbar)
# ---------------------------------------------------------------------------
function Get-GitBranch {
    $dir = $executionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    while ($dir) {
        $head = Join-Path $dir '.git\HEAD'
        if (Test-Path -LiteralPath $head -PathType Leaf) {
            $ref = (Get-Content -LiteralPath $head -Raw).Trim()
            if ($ref -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
            return $ref.Substring(0, 7)   # detached HEAD
        }
        $dir = Split-Path $dir -Parent
    }
}

$global:__LastHistoryId = -1

function prompt {
    $ok   = $?
    $code = if ($ok) { 0 } elseif ($LASTEXITCODE) { $LASTEXITCODE } else { 1 }
    $bel  = [char]7
    $out  = ''

    # Tell WT the previous command finished (+ exit code -> scrollbar mark color)
    $last = Get-History -Count 1
    if ($global:__LastHistoryId -ne -1) {
        if ($last.Id -eq $global:__LastHistoryId) { $out += "$esc]133;D$bel" }
        else { $out += "$esc]133;D;$code$bel" }
    }
    $global:__LastHistoryId = $last.Id

    $out += "$esc]133;A$bel"   # prompt start

    $loc = $executionContext.SessionState.Path.CurrentLocation
    if ($loc.Provider.Name -eq 'FileSystem') {
        $out += "$esc]9;9;`"$($loc.ProviderPath)`"$bel"   # current folder -> WT
    }

    $path = $loc.Path
    if ($path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        $path = '~' + $path.Substring($HOME.Length)
    }
    $Host.UI.RawUI.WindowTitle = Split-Path -Leaf $loc.Path

    $out += "`n$($c.teal)$path$($c.reset)"
    $branch = Get-GitBranch
    if ($branch) { $out += " $($c.dim)on$($c.reset) $($c.violet)$branch$($c.reset)" }
    if (-not $ok) { $out += " $($c.red)[$code]$($c.reset)" }

    $arrow = if ($ok) { $c.gold } else { $c.red }
    $out += "`n$arrow$(([string][char]0x276F) * ($nestedPromptLevel + 1))$($c.reset) "
    $out += "$esc]133;B$bel"   # command input starts
    return $out
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }
function mkcd([string]$Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null; Set-Location $Path }
function touch([string]$Path) {
    if (Test-Path $Path) { (Get-Item $Path).LastWriteTime = Get-Date } else { New-Item -ItemType File -Path $Path | Out-Null }
}
function which([string]$Name) { Get-Command $Name -All | Select-Object CommandType, Name, Source }
function ll  { Get-ChildItem -Force @args }
function e   { Invoke-Item . }                     # open current folder in Explorer
function reload { . $PROFILE }
function ep  { notepad $PROFILE }
function grep { $input | Select-String @args }      # ... | grep foo

# ---------------------------------------------------------------------------
# .NET / C# development
# ---------------------------------------------------------------------------
$env:DOTNET_NOLOGO                       = '1'   # no welcome banner
$env:DOTNET_CLI_TELEMETRY_OPTOUT         = '1'
$env:DOTNET_WATCH_RESTART_ON_RUDE_EDIT   = '1'   # hot reload can't apply -> restart without asking
$env:DOTNET_WATCH_SUPPRESS_LAUNCH_BROWSER = '1'  # don't open a browser tab on every `dotnet watch`

# Tab completion for the dotnet CLI (commands, options, project refs, package names)
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# Short commands
function db  { dotnet build @args }
function dr  { dotnet run @args }
function dw  { dotnet watch @args }
function dwt { dotnet watch test @args }
function dres { dotnet restore @args }

# dt            -> run all tests
# dt OrderTests -> only tests whose full name contains "OrderTests"
function dt([string]$Filter) {
    if ($Filter) { dotnet test --filter "FullyQualifiedName~$Filter" @args }
    else { dotnet test @args }
}

# Delete every bin/ and obj/ below the current folder (fixes most "weird build" issues)
function dclean {
    Get-ChildItem -Recurse -Directory -Include bin, obj -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
        ForEach-Object { Write-Host "removing $($_.FullName)" -ForegroundColor DarkGray; Remove-Item $_.FullName -Recurse -Force }
}

# Stop build servers + stray dotnet processes that keep DLLs locked
function dkill {
    dotnet build-server shutdown | Out-Null
    Get-Process dotnet, VBCSCompiler, MSBuild -ErrorAction SilentlyContinue | Stop-Process -Force
}

# Open the solution in this folder (or the nearest parent) with your default IDE
function sln {
    $dir = (Get-Location).ProviderPath
    while ($dir) {
        $s = Get-ChildItem -LiteralPath $dir -File | Where-Object Extension -in '.slnx', '.sln' | Select-Object -First 1
        if ($s) { Invoke-Item $s.FullName; return }
        $dir = Split-Path $dir -Parent
    }
    Write-Warning 'No .sln/.slnx found'
}

# Switch ASP.NET Core environment for this shell: aspenv Production
function aspenv([ValidateSet('Development', 'Staging', 'Production')][string]$Name = 'Development') {
    $env:ASPNETCORE_ENVIRONMENT = $Name
    $env:DOTNET_ENVIRONMENT     = $Name
    Write-Host "ASPNETCORE_ENVIRONMENT = $Name" -ForegroundColor DarkGray
}

# "Address already in use": who's on the port, and kill it
function port([int]$Port) {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Get-Process -Id $_.OwningProcess } | Select-Object Id, ProcessName, Path
}
function killport([int]$Port) {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -PassThru } | Select-Object Id, ProcessName
}

# One-shot dev layout in the current tab:
#   [ this shell ] | [ dotnet watch run ]
#                  | [ dotnet watch test ]
function dev {
    $here  = (Get-Location).ProviderPath
    $shell = (Get-Process -Id $PID).Path   # same shell you're in (pwsh or powershell)
    wt -w 0 split-pane -V -s 0.45 -d "$here" "$shell" -NoExit -Command "dotnet watch run" `; `
        split-pane -H -d "$here" "$shell" -NoExit -Command "dotnet watch test" `; `
        move-focus left
}

# Misc
function nugetclear { dotnet nuget locals all --clear }
function devcert    { dotnet dev-certs https --clean; dotnet dev-certs https --trust }