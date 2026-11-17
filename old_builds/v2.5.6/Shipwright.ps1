# Settings, sound deck, and first-run Shipyard wizard.
$script:PyrateMusicLists=@(
    @{ Label='Off'; Tracks=@() },
    @{ Label='Moonlit Watch'; Tracks=@('lagoon-watch','lantern-reach') },
    @{ Label='Corsair Run'; Tracks=@('the-black-tide','storm-corsairs') },
    @{ Label='All chart-room tracks'; Tracks=@('lagoon-watch','the-black-tide','lantern-reach','storm-corsairs') }
)
$script:PyrateMusicNames=@{
    'lagoon-watch'='Lagoon Watch'; 'lantern-reach'='Lantern Reach'
    'the-black-tide'='The Black Tide'; 'storm-corsairs'='Storm Corsairs'
}
$script:PyrateEffects=@('cannon','embers','boats','cargo','hoist','aboard','ruins')
$script:PyrateAddress='8AEyf8SfkYx6sHrLsp8aSAXrS8r9BZmnBfA6US9taa4mWpPXMNitipudPXU1MynA2mYHEXTsRZJik45gFjRsmeJ6HxRBEvn'
$script:PyrateMusicChoice=0
$script:PyrateMusicVolume=35
$script:PyrateEffectsOn=$true
$script:PyrateEffectsVolume=50
$script:PyrateWizardComplete=$false
$script:PyrateWizardLayoutRevision=4
$script:PyrateShortcut=$false
$script:PyrateTrackIndex=0
$script:PyrateMusicPlayer=$null
$script:PyrateEffectPlayers=[Collections.Generic.List[Pyrate.PcmVoice]]::new()
$script:PyrateEffectKey=''
$script:PyrateCannonKey=''
$script:PyrateBellPlan=[Pyrate.ShipBellPlan]::new()
$script:PyrateBellAssets=@{ Start='ship-bell-start'; Port='ship-bell-port'; Finish='ship-bell-finish' }
$script:PyrateBellQueue=[Collections.Generic.Queue[string]]::new()
$script:PyrateBellPlayer=$null
$script:PyrateMusicNow=$null
$script:PyrateSetupExit=$null
$script:PyrateWizardActive=$null

function New-PyrateDialogText($Panel,[string]$Text,[string]$Style='') {
    $block=[Windows.Controls.TextBlock]::new()
    $block.Text=$Text; $block.TextWrapping='Wrap'
    $block.Margin=[Windows.Thickness]::new(0,0,0,7)
    if ($Style) { $block.Style=$script:Deck.FindResource($Style) }
    $null=$Panel.Children.Add($block)
    return $block
}
function New-PyrateDialogCheck($Panel,[string]$Text,[bool]$Checked) {
    $box=[Windows.Controls.CheckBox]::new()
    $box.Content=$Text; $box.IsChecked=$Checked
    $box.Margin=[Windows.Thickness]::new(0,0,0,7)
    $null=$Panel.Children.Add($box)
    return $box
}
function New-PyrateDialogStack($Dialog) {
    $scroll=[Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility='Auto'
    $scroll.HorizontalScrollBarVisibility='Disabled'
    $body=[Windows.Controls.StackPanel]::new()
    $scroll.Content=$body
    $null=$Dialog.Body.Children.Add($scroll)
    return $body
}
function New-PyrateVolume($Panel,[string]$Label,[int]$Volume) {
    $null=New-PyrateDialogText $Panel $Label 'Small'
    $control=[Windows.Controls.Slider]::new()
    $control.Minimum=0; $control.Maximum=100; $control.Value=$Volume
    $control.TickFrequency=5; $control.IsSnapToTickEnabled=$true
    $control.Margin=[Windows.Thickness]::new(0,0,0,10)
    [Windows.Automation.AutomationProperties]::SetName($control,$Label)
    $null=$Panel.Children.Add($control)
    return $control
}
function Set-PyrateMusic([bool]$Reset) {
    try {
        if ($Reset) { $script:PyrateTrackIndex=0 }
        if ($script:PyrateMusicChoice -eq 0) {
            if ($script:PyrateMusicPlayer) { $script:PyrateMusicPlayer.Close() }
            if ($script:PyrateMusicNow) { $script:PyrateMusicNow.Text='Music off' }
            return
        }
        if (!$script:PyrateMusicPlayer) {
            $script:PyrateMusicPlayer=[Windows.Media.MediaPlayer]::new()
            $script:PyrateMusicPlayer.add_MediaEnded({ $script:PyrateTrackIndex++; Set-PyrateMusic $false })
            $script:PyrateMusicPlayer.add_MediaFailed({
                param($sender,$e)
                Add-BwLog "Playlist playback failed: $($e.ErrorException.Message)"
                if ($script:PyrateMusicNow) { $script:PyrateMusicNow.Text='Audio unavailable. See the ship''s log.' }
            })
        }
        $tracks=$script:PyrateMusicLists[$script:PyrateMusicChoice].Tracks
        $script:PyrateTrackIndex=$script:PyrateTrackIndex % $tracks.Count
        $track=$tracks[$script:PyrateTrackIndex]
        $player=$script:PyrateMusicPlayer
        $player.Close(); $player.Volume=$script:PyrateMusicVolume/100.0
        $player.Open([uri](Join-Path $script:AppRoot "assets\audio\$track.mp3")); $player.Play()
        if ($script:PyrateMusicNow) { $script:PyrateMusicNow.Text="Now playing  /  $($script:PyrateMusicNames[$track])" }
    } catch { Add-BwLog "Could not start playlist: $($_.Exception.Message)" }
}
function Close-PyrateEffect([Pyrate.PcmVoice]$Player) {
    if ($Player -and $script:PyrateEffectPlayers.Remove($Player)) {
        try { $Player.Dispose() } catch { Add-BwLog "Port audio cleanup failed: $($_.Exception.Message)" }
    }
}
function Stop-PyrateEffects {
    foreach ($player in $script:PyrateEffectPlayers.ToArray()) { Close-PyrateEffect $player }
}
function Play-PyrateEffect([int]$Index) {
    if (!$script:PyrateEffectsOn -or $script:PyrateEffectsVolume -le 0 -or $script:SmokeTest) { return }
    $player=$null
    $name=$script:PyrateEffects[$Index]
    try {
        if ($script:PyrateEffectPlayers.Count -ge 12) { Close-PyrateEffect $script:PyrateEffectPlayers[0] }
        $path=Join-Path $script:AppRoot "assets\audio\$name.wav"
        $player=[Pyrate.PcmVoice]::new($path,($script:PyrateEffectsVolume/100.0),$false)
        $script:PyrateEffectPlayers.Add($player)
    } catch {
        Close-PyrateEffect $player
        Add-BwLog "Could not play port sound '$name': $($_.Exception.Message)"
    }
}
function Stop-PyrateBells {
    $script:PyrateBellQueue.Clear()
    $player=$script:PyrateBellPlayer
    $script:PyrateBellPlayer=$null
    if ($player) {
        try { $player.Dispose() } catch { Add-BwLog "Ship bell cleanup failed: $($_.Exception.Message)" }
    }
}
function Start-PyrateBellPlayback {
    if ($script:PyrateBellPlayer -or !$script:PyrateBellQueue.Count) { return }
    if (!$script:PyrateEffectsOn -or $script:PyrateEffectsVolume -le 0 -or $script:SmokeTest) {
        Stop-PyrateBells
        return
    }
    $name=$script:PyrateBellQueue.Dequeue()
    try {
        $path=Join-Path $script:AppRoot "assets\audio\$name.wav"
        $script:PyrateBellPlayer=[Pyrate.PcmVoice]::new($path,($script:PyrateEffectsVolume/100.0),$false)
    } catch {
        Stop-PyrateBells
        Add-BwLog "Could not play ship bell: $($_.Exception.Message)"
    }
}
function Update-PyrateAudio {
    foreach ($voice in $script:PyrateEffectPlayers.ToArray()) {
        if ($voice.Ended) { Close-PyrateEffect $voice }
    }
    $bell=$script:PyrateBellPlayer
    if ($bell -and $bell.Ended) {
        $script:PyrateBellPlayer=$null
        try { $bell.Dispose() } catch { Add-BwLog "Ship bell cleanup failed: $($_.Exception.Message)" }
        Start-PyrateBellPlayback
    }
}
function Queue-PyrateBell([ValidateSet('Start','Port','Finish')][string]$Cue) {
    if (!$script:PyrateEffectsOn -or $script:PyrateEffectsVolume -le 0 -or $script:SmokeTest) { return }
    $script:PyrateBellQueue.Enqueue($script:PyrateBellAssets[$Cue])
    Start-PyrateBellPlayback
}
function Update-PyrateRaidSound($Frame) {
    if ($Frame.Shot -ne [Pyrate.Shot]::Battle) { return }
    if ($Frame.RaidStage -lt 2 -and $Frame.RaidSceneAge -ge .13) {
        $cue=[int][Math]::Floor(($Frame.RaidSceneAge-.13)/2.7)
        $cannon="$($Frame.Port)/$cue"
        if ($cannon -ne $script:PyrateCannonKey) {
            $script:PyrateCannonKey=$cannon
            Play-PyrateEffect 0
        }
    }
    if ($Frame.RaidStage -gt 0) {
        $stage="$($Frame.Port)/$($Frame.RaidStage)"
        if ($stage -ne $script:PyrateEffectKey) {
            $script:PyrateEffectKey=$stage
            Play-PyrateEffect $Frame.RaidStage
        }
    }
}
function New-PyrateSettings {
    $d=New-BwDialog 'Captain''s settings' 600 645
    $body=New-PyrateDialogStack $d
    $null=New-PyrateDialogText $body '01  /  SOUND DECK' 'Kicker'
    $null=New-PyrateDialogText $body 'Original pirate MIDI scores with offline playback. Sea sound stays independent.' 'Small'
    $choice=[Windows.Controls.ComboBox]::new()
    [Windows.Automation.AutomationProperties]::SetName($choice,'Background music playlist')
    foreach ($item in $script:PyrateMusicLists) { $null=$choice.Items.Add($item.Label) }
    $choice.SelectedIndex=$script:PyrateMusicChoice
    $choice.Margin=[Windows.Thickness]::new(0,0,0,7); $null=$body.Children.Add($choice)
    $nowText=New-PyrateDialogText $body 'Music off' 'Small'
    if ($script:PyrateMusicChoice -gt 0) {
        $currentTrack=$script:PyrateMusicLists[$script:PyrateMusicChoice].Tracks[$script:PyrateTrackIndex]
        $nowText.Text="Now playing  /  $($script:PyrateMusicNames[$currentTrack])"
    }
    $musicVol=New-PyrateVolume $body 'Music volume' $script:PyrateMusicVolume
    $effects=New-PyrateDialogCheck $body 'Port sound effects' $script:PyrateEffectsOn
    $effects.ToolTip='Controls port effects and the ship bell'
    $sfxVol=New-PyrateVolume $body 'Port effects volume' $script:PyrateEffectsVolume
    $soundTools=[Windows.Controls.WrapPanel]::new()
    $null=$body.Children.Add($soundTools)
    $next=New-BwDialogButton $soundTools 'Next track'
    $next.IsEnabled=($script:PyrateMusicChoice -gt 0)
    $test=New-BwDialogButton $soundTools 'Preview port sound'
    $test.IsEnabled=$script:PyrateEffectsOn
    $choice.Tag=$next; $effects.Tag=$test
    $choice.add_SelectionChanged({
        param($sender,$e)
        if ($sender.SelectedIndex -lt 0) { return }
        $script:PyrateMusicChoice=$sender.SelectedIndex
        $sender.Tag.IsEnabled=($sender.SelectedIndex -gt 0)
        Set-PyrateMusic $true
    })
    $musicVol.add_ValueChanged({
        param($sender,$e)
        $script:PyrateMusicVolume=[int]$sender.Value
        if ($script:PyrateMusicPlayer) { $script:PyrateMusicPlayer.Volume=$sender.Value/100 }
    })
    $effects.add_Click({
        param($sender,$e)
        $script:PyrateEffectsOn=[bool]$sender.IsChecked; $sender.Tag.IsEnabled=$script:PyrateEffectsOn
        if (!$script:PyrateEffectsOn) {
            Stop-PyrateEffects
            Stop-PyrateBells
        }
    })
    $sfxVol.add_ValueChanged({
        param($sender,$e)
        $script:PyrateEffectsVolume=[int]$sender.Value
        foreach ($voice in $script:PyrateEffectPlayers.ToArray()) { $voice.Volume=$sender.Value/100 }
        if ($sender.Value -le 0) { Stop-PyrateBells; Stop-PyrateEffects }
        elseif ($script:PyrateBellPlayer) { $script:PyrateBellPlayer.Volume=$sender.Value/100 }
    })
    $next.add_Click({ $script:PyrateTrackIndex++; Set-PyrateMusic $false })
    $test.add_Click({ Play-PyrateEffect 0 })
    $null=New-PyrateDialogText $body '02  /  SUPPORT THE CREW' 'Kicker'
    $null=New-PyrateDialogText $body 'Donate Monero (XMR) to The Background Gremlin Group.' 'Small'
    $address=[Windows.Controls.TextBox]::new()
    $address.Text=$script:PyrateAddress; $address.IsReadOnly=$true; $address.TextWrapping='Wrap'
    [Windows.Automation.AutomationProperties]::SetName($address,'Monero donation address')
    $address.Margin=[Windows.Thickness]::new(0,0,0,8); $null=$body.Children.Add($address)
    $support=[Windows.Controls.WrapPanel]::new(); $null=$body.Children.Add($support)
    $wallet=New-BwDialogButton $support 'Open Monero donation link'
    $copy=New-BwDialogButton $support 'Copy XMR address'
    $note=New-PyrateDialogText $body '' 'Small'
    $wallet.Tag=$note; $copy.Tag=$note
    $copy.add_Click({
        param($sender,$e)
        try { [Windows.Clipboard]::SetText($script:PyrateAddress); $sender.Tag.Text='XMR address copied.' }
        catch { $sender.Tag.Text='Could not copy. The address can be selected manually.' }
    })
    $wallet.add_Click({
        param($sender,$e)
        try {
            $open=[Diagnostics.ProcessStartInfo]::new('monero:'+$script:PyrateAddress)
            $open.UseShellExecute=$true
            $child=[Diagnostics.Process]::Start($open)
            if ($child) { $child.Dispose() }
            $sender.Tag.Text='Review the address in your Monero wallet.'
        } catch { $sender.Tag.Text='No Monero wallet could open the link. Use Copy XMR address.' }
    })
    $again=New-BwDialogButton $d.Buttons 'First-run setup'
    $again.IsEnabled=(!$script:Run -and !$script:Setup)
    $again.add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true })
    $close=New-BwDialogButton $d.Buttons 'Close' $true; $close.IsCancel=$true
    return [pscustomobject]@{ Dialog=$d; Now=$nowText; Address=$address }
}
function Show-PyrateSettings {
    $settings=New-PyrateSettings
    $script:PyrateMusicNow=$settings.Now
    try { $again=($settings.Dialog.Window.ShowDialog() -eq $true) }
    finally { $script:PyrateMusicNow=$null; Save-BwPrefs }
    if ($again) { Show-PyrateWizard }
}

function Get-PyrateSetupDestination([string]$Path) {
    $p=$Path.Trim()
    if ($p -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Enter a full drive or network folder path.' }
    return [IO.Path]::GetFullPath($p)
}
function Install-PyrateUserCopy {
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    if (!$local) { throw 'Windows did not report a Local AppData folder.' }
    $base=$local
    foreach ($part in @('BGGG','Simple Pyrate')) {
        $base=Join-Path $base $part
        $null=[IO.Directory]::CreateDirectory($base)
        if (([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Install folder must not be a junction or symbolic link: $base"
        }
    }
    $target=Join-Path $base "App-$script:PyrateVersion"
    if ([IO.Directory]::Exists($target) -and (([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Install folder must not be a junction or symbolic link: $target"
    }
    if ($script:AppRoot.TrimEnd('\') -ieq $target) { return $target }
    $files=@(
        'VERSION','Start-Simple-Pyrate.cmd','Start-Blackwake.cmd','Blackwake.ps1','SimplePyrate.ps1',
        'Engine.ps1','Install-Tools.ps1','Shipwright.ps1','VoyageTimeline.cs','VoyageCanvas.cs','RaidCanvas.cs','ShipAudio.cs',
        'assets\Deck.xaml','assets\Night-Sea.wav','assets\build-audio.py','assets\build-voyage.py','assets\make-sea.py',
        'assets\voyage\sea-and-sky.png','assets\voyage\fog.png','assets\voyage\lagoon.png','assets\voyage\pyrate-ship.png',
        'assets\voyage\port-0.png','assets\voyage\port-1.png','assets\voyage\port-2.png','assets\voyage\port-3.png',
        'README.md','CHANGELOG.md','docs\USER-GUIDE.md','docs\TROUBLESHOOTING.md','docs\DEVELOPMENT.md',
        'docs\WINDOWS-TEST.md','docs\V2.5.2-AUDIT.md','docs\media\pyrate-banner-v2.5.2.jpg','docs\media\edition-v2.5.2.svg',
        'docs\media\edition-v2.5.3.svg','docs\media\edition-v2.5.4.svg','docs\media\edition-v2.5.5.svg','docs\media\edition-v2.5.6.svg',
        'docs\media\runtime.svg','docs\media\formats.svg','docs\media\at-anchor.jpg','docs\media\port-battle.jpg',
        'tests\Engine.Tests.ps1','tests\Voyage.Tests.ps1','tests\Upgrade.Tests.ps1','tests\local_fixture.py'
    )
    foreach ($track in $script:PyrateMusicNames.Keys) {
        $files+="assets\audio\$track.mid"; $files+="assets\audio\$track.mp3"
    }
    foreach ($cue in $script:PyrateEffects) { $files+="assets\audio\$cue.wav" }
    foreach ($cue in $script:PyrateBellAssets.Values) { $files+="assets\audio\$cue.wav" }
    foreach ($name in $files) {
        if (![IO.File]::Exists((Join-Path $script:AppRoot $name))) { throw "The extracted app is missing $name. Extract the full ZIP before installing." }
    }
    if ([IO.Directory]::Exists($target)) {
        foreach ($name in $files) {
            $existing=Join-Path $target $name
            if (![IO.File]::Exists($existing) -or
                (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath (Join-Path $script:AppRoot $name) -Algorithm SHA256).Hash) {
                throw "An existing v$script:PyrateVersion copy at $target differs from this package. It was left untouched. Continue in portable mode or move the old folder first."
            }
        }
        return $target
    }
    $stage=Join-Path $base ('.install-'+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($stage)
    try {
        foreach ($name in $files) {
            $destination=Join-Path $stage $name
            $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [IO.File]::Copy((Join-Path $script:AppRoot $name),$destination,$false)
        }
        [IO.Directory]::Move($stage,$target)
        return $target
    } finally {
        if ([IO.Directory]::Exists($stage)) { [IO.Directory]::Delete($stage,$true) }
    }
}
function New-PyrateShortcut([string]$AppPath=$script:AppRoot,[switch]$StartMenu) {
    $location=[Environment]::GetFolderPath($(if ($StartMenu) { 'Programs' } else { 'DesktopDirectory' }))
    if (!$location -or ![IO.Directory]::Exists($location)) { throw 'Windows did not report a usable shortcut folder.' }
    $link=Join-Path $location $(if ($StartMenu) { "Simple Pyrate v$script:PyrateVersion.lnk" } else { 'Simple Pyrate.lnk' })
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$null
    try {
        $shortcut=$shell.CreateShortcut($link)
        $target=Join-Path $AppPath 'Start-Simple-Pyrate.cmd'
        if ([IO.File]::Exists($link)) {
            if ($shortcut.TargetPath -ieq $target) { return }
            $installRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BGGG\Simple Pyrate'
            $previous=@(
                (Join-Path $installRoot 'App-2.5.2\Start-Simple-Pyrate.cmd'),
                (Join-Path $installRoot 'App-2.5.2-setup2\Start-Simple-Pyrate.cmd'),
                (Join-Path $installRoot 'App-2.5.3\Start-Simple-Pyrate.cmd'),
                (Join-Path $installRoot 'App-2.5.4\Start-Simple-Pyrate.cmd'),
                (Join-Path $installRoot 'App-2.5.5\Start-Simple-Pyrate.cmd')
            )
            $updated=Join-Path (Join-Path $installRoot "App-$script:PyrateVersion") 'Start-Simple-Pyrate.cmd'
            if ($shortcut.TargetPath -notin $previous -or $target -ine $updated) {
                throw "The shortcut $link already points somewhere else and was left unchanged."
            }
        }
        $shortcut.TargetPath=$target
        $shortcut.WorkingDirectory=$AppPath
        $shortcut.Description='Simple Pyrate / The Background Gremlin Group'
        $shortcut.Save()
    } finally {
        if ($shortcut) { $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}
function Add-PyrateWizardText($Panel,[string]$Text,[string]$Role='Body') {
    $element=New-PyrateDialogText $Panel $Text
    $element.FlowDirection='LeftToRight'
    $element.TextAlignment='Left'
    $element.HorizontalAlignment='Stretch'
    $element.VerticalAlignment='Top'
    $element.FontFamily=[Windows.Media.FontFamily]::new('Segoe UI')
    $element.FontSize=14
    $element.LineHeight=21
    $element.LineStackingStrategy='MaxHeight'
    $element.Margin=[Windows.Thickness]::new(0,0,0,10)
    switch ($Role) {
        'Step' {
            $element.FontSize=12; $element.LineHeight=18; $element.FontWeight='SemiBold'
            $element.Foreground=Get-BwBrush '#E9BD72'
            $element.Margin=[Windows.Thickness]::new(0,0,0,6)
        }
        'Title' {
            $element.FontSize=28; $element.LineHeight=34; $element.FontWeight='SemiBold'
            $element.Margin=[Windows.Thickness]::new(0,0,0,8)
        }
        'Note' {
            $element.FontSize=13; $element.LineHeight=19
            $element.Foreground=Get-BwBrush '#BAC9C7'
        }
    }
    return $element
}
function Set-PyrateWizardPage($State) {
    $State.Body.Children.Clear()
    $State.Scroll.ScrollToTop()
    $State.Note=$null
    $State.Back.IsEnabled=($State.Page -gt 0 -and !$script:Setup)
    $State.Later.IsEnabled=(!$script:Setup)
    $State.Next.IsEnabled=(!$script:Setup)
    switch ($State.Page) {
        0 {
            $null=Add-PyrateWizardText $State.Body '01  /  FIRST-RUN SETUP' 'Step'
            $null=Add-PyrateWizardText $State.Body 'Welcome to Simple Pyrate' 'Title'
            $null=Add-PyrateWizardText $State.Body 'Let''s set up your ship.'

            $art=[Pyrate.VoyageCanvas]::CreateHarborArtwork((Join-Path $script:AppRoot 'assets\voyage'))
            $art.Height=126
            $art.Margin=[Windows.Thickness]::new(0,6,0,12)
            $null=$State.Body.Children.Add($art)

            $null=Add-PyrateWizardText $State.Body 'Choose a save folder, then check yt-dlp, FFmpeg, FFprobe, and Deno. Windows only asks for administrator approval if system tools need to be installed.'
            $State.Next.Content='Next'
        }
        1 {
            $null=Add-PyrateWizardText $State.Body '02  /  THE CARGO HOLD' 'Step'
            $null=Add-PyrateWizardText $State.Body 'Choose a save folder' 'Title'
            $folder=[Windows.Controls.TextBox]::new()
            $folder.Text=$State.Folder; $folder.Margin=[Windows.Thickness]::new(0,6,0,8)
            [Windows.Automation.AutomationProperties]::SetName($folder,'Save folder')
            $folder.Tag=$State; $null=$State.Body.Children.Add($folder)
            $folder.add_TextChanged({ param($sender,$e) $sender.Tag.Folder=$sender.Text })
            $pick=New-BwDialogButton $State.Body 'Browse folders'; $pick.HorizontalAlignment='Left'; $pick.Tag=$folder
            $pick.add_Click({
                param($sender,$e)
                Pick-BwFolder $sender.Tag ([Windows.Window]::GetWindow($sender))
            })
            $install=New-PyrateDialogCheck $State.Body 'Install an app copy for this Windows account' $State.InstallCopy
            $install.Tag=$State; $install.add_Click({ param($sender,$e) $sender.Tag.InstallCopy=[bool]$sender.IsChecked })
            $link=New-PyrateDialogCheck $State.Body 'Create a Desktop shortcut' $State.Shortcut
            $link.Tag=$State; $link.add_Click({ param($sender,$e) $sender.Tag.Shortcut=[bool]$sender.IsChecked })
            $null=Add-PyrateWizardText $State.Body 'An installed copy gets a Start Menu shortcut. If you stay portable, keep the extracted app folder in place.' 'Note'
            $State.Note=Add-PyrateWizardText $State.Body '' 'Note'
            $State.Next.Content='Check tools'
        }
        2 {
            $null=Add-PyrateWizardText $State.Body '03  /  SHIPYARD INSPECTION' 'Step'
            $null=Add-PyrateWizardText $State.Body 'Check the machine-wide tools' 'Title'
            $State.Ready=$false
            if (!$script:Setup) { $State.Ready=Update-BwTools }
            foreach ($key in @('yt-dlp','ffmpeg','ffprobe','deno')) {
                $path=if ($script:Tools -and $script:Tools[$key]) { $script:Tools[$key] } else { 'Missing from the system PATH' }
                $line=[Windows.Controls.Grid]::new()
                $line.Margin=[Windows.Thickness]::new(0,0,0,5)
                $nameColumn=[Windows.Controls.ColumnDefinition]::new()
                $nameColumn.Width=[Windows.GridLength]::new(98)
                $pathColumn=[Windows.Controls.ColumnDefinition]::new()
                $pathColumn.Width=[Windows.GridLength]::new(1,'Star')
                $line.ColumnDefinitions.Add($nameColumn); $line.ColumnDefinitions.Add($pathColumn)
                $label=Add-PyrateWizardText $line $key 'Note'
                $label.FontWeight='SemiBold'; $label.Margin=[Windows.Thickness]::new(0,0,12,0)
                $value=Add-PyrateWizardText $line $path 'Note'
                $value.Margin=[Windows.Thickness]::new(0)
                [Windows.Controls.Grid]::SetColumn($value,1)
                $null=$State.Body.Children.Add($line)
            }
            $null=Add-PyrateWizardText $State.Body 'Existing system tools are kept. Only missing tools are downloaded, verified, and registered on the Windows system PATH.'
            $State.Note=Add-PyrateWizardText $State.Body '' 'Note'
            if ($script:Setup) {
                $State.Note.Text='Installing and checking Windows system tools. This can take a few minutes.'
                $work=[Windows.Controls.ProgressBar]::new()
                $work.Height=8; $work.IsIndeterminate=$true; $work.Foreground=Get-BwBrush '#E9BD72'
                [Windows.Automation.AutomationProperties]::SetName($work,'Installing the system tools')
                $null=$State.Body.Children.Add($work)
            }
            elseif ($State.Failed) { $State.Note.Text='Shipyard did not finish. Retry and approve the Windows prompt, or continue later. See the ship''s log for the exit code.' }
            $State.Next.Content=if ($State.Ready) { 'Next' } elseif ($State.Failed) { 'Retry install' } else { 'Install missing tools' }
        }
        3 {
            $null=Add-PyrateWizardText $State.Body '04  /  READY TO SAIL' 'Step'
            $null=Add-PyrateWizardText $State.Body 'The chart room is ready' 'Title'
            $null=Add-PyrateWizardText $State.Body "Save folder: $($State.Folder)" 'Note'
            $null=Add-PyrateWizardText $State.Body 'Paste a link, choose your cargo and queue a haul. The Captain''s settings hold music playlists, port sound effects and the donation link.'
            $null=Add-PyrateWizardText $State.Body $(if ($State.InstallCopy) { 'Finish will install a per-user copy and add it to the Start Menu. The current window stays open.' } else { 'Finish keeps the app portable in its current folder.' }) 'Note'
            $State.Note=Add-PyrateWizardText $State.Body '' 'Note'
            $State.Next.Content='Finish'
        }
    }
}
function New-PyrateWizard {
    $d=New-BwDialog 'Simple Pyrate Setup' 700 490 -NoBodyHeading
    $d.Window.UseLayoutRounding=$true
    $d.Window.SnapsToDevicePixels=$true
    $d.Window.MaxWidth=[Math]::Max($d.Window.MinWidth,[Windows.SystemParameters]::WorkArea.Width-24)
    $d.Window.MaxHeight=[Math]::Max($d.Window.MinHeight,[Windows.SystemParameters]::WorkArea.Height-24)
    $d.Window.Width=[Math]::Min($d.Window.Width,$d.Window.MaxWidth)
    $d.Window.Height=[Math]::Min($d.Window.Height,$d.Window.MaxHeight)
    $d.Buttons.HorizontalAlignment='Right'
    $body=New-PyrateDialogStack $d
    $body.UseLayoutRounding=$true
    $body.SnapsToDevicePixels=$true
    $body.Margin=[Windows.Thickness]::new(0,0,12,0)
    $scroll=$d.Body.Children[0]
    $back=New-BwDialogButton $d.Buttons 'Back'
    $later=New-BwDialogButton $d.Buttons 'Later'
    $next=New-BwDialogButton $d.Buttons 'Next' $true
    $next.IsDefault=$true
    foreach ($button in @($back,$later,$next)) {
        $button.MinHeight=42; $button.MinWidth=78
        $button.VerticalAlignment='Center'
    }
    $state=[pscustomobject]@{ Window=$d.Window; Body=$body; Scroll=$scroll; Back=$back; Later=$later; Next=$next
        Page=0; Folder=$script:Ui.Destination.Text; Shortcut=$script:PyrateShortcut; InstallCopy=$false; Note=$null; Ready=$false; Failed=$false; Timer=$null }
    $back.Tag=$state; $later.Tag=$state; $next.Tag=$state
    $back.add_Click({ param($sender,$e) $sender.Tag.Page--; Set-PyrateWizardPage $sender.Tag })
    $later.add_Click({ param($sender,$e) $sender.Tag.Window.Close() })
    $next.add_Click({
        param($sender,$e)
        $s=$sender.Tag
        try {
            switch ($s.Page) {
                0 { $s.Page=1 }
                1 {
                    $s.Folder=Get-PyrateSetupDestination $s.Folder
                    $s.Page=2
                }
                2 {
                    if ($s.Ready) { $s.Page=3 }
                    else {
                        $s.Failed=$false
                        Start-BwSetup $false $true
                        if (!$script:Setup) { $s.Failed=$true }
                    }
                }
                3 {
                    if (!(Update-BwTools)) { $s.Page=2; Set-PyrateWizardPage $s; return }
                    $null=[IO.Directory]::CreateDirectory($s.Folder)
                    $appPath=$script:AppRoot
                    if ($s.InstallCopy) { $appPath=Install-PyrateUserCopy; New-PyrateShortcut $appPath -StartMenu }
                    if ($s.Shortcut) { New-PyrateShortcut $appPath }
                    if ($s.InstallCopy) { Add-BwLog "Installed the per-user app copy: $appPath" }
                    $script:Ui.Destination.Text=$s.Folder
                    $script:PyrateShortcut=$s.Shortcut
                    $script:PyrateWizardComplete=$true; $script:Hold=$false
                    Save-BwPrefs
                    Show-BwError ''
                    $s.Window.DialogResult=$true
                    return
                }
            }
            Set-PyrateWizardPage $s
        } catch {
            if ($s.Note) { $s.Note.Text=$_.Exception.Message }
            else { Add-BwLog "Wizard: $($_.Exception.Message)" }
        }
    })
    $d.Window.add_Closing({ param($sender,$e) if ($script:Setup) { $e.Cancel=$true } })
    $timer=[Windows.Threading.DispatcherTimer]::new()
    $timer.Interval=[TimeSpan]::FromMilliseconds(240)
    $state.Timer=$timer; $d.Window.Tag=$state
    $timer.add_Tick({
        $currentWizard=$script:PyrateWizardActive
        if ($currentWizard -and $currentWizard.Page -eq 2 -and !$script:Setup -and !$currentWizard.Next.IsEnabled) {
            $currentWizard.Failed=($script:PyrateSetupExit -ne 0)
            Set-PyrateWizardPage $currentWizard
            if ($currentWizard.Ready -and !$currentWizard.Failed) { $currentWizard.Page=3; Set-PyrateWizardPage $currentWizard }
        }
    })
    $d.Window.add_Loaded({ param($sender,$e) $script:PyrateWizardActive=$sender.Tag; $sender.Tag.Timer.Start() })
    $d.Window.add_Closed({ param($sender,$e) $sender.Tag.Timer.Stop(); $script:PyrateWizardActive=$null })
    Set-PyrateWizardPage $state
    return $state
}
function Show-PyrateWizard {
    if ($script:Setup -or $script:Run) { return }
    $wizard=New-PyrateWizard
    $null=$wizard.Window.ShowDialog()
}
