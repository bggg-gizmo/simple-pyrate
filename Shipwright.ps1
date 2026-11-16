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
$script:PyrateEffectsOn=$false
$script:PyrateEffectsVolume=50
$script:PyrateWizardComplete=$false
$script:PyrateShortcut=$false
$script:PyrateTrackIndex=0
$script:PyrateMusicPlayer=$null
$script:PyrateEffectPlayer=$null
$script:PyrateEffectKey=''
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
function Play-PyrateEffect([int]$Index) {
    if (!$script:PyrateEffectsOn -or $script:PyrateEffectsVolume -le 0 -or $script:SmokeTest) { return }
    try {
        if (!$script:PyrateEffectPlayer) {
            $script:PyrateEffectPlayer=[Windows.Media.MediaPlayer]::new()
            $script:PyrateEffectPlayer.add_MediaFailed({ param($sender,$e) Add-BwLog "Port sound unavailable: $($e.ErrorException.Message)" })
        }
        $player=$script:PyrateEffectPlayer
        $player.Close(); $player.Volume=$script:PyrateEffectsVolume/100.0
        $name=$script:PyrateEffects[$Index]
        $player.Open([uri](Join-Path $script:AppRoot "assets\audio\$name.wav")); $player.Play()
    } catch { Add-BwLog "Could not play port sound: $($_.Exception.Message)" }
}
function Update-PyrateRaidSound($Frame) {
    if ($Frame.Shot -ne [Pyrate.Shot]::Battle) { return }
    $cue=if ($Frame.RaidStage -eq 0) { [int][Math]::Floor($Frame.RaidSceneAge/2.7) } else { 0 }
    $key="$($Frame.Port)/$($Frame.RaidStage)/$cue"
    if ($key -eq $script:PyrateEffectKey) { return }
    $script:PyrateEffectKey=$key
    Play-PyrateEffect $Frame.RaidStage
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
        if (!$script:PyrateEffectsOn -and $script:PyrateEffectPlayer) { $script:PyrateEffectPlayer.Close() }
    })
    $sfxVol.add_ValueChanged({
        param($sender,$e)
        $script:PyrateEffectsVolume=[int]$sender.Value
        if ($script:PyrateEffectPlayer) { $script:PyrateEffectPlayer.Volume=$sender.Value/100 }
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
    $target=Join-Path $base 'App-2.5.2'
    if ([IO.Directory]::Exists($target) -and (([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Install folder must not be a junction or symbolic link: $target"
    }
    if ($script:AppRoot.TrimEnd('\') -ieq $target) { return $target }
    $files=@(
        'Start-Simple-Pyrate.cmd','Start-Blackwake.cmd','Blackwake.ps1','SimplePyrate.ps1',
        'Engine.ps1','Install-Tools.ps1','Shipwright.ps1','VoyageTimeline.cs','VoyageCanvas.cs','RaidCanvas.cs',
        'assets\Deck.xaml','assets\Night-Sea.wav','assets\build-audio.py','assets\build-voyage.py','assets\make-sea.py',
        'assets\voyage\sea-and-sky.png','assets\voyage\fog.png','assets\voyage\lagoon.png','assets\voyage\pyrate-ship.png',
        'assets\voyage\port-0.png','assets\voyage\port-1.png','assets\voyage\port-2.png','assets\voyage\port-3.png',
        'README.md','CHANGELOG.md','docs\USER-GUIDE.md','docs\TROUBLESHOOTING.md','docs\DEVELOPMENT.md',
        'docs\WINDOWS-TEST.md','docs\V2.5.2-AUDIT.md','docs\media\pyrate-banner-v2.5.2.jpg','docs\media\edition-v2.5.2.svg',
        'docs\media\runtime.svg','docs\media\formats.svg','docs\media\at-anchor.jpg','docs\media\port-battle.jpg',
        'tests\Engine.Tests.ps1','tests\Voyage.Tests.ps1','tests\Upgrade.Tests.ps1','tests\local_fixture.py'
    )
    foreach ($track in $script:PyrateMusicNames.Keys) {
        $files+="assets\audio\$track.mid"; $files+="assets\audio\$track.mp3"
    }
    foreach ($cue in $script:PyrateEffects) { $files+="assets\audio\$cue.wav" }
    foreach ($name in $files) {
        if (![IO.File]::Exists((Join-Path $script:AppRoot $name))) { throw "The extracted app is missing $name. Extract the full ZIP before installing." }
    }
    if ([IO.Directory]::Exists($target)) {
        foreach ($name in $files) {
            $existing=Join-Path $target $name
            if (![IO.File]::Exists($existing) -or
                (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath (Join-Path $script:AppRoot $name) -Algorithm SHA256).Hash) {
                throw "An existing v2.5.2 copy at $target differs from this package. It was left untouched. Continue in portable mode or move the old folder first."
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
    $link=Join-Path $location $(if ($StartMenu) { 'Simple Pyrate v2.5.2.lnk' } else { 'Simple Pyrate.lnk' })
    $shell=New-Object -ComObject WScript.Shell
    try {
        if ([IO.File]::Exists($link)) {
            $existing=$shell.CreateShortcut($link)
            if ($existing.TargetPath -ine (Join-Path $AppPath 'Start-Simple-Pyrate.cmd')) {
                throw "The shortcut $link already points somewhere else and was left unchanged."
            }
            return
        }
        $shortcut=$shell.CreateShortcut($link)
        $shortcut.TargetPath=Join-Path $AppPath 'Start-Simple-Pyrate.cmd'
        $shortcut.WorkingDirectory=$AppPath
        $shortcut.Description='Simple Pyrate / The Background Gremlin Group'
        $shortcut.Save()
    } finally { $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}
function Set-PyrateWizardPage($State) {
    $State.Body.Children.Clear()
    $State.Back.IsEnabled=($State.Page -gt 0 -and !$script:Setup)
    $State.Later.IsEnabled=(!$script:Setup)
    $State.Next.IsEnabled=(!$script:Setup)
    switch ($State.Page) {
        0 {
            $null=New-PyrateDialogText $State.Body '01  /  FIRST-RUN SETUP' 'Kicker'
            $null=New-PyrateDialogText $State.Body 'Welcome to Simple Pyrate' 'Heading'
            $null=New-PyrateDialogText $State.Body 'Let''s set up your ship.'

            # Compose the original artwork here without reusing the live voyage text.
            $artwork=[Windows.Media.DrawingGroup]::new()
            $voyageFolder=Join-Path $script:AppRoot 'assets\voyage'
            foreach ($layer in @(
                @{ File='sea-and-sky.png'; Bounds=[Windows.Rect]::new(0,0,1200,390) },
                @{ File='lagoon.png'; Bounds=[Windows.Rect]::new(0,0,1200,390) },
                @{ File='pyrate-ship.png'; Bounds=[Windows.Rect]::new(504,125,323.7,172.38) },
                @{ File='fog.png'; Bounds=[Windows.Rect]::new(0,0,1200,390) }
            )) {
                $bitmap=[Windows.Media.Imaging.BitmapImage]::new()
                $bitmap.BeginInit()
                $bitmap.CacheOption='OnLoad'
                $bitmap.UriSource=[uri](Join-Path $voyageFolder $layer.File)
                $bitmap.EndInit()
                $drawing=[Windows.Media.ImageDrawing]::new()
                $drawing.ImageSource=$bitmap
                $drawing.Rect=$layer.Bounds
                $artwork.Children.Add($drawing)
            }
            if ($artwork.CanFreeze) { $artwork.Freeze() }
            $art=[Windows.Controls.Image]::new()
            $art.Source=[Windows.Media.DrawingImage]::new($artwork)
            $art.Height=146; $art.Stretch='UniformToFill'; $art.ClipToBounds=$true
            $art.IsHitTestVisible=$false
            $art.Margin=[Windows.Thickness]::new(0,6,0,12)
            $null=$State.Body.Children.Add($art)

            $null=New-PyrateDialogText $State.Body 'Choose a save folder, then check yt-dlp, FFmpeg, FFprobe, and Deno. Windows only asks for administrator approval if system tools need to be installed.'
            $State.Next.Content='Next'
        }
        1 {
            $null=New-PyrateDialogText $State.Body '02  /  THE CARGO HOLD' 'Kicker'
            $null=New-PyrateDialogText $State.Body 'Choose a save folder' 'Heading'
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
            $null=New-PyrateDialogText $State.Body 'An installed copy gets a Start Menu shortcut. If you stay portable, keep the extracted app folder in place.' 'Small'
            $State.Note=New-PyrateDialogText $State.Body '' 'Small'
            $State.Next.Content='Check tools'
        }
        2 {
            $null=New-PyrateDialogText $State.Body '03  /  SHIPYARD INSPECTION' 'Kicker'
            $null=New-PyrateDialogText $State.Body 'Check the machine-wide tools' 'Heading'
            $State.Ready=$false
            if (!$script:Setup) { $State.Ready=Update-BwTools }
            foreach ($key in @('yt-dlp','ffmpeg','ffprobe','deno')) {
                $path=if ($script:Tools -and $script:Tools[$key]) { $script:Tools[$key] } else { 'Missing from the system PATH' }
                $null=New-PyrateDialogText $State.Body "$key  /  $path" 'Small'
            }
            $null=New-PyrateDialogText $State.Body 'Existing system tools are kept. Only missing tools are downloaded, verified, and registered on the Windows system PATH.'
            $State.Note=New-PyrateDialogText $State.Body '' 'Small'
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
            $null=New-PyrateDialogText $State.Body '04  /  READY TO SAIL' 'Kicker'
            $null=New-PyrateDialogText $State.Body 'The chart room is ready' 'Heading'
            $null=New-PyrateDialogText $State.Body "Save folder: $($State.Folder)" 'Small'
            $null=New-PyrateDialogText $State.Body 'Paste a link, choose your cargo and queue a haul. The Captain''s settings hold music playlists, port sound effects and the donation link.'
            $null=New-PyrateDialogText $State.Body $(if ($State.InstallCopy) { 'Finish will install a per-user copy and add it to the Start Menu. The current window stays open.' } else { 'Finish keeps the app portable in its current folder.' }) 'Small'
            $State.Note=New-PyrateDialogText $State.Body '' 'Small'
            $State.Next.Content='Finish'
        }
    }
}
function New-PyrateWizard {
    $d=New-BwDialog 'Simple Pyrate Setup' 700 490 -NoBodyHeading
    $body=New-PyrateDialogStack $d
    $back=New-BwDialogButton $d.Buttons 'Back'
    $later=New-BwDialogButton $d.Buttons 'Later'
    $next=New-BwDialogButton $d.Buttons 'Next' $true
    $next.IsDefault=$true
    $state=[pscustomobject]@{ Window=$d.Window; Body=$body; Back=$back; Later=$later; Next=$next
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
