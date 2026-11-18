Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Engine.ps1')
$n=0
function Check([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $script:n++
    "PASS: $Name"
}
$fixtureToken='web.gvs+Unit_Test53'
$jar=[Text.Encoding]::UTF8.GetBytes(("# Netscape HTTP Cookie File"+[Environment]::NewLine+
    (@('127.0.0.1','FALSE','/','FALSE','0','pyrate_test','FixtureCookie53') -join [char]9)+[Environment]::NewLine))
$a=New-BwSourceAccess $fixtureToken $jar
Check ($a.Po -ceq $fixtureToken) 'Structured token accepted'
$invalid=$false
try { $null=New-BwSourceAccess 'web.gvs+bad;option' $null } catch { $invalid=$true }
Check $invalid 'Malformed token rejected'
$badCookie=$false
try { $null=New-BwSourceAccess '' ([Text.Encoding]::UTF8.GetBytes('invalid')) } catch { $badCookie=$true }
Check $badCookie 'Only Netscape cookie exports accepted'
$youtube=New-BwJobAccess $a 'https://www.youtube.com/watch?v=fixture'
$other=New-BwJobAccess $a 'https://example.com/test'
try {
    $configuration=[IO.File]::ReadAllText($youtube.Config)
    Check ($configuration.Contains($fixtureToken+';player_client=default,web')) 'YouTube input receives the configured PO token'
    Check (!$configuration.Contains('FixtureCookie53')) 'Cookie values stay in the private cookie file'
    Check (![IO.File]::ReadAllText($other.Config).Contains($fixtureToken)) 'Other extractors do not receive YouTube PO tokens'
    $job=[pscustomobject]@{ Url='https://www.youtube.com/watch?v=fixture'; Scope='single'; Height=1080 }
    $tools=@{'ffmpeg'=(Join-Path $PSScriptRoot 'ffmpeg.exe');'deno'=(Join-Path $PSScriptRoot 'deno.exe')}
    $args=@(New-BwArguments $job MP4 $tools $youtube.Config)
    Check ($args -contains '--config-locations' -and $args -contains $youtube.Config) 'Scoped config passed to the process'
    Check (!($args -join ' ').Contains($fixtureToken)) 'Token absent from child command line'
    Check ((Protect-BwAccessLog ('Cookie FixtureCookie53 ' + $fixtureToken + ' ' + $youtube.Directory) $youtube) -ceq 'Cookie [cookie] [PO token] [source credentials]') 'Log strings redact credentials and private path'
} finally {
    foreach ($entry in @($youtube,$other)) { if ($entry) { [IO.Directory]::Delete($entry.Directory,$true) } }
}
$browserAccess=New-BwSourceAccess '' $null 'Firefox'
$browserSession=New-BwJobAccess $browserAccess 'https://example.com/test'
try {
    $cfg=[IO.File]::ReadAllText($browserSession.Config)
    Check ($cfg.Trim() -ceq "--cookies-from-browser 'firefox'") 'Browser mode uses only the yt-dlp browser reader'
    Check (!(Test-Path (Join-Path $browserSession.Directory 'cookies.txt'))) 'Browser sign-in does not write a cookie export'
    $invalidBrowser=$false
    try { $null=New-BwSourceAccess '' $null 'firefox:untrusted' } catch { $invalidBrowser=$true }
    Check $invalidBrowser 'Browser argument is allowlisted'
    $combine=$false
    try { $null=New-BwSourceAccess '' $jar 'firefox' } catch { $combine=$true }
    Check $combine 'Browser credentials cannot be merged into an imported cookie export'
} finally { [IO.Directory]::Delete($browserSession.Directory,$true) }
if ([IO.Path]::DirectorySeparatorChar -ne '\') {
    $arch=$env:PROCESSOR_ARCHITECTURE
    try {
        foreach ($m in @('AMD64','ARM64')) {
            $env:PROCESSOR_ARCHITECTURE=$m
            $resolved=Get-BwToolPaths
            Check (!@($resolved.Values | Where-Object { !$_ }).Count) "Bundled $m tools resolve without system PATH"
        }
        $machine=Get-BwToolPaths -MachineOnly
        Check (@($machine.Values | Where-Object { $_ }).Count -eq 0) 'Machine-only updater never treats bundled runtimes as installed system tools'
    } finally { $env:PROCESSOR_ARCHITECTURE=$arch }
}
"$n source-access and packaging checks passed."
