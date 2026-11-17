param([switch]$Playback)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:AppRoot=Split-Path -Parent $PSScriptRoot
Add-Type -Path @((Join-Path $script:AppRoot 'ShipAudio.cs'),(Join-Path $script:AppRoot 'VoyageTimeline.cs'))
$script:SmokeTest=$false
$script:Sound=$null
$script:AudioLog=[Collections.Generic.List[string]]::new()
function Add-BwLog([string]$Text) { $script:AudioLog.Add($Text) }
. (Join-Path $script:AppRoot 'Shipwright.ps1')
$fx=@($script:PyrateEffects | ForEach-Object { Join-Path $script:AppRoot "assets/audio/$_.wav" })
$bells=@($script:PyrateBellAssets.Values | ForEach-Object { Join-Path $script:AppRoot "assets/audio/$_.wav" })
$sea=Join-Path $script:AppRoot 'assets/Night-Sea.wav'
foreach ($path in ($fx+$bells+@($sea))) {
    if ([Pyrate.PcmVoice]::CheckRecording($path) -le 0) { throw "Empty recording: $path" }
}
Write-Output 'PASS: 11 shipped WAVs are valid PCM'
if (!$Playback) { exit 0 }

try {
    $script:PyrateEffectsOn=$true
    $script:PyrateEffectsVolume=50
    $script:Sound=[Pyrate.PcmVoice]::new($sea, 1, $true)
    Start-Sleep -Milliseconds 125
    if ($script:Sound.Ended) { throw "Ambience could not start: $($script:Sound.Failure)" }
    Play-PyrateEffect 0
    Queue-PyrateBell Port
    if ($script:PyrateEffectPlayers.Count -ne 1 -or !$script:PyrateBellPlayer) {
        throw ('The effect or bell was not queued. ' + ($script:AudioLog -join ' / '))
    }
    $effect=$script:PyrateEffectPlayers[0]
    $bell=$script:PyrateBellPlayer
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 30
        Update-PyrateAudio
    } while (($script:PyrateEffectPlayers.Count -or $script:PyrateBellPlayer) -and $deadline.Elapsed.TotalSeconds -lt 7)
    if (!$effect.Ended -or !$bell.Ended -or $effect.Failure -or $bell.Failure -or !$script:Sound -or $script:Sound.Ended -or $script:AudioLog.Count) {
        throw ('Sound completion failed. ' + ($script:AudioLog -join ' / '))
    }
    Write-Output 'PASS: ambient loop, cannon effect, and port bell completed concurrently through the shared output'
    $script:PyrateEffectsOn=$false
    Play-PyrateEffect 0
    Queue-PyrateBell Port
    if ($script:PyrateEffectPlayers.Count -or $script:PyrateBellPlayer -or $script:Sound.Ended) { throw 'SFX mute affected the wrong voices' }
    Write-Output 'PASS: muting effects does not stop the ambient loop'
} finally {
    Stop-PyrateEffects
    Stop-PyrateBells
    if ($script:Sound) { $script:Sound.Dispose() }
    Start-Sleep -Milliseconds 100
}
