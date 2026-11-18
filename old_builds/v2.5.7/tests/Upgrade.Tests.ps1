param([string]$Ffmpeg,[string]$YtDlp,[string]$FixtureBase)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Engine.ps1')
Add-Type -Path (Join-Path $root 'VoyageTimeline.cs')
$script:Checks=0
function Check($Condition,[string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $script:Checks++
    "PASS: $Name"
}

$bell=[Pyrate.ShipBellPlan]::new()
Check ($bell.BeginJob($false,1,$false)) 'A single job signals one start bell'
Check (!$bell.EnterPort($false)) 'A single job does not signal a batch port bell'
Check ($bell.Finish($false,'Complete')) 'A finished single job signals the finish bell'
Check (!$bell.Finish($false,'Complete')) 'An already finished queue cannot ring twice'
Check ($bell.BeginJob($true,1,$false)) 'A collection signals its start bell'
Check ($bell.EnterPort($false) -and $bell.EnterPort($false)) 'Each item of a collection signals its own port bell'
Check (!$bell.Finish($true,'Complete')) 'An intermediate queued job cannot signal the finish bell'
Check (!$bell.BeginJob($false,1,$false)) 'The next queued job shares the same start bell'
Check ($bell.EnterPort($false)) 'Batch ports remain enabled across queued jobs'
Check ($bell.Finish($false,'Partial')) 'The final partial result still signals that the queue ended'
Check ($bell.BeginJob($false,2,$false) -and $bell.EnterPort($false)) 'Multiple selected outputs count as a batch'
Check (!$bell.Finish($false,'Cancelled')) 'A cancelled queue does not ring the finish bell'
Check ($bell.BeginJob($false,1,$true) -and $bell.EnterPort($false)) 'Multiple pasted links count as a batch'
Check ($bell.Finish($false,'Complete')) 'A new queue after cancellation can finish normally'
foreach ($fixture in @(@{Name='ship-bell-port'; Strikes=2},@{Name='ship-bell-start'; Strikes=3},@{Name='ship-bell-finish'; Strikes=5})) {
    $wave=[IO.File]::ReadAllBytes((Join-Path $root "assets\audio\$($fixture.Name).wav"))
    $frames=([int]$fixture.Strikes-1)*16317+45500
    Check (([Text.Encoding]::ASCII.GetString($wave,0,4) -ceq 'RIFF') -and
        ([Text.Encoding]::ASCII.GetString($wave,8,4) -ceq 'WAVE') -and
        ([BitConverter]::ToUInt16($wave,20) -eq 1) -and ([BitConverter]::ToUInt16($wave,22) -eq 1) -and
        ([BitConverter]::ToInt32($wave,24) -eq 22050) -and ([BitConverter]::ToUInt16($wave,34) -eq 16) -and
        ([BitConverter]::ToInt32($wave,40) -eq $frames*2) -and ($wave.Length -eq 44+$frames*2)) "$($fixture.Name) contains the expected $($fixture.Strikes)-strike PCM recording"
}

$seen=@{}
Check ((Get-BwTransferPercent 100 'video' @('video','audio') $seen) -eq 50) 'A downloaded video component alone does not finish split media'
Check ((Get-BwTransferPercent 50 'audio' @('video','audio') $seen) -eq 75) 'Split audio contributes to one shared transfer percentage'
Check ((Get-BwTransferPercent 10 'video' @('video','audio') $seen) -eq 75) 'Resumed components cannot rewind split-media progress'
Check ((Get-BwTransferPercent 100 'audio' @('video','audio') $seen) -eq 100) 'Both components finish the split-media transfer'
$stats=ConvertFrom-BwFfmpegProgress @{ out_time_us='42000000'; speed='2.0x' } 60
Check ($stats.Percent -eq 70 -and $stats.MediaSeconds -eq 42 -and $stats.EtaSeconds -eq 9) 'FFmpeg timestamp, speed and ETA are parsed'
$stats=ConvertFrom-BwFfmpegProgress @{ out_time_us='N/A'; speed='N/A' } 0
Check ($null -eq $stats.Percent -and $null -eq $stats.EtaSeconds) 'Unknown conversion duration never invents percentages or an ETA'
$stats=ConvertFrom-BwFfmpegProgress @{ out_time_us='65000000'; speed='1.0x' } 60
Check ($stats.Percent -lt 100 -and $stats.EtaSeconds -eq 0) 'FFmpeg stays below 100% until the output is moved'

$voyage=[Pyrate.VoyageTimeline]::new(); $voyage.Start(0)
$voyage.EnterPort('MP4','Coast','Item 1 of 2'); $voyage.SignalActivity()
$shot=$voyage.Tick(0,$false)
Check ($shot.RaidPercent -eq 0) 'New ports start without prior damage'
for($i=1;$i -le 6;$i++){
    $threshold=[Pyrate.VoyageTimeline]::MilestonePercent($i)
    $voyage.ReportProgress($threshold-.1)
    Check ($voyage.Tick($i,$false).RaidStage -eq ($i-1)) "Port stage does not trigger early at $threshold%"
    $voyage.ReportProgress($threshold)
    Check ($voyage.Tick($i+.01,$false).RaidPercent -eq $threshold) "Port stage triggers at $threshold%"
}
$voyage.ReportProgress(42)
Check ($voyage.Tick(7,$false).RaidPercent -eq 98) 'Previous damage and cargo phases do not rewind'
$voyage.ResolvePort($true); $voyage.EnterPort('Captions','Second port','Item 2 of 2'); $voyage.SignalActivity()
Check ($voyage.Tick(8,$false).RaidPercent -eq 0) 'Each output item gets an independent port state'
$voyage.ResolvePort($false); $voyage.Finish(8.1,'No captions',$false)
Check ($voyage.Tick(8.1,$false).Shot -eq 'Harbor') 'Missing captions do not delay return for the raid finale in reduced motion'
$voyage=[Pyrate.VoyageTimeline]::new(); $voyage.Start(0)
$voyage.EnterPort('MP3','Fast cargo',''); $voyage.ResolvePort($true); $voyage.Finish(.05,'Complete',$false)
$frames=@(for($t=0.0;$t -lt 15;$t+=.08){$voyage.Tick($t,$true)})
$beats=@($frames | Where-Object Shot -eq 'Battle' | ForEach-Object RaidPercent | Select-Object -Unique)
Check (($beats -join ',') -eq '0,30,50,75,80,95,98') 'An instant caption, audio or video save still replays every reached raid beat'
Check ($frames[-1].Shot -eq 'Harbor') 'The raid encore still returns to harbor'

if ($Ffmpeg) {
    $tmp=Join-Path ([IO.Path]::GetTempPath()) ('Pyrate remux QA '+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($tmp)
    $tools=@{ffmpeg=$Ffmpeg; ffprobe=(Join-Path (Split-Path -Parent $Ffmpeg) $(if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'ffprobe.exe' } else { 'ffprobe' })); 'yt-dlp'=$YtDlp; deno=$null}
    $token=[Threading.CancellationTokenSource]::new()
    try {
        foreach ($case in @(@{ Name='remux.mkv'; Video='libx264'; Audio='aac'; Operation='MP4 remux (no re-encode)' },
            @{ Name='audio.mkv'; Video='libx264'; Audio='libopus'; Operation='MP4 audio encode (video copied)' },
            @{ Name='encode.webm'; Video='libvpx-vp9'; Audio='libopus'; Operation='MP4 video encode' })) {
            $source=Join-Path $tmp $case.Name
            & $Ffmpeg -nostdin -v error -f lavfi -i 'testsrc2=s=320x180:r=24:d=2' -f lavfi -i 'sine=frequency=430:duration=2' -c:v $case.Video -c:a $case.Audio -shortest $source
            if ($LASTEXITCODE) { throw "Could not produce $source" }
            $events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
            $final=Invoke-BwMp4Finalization $source $tmp $case.Name $tools $events $token
            $items=$events.ToArray()
            Check ((Test-Path -LiteralPath $final) -and !(Test-Path -LiteralPath $source)) "$($case.Name) finalized as MP4"
            $operation=@($items | Where-Object Kind -eq 'processing' | ForEach-Object { $_.Data.Operation } | Where-Object { $_ -ne 'MP4 stream inspection' })
            Check ($operation[0] -eq $case.Operation) "$($case.Name) chooses the right FFmpeg path"
            $progress=@($items | Where-Object Kind -eq 'convert-progress')
            Check ($progress.Count -gt 0 -and $progress[-1].Data.MediaSeconds -gt 0) "$($case.Name) reports actual FFmpeg media time"
            $streams=& $tools.ffprobe -v error -show_entries stream=codec_name -of csv=p=0 $final
            Check ($LASTEXITCODE -eq 0 -and $streams -contains 'h264' -and $streams -contains 'aac') "$($case.Name) produces readable H.264/AAC"
        }
        $source=Join-Path $tmp 'broken.webm'
        [IO.File]::WriteAllText($source,'not a media file')
        $failure=$false
        try { $null=Invoke-BwMp4Finalization $source $tmp 'broken' $tools $events $token } catch { $failure=$true }
        Check ($failure -and (Test-Path -LiteralPath $source) -and !(Test-Path (Join-Path $tmp 'broken.mp4'))) 'Failed FFmpeg conversion preserves the input and publishes no final MP4'
        Check ((@(Get-ChildItem -LiteralPath $tmp -Filter '.pyrate-*.mp4' -Force)).Count -eq 0) 'FFmpeg staging files are cleaned up after success and failure'
        if ($YtDlp -and $FixtureBase) {
            $job=[pscustomobject]@{ Url="$FixtureBase/encode.html"; Scope='single'; Height=480; Destination=$tmp; Modes=@('MP4') }
            $events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
            Invoke-BwJob $job $tools $events $token
            $items=$events.ToArray()
            if (($items | Where-Object Kind -eq done).Data.Status -ne 'Complete') { $items | Where-Object Kind -eq log | ForEach-Object { $_.Data } }
            Check (($items | Where-Object Kind -eq done).Data.Status -eq 'Complete') 'Real yt-dlp WebM input completes through the queue as MP4'
            $conversionIndex=[array]::FindIndex($items,[Predicate[object]]{param($e)$e.Kind -eq 'convert-progress'})
            $portEndIndex=[array]::FindIndex($items,[Predicate[object]]{param($e)$e.Kind -eq 'port-done'})
            Check ($conversionIndex -ge 0 -and $portEndIndex -gt $conversionIndex -and $items[$portEndIndex].Data.Saved) 'Real conversion remains associated with its port until the file is saved'
        }
        $existing=Join-Path $tmp 'existing.mp4'
        $source=Join-Path $tmp 'existing.webm'
        [IO.File]::WriteAllText($existing,'keep this file')
        [IO.File]::WriteAllText($source,'keep this source')
        Check ((Invoke-BwMp4Finalization $source $tmp 'existing' $tools $events $token) -eq $existing -and
            [IO.File]::ReadAllText($existing) -eq 'keep this file' -and [IO.File]::ReadAllText($source) -eq 'keep this source') 'An existing MP4 and its input are left untouched'

        $source=Join-Path $tmp 'cancel-during-encode.webm'
        & $Ffmpeg -nostdin -v error -f lavfi -i 'testsrc2=s=320x180:r=24:d=4' -c:v libvpx-vp9 $source
        if ($LASTEXITCODE) { throw 'Could not create the cancellation fixture' }
        $script:RealPyrateInvoke=(Get-Command Invoke-BwProcess).ScriptBlock
        function Invoke-BwProcess($Exe,$Arguments,$HandleLine,$Cancel,$WorkingDirectory,$TimeoutSeconds=0) {
            if ($Exe -eq $Ffmpeg -and $Arguments -contains '-progress') {
                $inputIndex=[array]::IndexOf($Arguments,'-i')
                $Arguments=@($Arguments[0..($inputIndex-1)])+@('-re')+@($Arguments[$inputIndex..($Arguments.Count-1)])
                $Cancel.CancelAfter(1400)
            }
            & $script:RealPyrateInvoke $Exe $Arguments $HandleLine $Cancel $WorkingDirectory $TimeoutSeconds
        }
        $events=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $finished=Invoke-BwMp4Finalization $source $tmp 'cancel during encode' $tools $events $token
        Check ($null -eq $finished -and $token.IsCancellationRequested -and [IO.File]::Exists($source) -and
            !(Test-Path (Join-Path $tmp 'cancel-during-encode.mp4'))) 'Stopping an active real encode leaves the source and saves no incomplete MP4'
        Check ((@(Get-ChildItem -LiteralPath $tmp -Filter '.pyrate-*.mp4' -Force)).Count -eq 0) 'Cancelling FFmpeg removes staged partial output'
        $source=Join-Path $tmp 'cancel.mkv'
        [IO.File]::WriteAllText($source,'input held on cancellation')
        Check ($null -eq (Invoke-BwMp4Finalization $source $tmp 'cancelled' $tools $events $token) -and [IO.File]::Exists($source)) 'Cancelled finalization leaves the source intact'
    } finally { $token.Dispose(); [IO.Directory]::Delete($tmp,$true) }
}

foreach ($test in @(
    @{ File='Shipwright.ps1'; Find='function Install-PyrateUserCopy' },
    @{ File='SimplePyrate.ps1'; Find='[System.Windows.Markup.IQueryAmbient].Assembly.Location' },
    @{ File='Start-Simple-Pyrate.cmd'; Find='-SetupWizard' })) {
    Check ([IO.File]::ReadAllText((Join-Path $root $test.File)).Contains($test.Find)) "$($test.File) retains the startup or setup integration"
}
$release=Get-BwAppVersion $root
Check ($release -ceq '2.5.7') 'This checkout identifies as Simple Pyrate 2.5.7'
Check (([IO.File]::ReadAllText((Join-Path $root 'Start-Simple-Pyrate.cmd'))).Contains('%~dp0VERSION')) 'Launcher checks release metadata beside the entry script'
Check (([IO.File]::ReadAllText((Join-Path $root 'Shipwright.ps1'))).Contains("'VERSION','Start-Simple-Pyrate.cmd'")) 'Per-user installer keeps the version metadata with the installed launcher'
"$script:Checks v$release checks passed."
