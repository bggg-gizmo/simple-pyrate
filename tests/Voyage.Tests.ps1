Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'VoyageTimeline.cs')
$script:Checks=0
function Require([bool]$Condition,[string]$Label) {
    if (!$Condition) { throw "FAIL: $Label" }
    $script:Checks++
    Write-Output "PASS: $Label"
}
function Step($Timeline,[double]$Seconds,[bool]$Motion=$true) { return $Timeline.Tick($Seconds,$Motion) }
$sea=[Pyrate.VoyageTimeline]::new()
$idle=Step $sea 0
Require ($idle.Shot -eq 'Harbor' -and $idle.Headline -ceq 'Ready to download' -and $idle.Detail -ceq 'Paste a link to start a download') 'Idle deck opens at harbor with download instructions'
$sea.Start(0)
Require ((Step $sea .4).Headline -eq 'Setting sail') 'A new haul begins with the departure shot'
$sea.BeginWait(.5,3,'Source-requested pause')
$sea.EnterPort('MP4','The first port','Item 1 of 3')
$shot=Step $sea 1.7
Require ($shot.Shot -eq 'OpenSea' -and $shot.Headline -eq 'Riding out the wait' -and $shot.WaitRemaining -gt 1) 'A source wait before the first item keeps the ship at sea'
$shot=Step $sea 3.2
Require ($shot.Shot -eq 'OpenSea' -and $shot.Detail -match '1s$') 'The sailing overlay counts down the actual wait'
$sea.SignalActivity()
$shot=Step $sea 3.25
Require ($shot.Shot -eq 'Battle' -and $shot.Port -eq 1 -and $shot.Mode -eq 'MP4' -and $shot.Headline -eq 'Plundering in progress') 'The first media transfer has its own numbered battle'
$sea.BeginWait(3.4,2,'Source-requested pause')
$shot=Step $sea 3.8
Require ($shot.Shot -eq 'OpenSea' -and $shot.Port -eq 1 -and $shot.WaitRemaining -gt 0) 'A delay during a transfer cuts back to sailing without inventing another port'
$sea.SignalActivity()
$shot=Step $sea 3.9
Require ($shot.Shot -eq 'Battle' -and $shot.Port -eq 1 -and $sea.PortsObserved -eq 1) 'The same port resumes when transfer activity returns'
$sea.ResolvePort()
$sea.EnterPort('MP3','The second port','Item 2 of 3')
$sea.ResolvePort()
$sea.EnterPort('Captions','The third port','Item 3 of 3')
$sea.ResolvePort()
$sea.Finish(4.1,'Complete',$false)
$shots=@(for($t=4.2; $t -lt 15.0; $t+=.07) { Step $sea $t })
Require ((@($shots | Where-Object Shot -eq 'Return')).Count -gt 0) 'Return plays only after the last queued scene'
$sequence=@($shots | Where-Object Shot -eq 'Battle' | ForEach-Object Port | Select-Object -Unique)
Require (($sequence -join ',') -eq '1,2,3') 'Fast successive media, audio and transcript events still show every port in order'
$port3=$shots | Where-Object { $_.Shot -eq 'Battle' -and $_.Port -eq 3 } | Select-Object -First 1
Require ($port3.Mode -eq 'Transcript' -and $port3.Detail -match 'Item 3 of 3') 'Transcript battles retain their own item label'
$between=@($shots | Where-Object { $_.Shot -eq 'OpenSea' -and $_.Headline -eq 'On to the next port' })
Require ($between.Count -gt 0 -and (Step $sea 15).Headline -eq 'Back at anchor') 'Open water separates battles and the final destination is the lagoon'
$sea.Start(16)
Require ((Step $sea 16.1).Shot -eq 'Departure' -and $sea.PortsObserved -eq 0) 'A new voyage restarts port numbering from the lagoon'
$sea.EnterPort('MP3','First of two queue jobs','')
$sea.Finish(16.2,'Complete',$true)
$sea.Start(16.3)
$sea.EnterPort('MP3','Second of two queue jobs','')
$sea.Finish(16.4,'Complete',$false)
$shots=@(for($t=16.5; $t -lt 26; $t+=.083) { Step $sea $t })
Require (((@($shots | Where-Object Shot -eq 'Battle' | ForEach-Object Port | Select-Object -Unique)) -join ',') -eq '1,2') 'Multiple queued links share the same voyage'
$b1=[Array]::FindIndex([object[]]$shots,[Predicate[object]]{param($f) $f.Shot -eq 'Battle' -and $f.Port -eq 2})
$ret=[Array]::FindIndex([object[]]$shots,[Predicate[object]]{param($f) $f.Shot -eq 'Return'})
Require ($b1 -ge 0 -and $ret -gt $b1) 'The ship does not return between queued links'
$sea.Start(30)
$sea.EnterPort('MP4','Abandoned port','')
$sea.EnterPort('MP4','Discarded visual backlog','')
$sea.Finish(30.3,'Cancelled',$false)
Require ((Step $sea 30.4).Headline -eq 'Turning for harbor' -and $sea.Backlog -eq 0) 'Cancellation returns immediately and drops replay-only battle backlog'
$sea.Start(40)
$sea.EnterPort('Captions','Reduced motion cargo','')
$sea.SignalActivity()
Require ((Step $sea 40 $false).Shot -eq 'Battle') 'Motion off jumps directly to a still frame'
$sea.Finish(40.1,'Complete',$false)
Require ((Step $sea 40.1 $false).Headline -eq 'Back at anchor' -and !$sea.NeedsClock) 'Motion off skips the return animation without delaying completion'
$sea.Start(50)
$sea.EnterPort('MP4','Single fast item','')
$sea.ResolvePort()
$sea.Finish(50.01,'Complete',$false)
$sequence=@(for($t=50; $t -lt 58; $t+=.11) { Step $sea $t })
Require (((@($sequence | ForEach-Object Shot | Select-Object -Unique)) -join ',') -eq 'Departure,OpenSea,Battle,Return,Harbor') 'An instant single download still plays the full scene sequence'
$sea.Start(60)
$sea.EnterPort('MP4','Awaiting the transfer','')
$null=Step $sea 62
Require ((Step $sea 63).Shot -eq 'OpenSea') 'A resolved title alone does not launch cannon fire before transfer activity'
$sea.SignalActivity()
Require ((Step $sea 63.1).Shot -eq 'Battle') 'Progress opens the battle while the item is still active'
$handoff=[Pyrate.VoyageTimeline]::new()
$handoff.Start(0)
$handoff.EnterPort('MP4','First coastal port','')
$handoff.ResolvePort($true)
$handoff.EnterPort('MP4','Next coastal port','')
$handoff.ResolvePort($true)
$handoff.Finish(.1,'Complete',$false)
$record=@(for($t=0.0;$t -lt 23.0;$t+=.033) { Step $handoff $t })
$cross=@($record | Where-Object { $_.Shot -eq 'OpenSea' -and $_.DepartingPort -eq 1 })
Require ($cross.Count -gt 3 -and $cross[0].PassingCoastX -eq 0 -and $cross[-1].PassingCoastX -lt -1200) 'The first port slides completely off the left edge before the next port'
Require ((@($cross | Where-Object DepartingRaidStage -ne 6)).Count -eq 0) 'A departing port keeps its final damage instead of reverting to an intact port'
$approach=@($record | Where-Object { $_.Shot -eq 'Battle' -and $_.Port -eq 2 -and $_.Age -lt .7 })
Require ($approach.Count -gt 3 -and $approach[0].PassingCoastX -eq 480 -and $approach[-1].PassingCoastX -eq 0) 'The next coastline arrives from the right and settles naturally'
foreach ($leg in @($cross,$approach)) {
    for ($i=1;$i -lt $leg.Count;$i++) {
        if ($leg[$i].PassingCoastX -gt $leg[$i-1].PassingCoastX) { throw 'The coastal camera reversed direction.' }
    }
}
Require $true 'Both coastlines move left in the same forward sailing direction'
Require ((@($record | Where-Object Shot -eq 'Return'))[0].Port -eq 2) 'Only the final encounter sends the ship home'
$paused=[Pyrate.VoyageTimeline]::new()
$paused.Start(0)
$paused.EnterPort('MP4','Delayed coastal port','')
$paused.SignalActivity()
$null=Step $paused 1.66
Require ((Step $paused 2.27).Shot -eq 'Battle') 'A transfer enters its port before a source wait'
$paused.BeginWait(2.9,2,'Source hold')
$during=Step $paused 3.05
Require ($during.Shot -eq 'OpenSea' -and $during.DepartingPort -eq 1 -and $during.PassingCoastX -lt 0) 'Source waits also exit a port in the forward direction'
$paused.SignalActivity()
Require ((Step $paused 3.4).Port -eq 1 -and $paused.PortsObserved -eq 1) 'A source hold never invents another numbered port'
Write-Output "$script:Checks voyage checks passed."
