param([string]$YtDlp, [string]$Ffmpeg, [string]$FixtureUrl, [string]$CollectionUrl)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Engine.ps1')
$script:Checks=0
function Assert-Bw($Condition,[string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    $script:Checks++
    Write-Host "PASS: $Message"
}
function Assert-BwThrows([scriptblock]$Action,[string]$Message) {
    try { & $Action | Out-Null } catch { Assert-Bw $true $Message; return }
    throw "FAIL: $Message"
}
Assert-Bw ((ConvertTo-BwWindowsArg 'plain') -ceq 'plain') 'Unquoted ordinary argument'
Assert-Bw ((ConvertTo-BwWindowsArg '') -ceq '""') 'Empty argument preserved'
Assert-Bw ((ConvertTo-BwWindowsArg 'C:\With Space\') -ceq '"C:\With Space\\"') 'Quoted argument preserves trailing slash'
Assert-Bw ((ConvertTo-BwWindowsArg 'contains "quote"') -ceq '"contains \"quote\""') 'Embedded quote is escaped'
$fixture='https://www.youtube.com/watch?v=7&list=42'
$urls = @(Get-BwLinks " `n$fixture`r`n$fixture`nhttps://example.org/second")
Assert-Bw ($urls.Count -eq 2 -and $urls[0] -ceq $fixture) 'One URL per line, deduplicated, preserves query'
Assert-BwThrows { Get-BwLinks '--exec=whoami' } 'Argument-shaped input is rejected'
Assert-BwThrows { Get-BwLinks 'file:///C:/Windows/secret.txt' } 'Local-file scheme is rejected'
Assert-BwThrows { Get-BwLinks 'https://user:password@example.org/private' } 'Embedded credentials are rejected'
Assert-BwThrows { Get-BwLinks 'https://example.org/watch a' } 'Whitespace within URLs is rejected'
Assert-Bw ((Get-BwLanguages 'en, pt-BR, en') -eq '(?i:en(?:-[a-z0-9]+)*),(?i:pt-br)') 'Caption language list and regional matching'
Assert-Bw ((Get-BwLanguages 'all') -eq 'all,-live_chat') 'All languages excludes live chat'
Assert-BwThrows { Get-BwLanguages 'en,.*' } 'Invalid caption pattern is rejected'
$body = @'
WEBVTT

00:00:00.000 --> 00:00:01.200
<c>One &amp; two</c>

00:00:01.200 --> 00:00:02.300
One &amp; two three

00:00:02.300 --> 00:00:04.000
Four o'clock.
'@
$parsed = (ConvertFrom-BwTranscript $body).TrimEnd() -replace '\r',''
Assert-Bw ($parsed -ceq "One & two`nthree`nFour o'clock.") 'Plain transcript strips timings/markup and overlapping rolling captions'
Assert-Bw ((ConvertFrom-BwTranscript 'Empty subtitle track') -eq '') 'Empty caption tracks are not mistaken for transcripts'
$job=[pscustomobject]@{
    Url=$fixture; Scope='single'; Height=1080; AudioQuality='192K'; AutoCaptions=$true
    Languages=(Get-BwLanguages 'en'); Modes=@('MP4','MP3','Captions'); CaptionFormat='Both'
}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('Blackwake QA & ' + [guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($tmp)
try {
    $ff = if ($Ffmpeg) { $Ffmpeg } else { Join-Path $tmp 'ffmpeg.exe' }
    $tools=@{'ffmpeg'=$ff; 'deno'=(Join-Path $tmp 'deno.exe'); 'yt-dlp'=$YtDlp}
    $argsVideo=@(New-BwArguments $job 'MP4' $tools)
    Assert-Bw (($argsVideo -contains '--no-playlist') -and ($argsVideo -contains '--playlist-items') -and ($argsVideo -match 'height<=1080').Count -eq 1) 'Single-item and video-resolution switches are wired'
    Assert-Bw ($argsVideo[-2] -eq '--' -and $argsVideo[-1] -ceq $fixture) 'Untrusted URL is passed after option terminator'
    $job.Scope='collection'
    $argsAudio=@(New-BwArguments $job 'MP3' $tools)
    Assert-Bw (($argsAudio -contains '--yes-playlist') -and ($argsAudio -notcontains '--playlist-items') -and ($argsAudio -contains '192K')) 'Collection audio has no single-item limit'
    $argsText=@(New-BwArguments $job 'Captions' $tools)
    Assert-Bw (($argsText -contains '--skip-download') -and ($argsText -contains '--write-auto-subs') -and ($argsText -contains '--convert-subs')) 'Transcript mode does not download media'
    $job.AutoCaptions=$false
    Assert-Bw ((New-BwArguments $job 'Captions' $tools) -notcontains '--write-auto-subs') 'Auto captions can be switched off'
    $file=Join-Path $tmp 'saved.txt'
    Write-BwTextFile $file "résumé"
    Write-BwTextFile $file 'must not overwrite'
    Assert-Bw (([IO.File]::ReadAllText($file)) -ceq 'résumé') 'UTF-8 transcript writes never overwrite an existing file'
    Assert-Bw ((Get-BwContainedFile $file $tmp) -eq $file -and !(Get-BwContainedFile $file (Join-Path $tmp 'unrelated'))) 'Reported files are constrained to the job destination'
    Assert-Bw ((Get-BwContainedFile 'saved.txt' $tmp) -eq $file -and !(Get-BwContainedFile '../saved.txt' $tmp)) 'Relative reported paths stay inside the job destination'
    $token=[Threading.CancellationTokenSource]::new()
    try {
        $shell=[Diagnostics.Process]::GetCurrentProcess()
        try { $hostExe=$shell.MainModule.FileName } finally { $shell.Dispose() }
        $token.CancelAfter(950)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $exit=Invoke-BwProcess $hostExe @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 25') { param($Line,$IsError) } $token $tmp
        Assert-Bw ($exit -eq -999 -and $timer.Elapsed.TotalSeconds -lt 9) 'Stop interrupts a running child process'
    } finally { $token.Dispose() }
    $setupFile=Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-Tools.ps1'
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($setupFile,[ref]$null,[ref]$null)
    $entry=$ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Copy-BwZipTools'
    },$false)
    . ([scriptblock]::Create($entry.Extent.Text))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archivePath=Join-Path $tmp 'tools.zip'
    $zip=[IO.Compression.ZipFile]::Open($archivePath,'Create')
    try {
        foreach ($name in @('distribution/bin/ffmpeg.exe','distribution/bin/ffprobe.exe','../ignored.exe')) {
            $stream=$zip.CreateEntry($name).Open()
            try { $stream.WriteByte(127) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    Copy-BwZipTools $archivePath $tmp @('ffmpeg.exe','ffprobe.exe')
    Assert-Bw (([IO.File]::ReadAllBytes((Join-Path $tmp 'ffmpeg.exe'))[0] -eq 127) -and
        ([IO.File]::ReadAllBytes((Join-Path $tmp 'ffprobe.exe'))[0] -eq 127) -and
        !(Test-Path (Join-Path $tmp 'ignored.exe'))) 'Setup extracts only the requested tools from a release archive'
    Assert-BwThrows { Copy-BwZipTools $archivePath $tmp @('deno.exe') } 'Setup rejects a release archive missing a required executable'
    if ($YtDlp -and $FixtureUrl -and $Ffmpeg) {
        $job | Add-Member -NotePropertyName Destination -NotePropertyValue $tmp
        $job.Scope='single'; $job.Url=$FixtureUrl
        $events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $token=[Threading.CancellationTokenSource]::new()
        try {
            Invoke-BwJob $job $tools $events $token
            $list=$events.ToArray()
            $list | Where-Object Kind -eq log | ForEach-Object { Write-Host $_.Data }
            $done=($list | Where-Object Kind -eq done).Data
            $files=@($list | Where-Object Kind -eq file | ForEach-Object { $_.Data })
            Assert-Bw ($done.Status -eq 'Complete' -and $done.Files -eq 4) 'Real yt-dlp and FFmpeg job produced all four expected files'
            Assert-Bw ((@($list | Where-Object Kind -eq progress)).Count -gt 0) 'Real yt-dlp emitted structured progress'
            Assert-Bw ((@($list | Where-Object Kind -eq processing)).Count -gt 0) 'Real yt-dlp emitted structured post-processing'
            $ports=@($list | Where-Object Kind -eq port | ForEach-Object { $_.Data })
            Assert-Bw (($ports.Mode -join ',') -ceq 'MP4,MP3,Captions') 'Media, audio and captions emit separate voyage encounters'
            $lifecycle=@($list | Where-Object Kind -in @('port','port-done') | ForEach-Object Kind)
            Assert-Bw (($lifecycle -join ',') -ceq 'port,port-done,port,port-done,port,port-done') 'Every reported encounter has matching start and completion'

            foreach ($ext in @('mp4','mp3','srt','txt')) { Assert-Bw (($files -like "*.$ext").Count -eq 1) "Real job saved .$ext" }
            Assert-Bw (([IO.File]::ReadAllText(($files -like '*.txt')[0])) -match 'Bring the haul home') 'Real saved transcript contains subtitle text'
        } finally { $token.Dispose() }
        $testRoot=Join-Path $tmp 'Separate tests'
        $job.Destination=$testRoot; $job.Modes=@('Captions'); $job.CaptionFormat='TXT'
        $events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $token=[Threading.CancellationTokenSource]::new()
        try {
            $worker=[PowerShell]::Create()
            try {
                $null=$worker.AddScript({
                    param($engine,$job,$tools,$events,$token)
                    . $engine
                    Invoke-BwJob $job $tools $events $token
                }.ToString()).AddArgument((Join-Path (Split-Path -Parent $PSScriptRoot) 'Engine.ps1')).AddArgument($job).AddArgument($tools).AddArgument($events).AddArgument($token)
                $null=$worker.EndInvoke($worker.BeginInvoke())
                Assert-Bw (!$worker.HadErrors) 'Background runspace can invoke the real engine'
            } finally { $worker.Dispose() }
            $list=$events.ToArray()
            Assert-Bw ((($list | Where-Object Kind -eq done).Data).Status -eq 'Complete' -and (Get-ChildItem $testRoot -Recurse -File).Extension -eq '.txt') 'TXT-only run keeps no video, audio, or SRT'
            while (!$events.IsEmpty) { [object]$discard=$null; $null=$events.TryDequeue([ref]$discard) }
            $job.Languages=Get-BwLanguages 'ja'
            Invoke-BwJob $job $tools $events $token
            Assert-Bw ((($events.ToArray() | Where-Object Kind -eq done).Data).Status -eq 'No captions') 'Unavailable caption language is not reported as successful'
            if ($CollectionUrl) {
                while (!$events.IsEmpty) { [object]$discard=$null; $null=$events.TryDequeue([ref]$discard) }
                $job.Destination=Join-Path $tmp 'Collection test'; $job.Modes=@('MP3'); $job.Scope='collection'; $job.Url=$CollectionUrl
                Invoke-BwJob $job $tools $events $token
                $list=$events.ToArray()
                $list | Where-Object Kind -eq log | ForEach-Object { Write-Host $_.Data }
                Assert-Bw ((($list | Where-Object Kind -eq done).Data).Status -eq 'Complete' -and (@($list | Where-Object Kind -eq file)).Count -eq 2) 'A real two-entry playlist is downloaded in full as MP3'
                $ports=@($list | Where-Object Kind -eq port | ForEach-Object { $_.Data })
                Assert-Bw (($ports | ForEach-Object Index) -join ',' -eq '1,2') 'Two real playlist items deliver ordered port events'
                Assert-Bw (($ports | ForEach-Object Count) -join ',' -eq '2,2') 'Playlist totals reach the voyage captions'
                while (!$events.IsEmpty) { [object]$discard=$null; $null=$events.TryDequeue([ref]$discard) }
                $job.Destination=Join-Path $tmp 'Collection wait test'
                $job.Modes=@('MP4','MP3','Captions')
                $job.Languages=Get-BwLanguages 'en'
                $script:fixtureEngineArguments=(Get-Command New-BwArguments).ScriptBlock
                function New-BwArguments($Job,[string]$Mode,$Tools) {
                    $argsList=@(& $script:fixtureEngineArguments $Job $Mode $Tools)
                    return @('--sleep-interval','1') + $argsList
                }
                Invoke-BwJob $job $tools $events $token
                $list=$events.ToArray()
                $list | Where-Object Kind -eq log | ForEach-Object { Write-Host $_.Data }
                $ports=@($list | Where-Object Kind -eq port | ForEach-Object { $_.Data })
                Assert-Bw (($ports.Mode -join ',') -ceq 'MP4,MP4,MP3,MP3,Captions,Captions') "A two-item collection gives each video, audio and transcript its own scene (observed: $($ports.Mode -join ','))"
                Assert-Bw ((@($list | Where-Object Kind -eq source-wait)).Count -ge 4) 'Real yt-dlp sleep messages emit voyage wait events'
                Assert-Bw (((@($list | Where-Object Kind -eq source-wait))[0]).Data.Seconds -eq 1) 'The actual source delay, not a hard-coded timer, is forwarded'

            }
            while (!$events.IsEmpty) { [object]$discard=$null; $null=$events.TryDequeue([ref]$discard) }
            $token.Cancel()
            Invoke-BwJob $job $tools $events $token
            Assert-Bw ((($events.ToArray() | Where-Object Kind -eq done).Data).Status -eq 'Cancelled') 'A cancelled job does not begin another transfer'
        } finally { $token.Dispose() }
    }
} finally { [IO.Directory]::Delete($tmp,$true) }
Write-Host "$script:Checks checks passed."
