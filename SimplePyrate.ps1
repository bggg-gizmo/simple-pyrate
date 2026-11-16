param([switch]$SmokeTest)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:StartupStage = 'Loading Windows desktop assemblies'
try {
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,UIAutomationTypes,System.Xaml
Add-Type -TypeDefinition @'
using System.ComponentModel;
namespace Blackwake {
    public sealed class QueueRow : INotifyPropertyChanged {
        private string status;
        private string detail;
        private string ink;
        public int Id { get; set; }
        public object Job { get; set; }
        public string Url { get; set; }
        public string Label { get; set; }
        public string Status { get { return status; } set { status=value; Changed("Status"); } }
        public string Detail { get { return detail; } set { detail=value; Changed("Detail"); } }
        public string Ink { get { return ink; } set { ink=value; Changed("Ink"); } }
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(string name) {
            PropertyChangedEventHandler handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }
    public sealed class FolderEntry {
        public string Name { get; set; }
        public string Path { get; set; }
    }
    public sealed class SavedFile {
        public string Name { get; set; }
        public string Path { get; set; }
    }
}
'@
$script:StartupStage = 'Loading the download engine'
. (Join-Path $PSScriptRoot 'Engine.ps1')
$script:AppRoot = $PSScriptRoot
$script:ProfileDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BGGG\Blackwake'
$script:PrefsPath = Join-Path $script:ProfileDir 'settings.json'
$script:Lines = [Collections.Generic.Queue[string]]::new()
$script:Saved = [Collections.ObjectModel.ObservableCollection[Blackwake.SavedFile]]::new()
$script:SavedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:Rows = [Collections.ObjectModel.ObservableCollection[Blackwake.QueueRow]]::new()
$script:Events = [Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:Run = $null
$script:Current = $null
$script:Setup = $null
$script:Hold = $false
$script:Closing = $false
$script:ClosingConfirmed = $false
$script:Tools = $null
$script:NextId = 1
$script:Meter = $null
$script:MeterRun = $false
$script:Sound = $null
$script:OpenLog = $null
$script:Dialog = $null

try {
    Add-Type -Namespace Blackwake -Name DarkChrome -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr handle, int attribute, ref int value, int size);
'@
} catch { }
function Set-DarkChrome($Window) {
    try {
        $h = [Windows.Interop.WindowInteropHelper]::new($Window).Handle
        [int]$yes = 1
        if ([Blackwake.DarkChrome]::DwmSetWindowAttribute($h,20,[ref]$yes,4) -ne 0) {
            $null = [Blackwake.DarkChrome]::DwmSetWindowAttribute($h,19,[ref]$yes,4)
        }
    } catch { }
}
$script:StartupStage = 'Compiling the voyage renderer'
if (!('Pyrate.VoyageCanvas' -as [type])) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'VoyageTimeline.cs'),(Join-Path $PSScriptRoot 'VoyageCanvas.cs')) -ReferencedAssemblies @(
        [Windows.FrameworkElement].Assembly.Location, [Windows.Media.DrawingContext].Assembly.Location,
        [Windows.DependencyObject].Assembly.Location, [Windows.Automation.AutomationProperties].Assembly.Location,
        [Uri].Assembly.Location,
        [System.Windows.Markup.IQueryAmbient].Assembly.Location
    )
}
$script:StartupStage = 'Opening the deck layout'
$xml = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'assets\Deck.xaml'))
try { $script:Deck = [Windows.Markup.XamlReader]::Load($xml) } finally { $xml.Dispose() }
$script:Deck.add_SourceInitialized({ Set-DarkChrome $script:Deck })
$script:Ui = @{}
foreach ($name in ('SeaSound Motion ShowTools DeckScroll Board BoardLeft BoardGap BoardRight MobileRow NewCargoCard FlightCard VoyageStage VoyageRow VoyageAnnounce DeckAtmosphere DeckDrift Paste Links LinkHint Single Collection VideoMode AudioMode CaptionMode MediaOptions VideoOptions AudioOptions CaptionOptions HeightChoice QualityChoice Languages CaptionChoice AutoCaptions Browse Destination FormError Queue ActiveStatus ActiveTitle ActiveDetail MeterTrack MeterFill MeterSweep SweepShift AccessibleMeter Percent Telemetry QueueCount Jobs EmptyQueue Cancel Remove Retry Clear OpenFolder ShowLog ShowFiles ToolStatus' -split ' ')) {
    $item = $script:Deck.FindName($name)
    if (!$item) { throw "Missing interface control $name." }
    $script:Ui[$name] = $item
}
$script:Ui.Jobs.ItemsSource = $script:Rows
$script:Voyage = [Pyrate.VoyageTimeline]::new()
$script:VoyageClock = [Diagnostics.Stopwatch]::StartNew()
$script:VoyageStatus='Complete'
$script:StartupStage = 'Loading the voyage artwork'
$script:VoyageArt = [Pyrate.VoyageCanvas]::new((Join-Path $PSScriptRoot 'assets\voyage'))
$null = $script:Ui.VoyageStage.Children.Insert(0,$script:VoyageArt)
$script:Ui.DeckAtmosphere.Source = [Windows.Media.Imaging.BitmapImage]::new([uri](Join-Path $PSScriptRoot 'assets\voyage\sea-and-sky.png'))
$script:LastVoyageLine=''
function Draw-BwVoyage {
    $now=$script:VoyageClock.Elapsed.TotalSeconds
    $motion=[bool]$script:Ui.Motion.IsChecked
    $shot=$script:Voyage.Tick($now,$motion)
    $script:VoyageArt.Present($shot,$now,$motion)
    $line=$shot.Headline
    if ($shot.Shot -eq [Pyrate.Shot]::Battle) { $line+=". Port $($shot.Port). $($shot.Mode). $($shot.Detail)" }
    if ($line -cne $script:LastVoyageLine) {
        $script:LastVoyageLine=$line
        $script:Ui.VoyageAnnounce.Text=$line
        $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($script:Ui.VoyageAnnounce)
        if (!$peer -and [Windows.Automation.Peers.AutomationPeer]::ListenerExists([Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged)) {
            $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($script:Ui.VoyageAnnounce)
        }
        if ($peer) { $peer.RaiseAutomationEvent([Windows.Automation.Peers.AutomationEvents]::LiveRegionChanged) }
    }
}
function Complete-BwVoyage([string]$Status,[bool]$MoreQueued) {
    $script:Voyage.Finish($script:VoyageClock.Elapsed.TotalSeconds,$Status,$MoreQueued)
    if (!$script:Ui.Motion.IsChecked) { Draw-BwVoyage }
}
function Test-BwVoyageContinuing {
    if ($script:Closing -or $script:Hold) { return $false }
    return (@($script:Rows | Where-Object { $_.Status -eq 'Queued' }).Count -gt 0)
}
function Add-BwLog([string]$Text) {
    if (!$Text) { return }
    $script:Lines.Enqueue(('[{0:HH:mm:ss}] {1}' -f (Get-Date),$Text))
    while ($script:Lines.Count -gt 650) { $null = $script:Lines.Dequeue() }
    if ($null -ne $script:OpenLog) {
        $script:OpenLog.Text = $script:Lines -join [Environment]::NewLine
        $script:OpenLog.ScrollToEnd()
    }
}
function Show-BwError([string]$Text) {
    $script:Ui.FormError.Text = $Text
    $script:Ui.FormError.Visibility = if ($Text) { 'Visible' } else { 'Collapsed' }
}
function Get-BwBrush([string]$Color) {
    return [Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}
function New-BwDialog([string]$Title,[int]$Width,[int]$Height) {
    $w = [Windows.Window]::new()
    $w.Owner = $script:Deck; $w.Title = $Title; $w.Width=$Width; $w.Height=$Height
    $w.MinWidth = [Math]::Min($Width,420); $w.MinHeight = [Math]::Min($Height,240)
    $w.WindowStartupLocation = 'CenterOwner'; $w.ShowInTaskbar = $false
    $w.Background = Get-BwBrush '#101D23'; $w.Foreground = Get-BwBrush '#F1E6CB'
    $w.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI'); $w.FontSize = 13
    $w.Resources.MergedDictionaries.Add($script:Deck.Resources)
    $w.add_SourceInitialized({ param($sender,$e) Set-DarkChrome $sender })
    $root = [Windows.Controls.DockPanel]::new(); $root.Margin=[Windows.Thickness]::new(18)
    $head = [Windows.Controls.TextBlock]::new(); $head.Text=$Title
    $head.Style = $script:Deck.FindResource('Heading'); $head.Margin=[Windows.Thickness]::new(0,0,0,10)
    [Windows.Controls.DockPanel]::SetDock($head,'Top'); $null=$root.Children.Add($head)
    $buttons = [Windows.Controls.WrapPanel]::new(); $buttons.Margin=[Windows.Thickness]::new(0,10,0,0)
    [Windows.Controls.DockPanel]::SetDock($buttons,'Bottom'); $null=$root.Children.Add($buttons)
    $body = [Windows.Controls.DockPanel]::new(); $null=$root.Children.Add($body)
    $w.Content = $root
    return [pscustomobject]@{ Window=$w; Body=$body; Buttons=$buttons }
}
function New-BwDialogButton($Panel,[string]$Text,[bool]$Primary=$false) {
    $button = [Windows.Controls.Button]::new(); $button.Content=$Text
    $button.Style = $script:Deck.FindResource($(if ($Primary) { 'Primary' } else { 'BaseButton' }))
    $button.Margin=[Windows.Thickness]::new(0,0,7,4)
    $null=$Panel.Children.Add($button)
    return $button
}
function Show-BwChoice([string]$Title,[string]$Text,[string]$Yes,[string]$No) {
    $d = New-BwDialog $Title 550 235
    $part = [Windows.Controls.TextBlock]::new(); $part.Text=$Text; $part.TextWrapping='Wrap'; $part.VerticalAlignment='Top'
    $null=$d.Body.Children.Add($part)
    $cancelButton = New-BwDialogButton $d.Buttons $No
    $cancelButton.IsCancel=$true
    $acceptButton = New-BwDialogButton $d.Buttons $Yes $true
    $acceptButton.IsDefault=$true
    $acceptButton.add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true })
    return ($d.Window.ShowDialog() -eq $true)
}
function Update-BwTools {
    try {
        $script:Tools = Get-BwToolPaths
        $missing = @($script:Tools.Values | Where-Object { !$_ }).Count
        $script:Ui.ToolStatus.Text = if ($missing) { "SHIPYARD  /  $missing MISSING" } else { 'SHIPYARD  /  READY' }
        return ($missing -eq 0)
    } catch {
        Add-BwLog "Tool check failed: $($_.Exception.Message)"
        $script:Ui.ToolStatus.Text = 'SHIPYARD  /  CHECK FAILED'
        return $false
    }
}
function Start-BwSetup([bool]$Refresh) {
    if ($script:Setup -or $script:Run) { return }
    try {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
        $command = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $script:AppRoot 'Install-Tools.ps1'))
        if ($Refresh) { $command += '-Refresh' }
        $info.Arguments = Join-BwArguments $command
        $info.UseShellExecute = $true; $info.Verb = 'runas'; $info.WindowStyle = 'Normal'
        $script:Setup = [Diagnostics.Process]::Start($info)
        if (!$script:Setup) { throw 'Windows did not start the Shipyard process.' }
        $script:Hold = $false
        $script:Ui.ToolStatus.Text = 'SHIPYARD  /  INSTALLING'
        Add-BwLog 'Shipyard is preparing machine-wide dependencies.'
    } catch {
        $script:Hold = $true
        Add-BwLog "Shipyard was not started: $($_.Exception.Message)"
        Show-BwError 'Shipyard did not start. Open Shipyard to retry Windows administrator approval.'
    }
}
function Show-BwShipyard {
    $ready = if ($script:Setup) { $false } else { Update-BwTools }
    $d = New-BwDialog 'Shipyard' 650 360
    $content = [Windows.Controls.TextBlock]::new(); $content.TextWrapping='Wrap'
    $status = @('yt-dlp','ffmpeg','ffprobe','deno' | ForEach-Object {
        $p = if ($script:Tools) { $script:Tools[$_] } else { $null }
        if ($p) { "$_  /  $p" } else { "$_  /  missing from system PATH" }
    })
    $content.Text = ($status -join [Environment]::NewLine) + [Environment]::NewLine + [Environment]::NewLine +
        'Missing tools are installed under Program Files and registered on the machine-wide PATH after Windows administrator approval. Refresh only replaces tools installed by Simple Pyrate.'
    $content.LineHeight = 21
    $null=$d.Body.Children.Add($content)
    $close = New-BwDialogButton $d.Buttons 'Close'; $close.IsCancel=$true
    $install = New-BwDialogButton $d.Buttons $(if ($ready) { 'Refresh managed tools' } else { 'Install missing tools' }) $true
    $install.IsEnabled = (-not $script:Run -and -not $script:Setup)
    $install.add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true })
    if ($d.Window.ShowDialog() -eq $true) { Start-BwSetup $ready }
}
function Load-BwPrefs {
    $data = $null
    try {
        if ([IO.File]::Exists($script:PrefsPath)) { $data = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:PrefsPath)) }
    } catch { Add-BwLog 'Could not read saved settings. Defaults are in use.' }
    $homeFolder = [Environment]::GetFolderPath('UserProfile')
    $default = Join-Path $homeFolder 'Downloads\Simple Pyrate'
    $script:Ui.Destination.Text = [string](Get-BwValue $data 'Destination' $default)
    $script:Ui.Motion.IsChecked = [bool](Get-BwValue $data 'Motion' ([Windows.SystemParameters]::ClientAreaAnimation))
    $script:Ui.SeaSound.IsChecked = [bool](Get-BwValue $data 'SeaSound' $false)
    $script:Ui.VideoMode.IsChecked = [bool](Get-BwValue $data 'Video' $true)
    $script:Ui.AudioMode.IsChecked = [bool](Get-BwValue $data 'Audio' $false)
    $script:Ui.CaptionMode.IsChecked = [bool](Get-BwValue $data 'Caption' $false)
    $script:Ui.Collection.IsChecked = [bool](Get-BwValue $data 'Collection' $false)
    $script:Ui.Single.IsChecked = !$script:Ui.Collection.IsChecked
    $script:Ui.Languages.Text = [string](Get-BwValue $data 'Languages' 'en')
    $script:Ui.AutoCaptions.IsChecked = [bool](Get-BwValue $data 'AutoCaptions' $true)
    foreach ($option in @{HeightChoice=0;QualityChoice=1;CaptionChoice=0}.GetEnumerator()) {
        $ctrl=$script:Ui[$option.Key]
        try {
            $index = [int](Get-BwValue $data $option.Key $option.Value)
            if ($index -ge 0 -and $index -lt $ctrl.Items.Count) { $ctrl.SelectedIndex = $index }
        } catch { }
    }
}
function Save-BwPrefs {
    $settings = @{
        Destination=$script:Ui.Destination.Text; Motion=$script:Ui.Motion.IsChecked; SeaSound=$script:Ui.SeaSound.IsChecked
        Video=$script:Ui.VideoMode.IsChecked; Audio=$script:Ui.AudioMode.IsChecked; Caption=$script:Ui.CaptionMode.IsChecked
        Collection=$script:Ui.Collection.IsChecked; Languages=$script:Ui.Languages.Text; AutoCaptions=$script:Ui.AutoCaptions.IsChecked
        HeightChoice=$script:Ui.HeightChoice.SelectedIndex; QualityChoice=$script:Ui.QualityChoice.SelectedIndex; CaptionChoice=$script:Ui.CaptionChoice.SelectedIndex
    }
    try {
        $null = [IO.Directory]::CreateDirectory($script:ProfileDir)
        [IO.File]::WriteAllText($script:PrefsPath,(ConvertTo-Json $settings),[Text.UTF8Encoding]::new($false))
    } catch { Add-BwLog 'Could not save preferences.' }
}
function Update-BwOptions {
    $script:Ui.VideoOptions.Visibility = if ($script:Ui.VideoMode.IsChecked) { 'Visible' } else { 'Collapsed' }
    $script:Ui.AudioOptions.Visibility = if ($script:Ui.AudioMode.IsChecked) { 'Visible' } else { 'Collapsed' }
    $script:Ui.CaptionOptions.Visibility = if ($script:Ui.CaptionMode.IsChecked) { 'Visible' } else { 'Collapsed' }
    $script:Ui.MediaOptions.Visibility = if ($script:Ui.VideoMode.IsChecked -or $script:Ui.AudioMode.IsChecked) { 'Visible' } else { 'Collapsed' }
    $script:Ui.MediaOptions.Columns = if ($script:Ui.VideoMode.IsChecked -and $script:Ui.AudioMode.IsChecked) { 2 } else { 1 }
}
function New-BwAnimation([double]$From,[double]$To,[double]$Seconds,[bool]$Repeat=$false,[bool]$Reverse=$false) {
    $a=[Windows.Media.Animation.DoubleAnimation]::new()
    $a.From=$From; $a.To=$To; $a.Duration=[Windows.Duration]::new([TimeSpan]::FromSeconds($Seconds))
    if ($Repeat) { $a.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever }
    $a.AutoReverse=$Reverse
    return $a
}
function Set-BwMotion {
    $d=$script:Ui.DeckDrift
    $d.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$null)
    if ($script:Ui.Motion.IsChecked) {
        $d.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,(New-BwAnimation -17 17 14 $true $true))
    }
    Draw-BwVoyage
    Set-BwMeter $script:Meter $script:MeterRun
}
function Set-BwSound {
    try {
        if ($script:Ui.SeaSound.IsChecked) {
            if (!$script:Sound) {
                Add-Type -AssemblyName System
                $script:Sound = [Media.SoundPlayer]::new((Join-Path $script:AppRoot 'assets\Night-Sea.wav'))
                $script:Sound.Load()
            }
            $script:Sound.PlayLooping()
        } elseif ($script:Sound) { $script:Sound.Stop() }
    } catch { Add-BwLog "Sea ambience is unavailable: $($_.Exception.Message)"; $script:Ui.SeaSound.IsChecked=$false }
}
function Set-BwMeter($Value,[bool]$Active) {
    $script:Meter=$Value; $script:MeterRun=$Active
    $length=[Math]::Max(0,$script:Ui.MeterTrack.ActualWidth)
    $unknown = ($null -eq $Value)
    $bar=$script:Ui.MeterFill; $sweep=$script:Ui.MeterSweep; $shift=$script:Ui.SweepShift
    $script:Ui.AccessibleMeter.IsIndeterminate=($Active -and $unknown)
    $script:Ui.AccessibleMeter.Value = if ($unknown) { 0 } else { $Value }
    $script:Ui.Percent.Text = if ($unknown) { '—' } else { '{0:0.#}%' -f $Value }
    $end=if ($unknown) { 0 } else { [Math]::Max(0,[Math]::Min($length,$length*[double]$Value/100.0)) }
    $smooth = $script:Ui.Motion.IsChecked -and $Active -and $length -gt 35
    $start = $bar.Width
    $bar.BeginAnimation([Windows.FrameworkElement]::WidthProperty,$null)
    $bar.Width = $end
    if ($smooth -and !$unknown -and [Math]::Abs($start-$end) -ge 1) {
        $animation = New-BwAnimation $start $end .21
        $animation.FillBehavior = 'Stop'
        $bar.BeginAnimation([Windows.FrameworkElement]::WidthProperty,$animation)
    }
    $sweeping = $smooth -and $unknown
    if ([string]$sweep.Tag -ne "$Active-$unknown-$sweeping-$([int]$length)") {
        $sweep.Tag = "$Active-$unknown-$sweeping-$([int]$length)"
        $shift.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$null)
        $sweep.Opacity = if ($sweeping) { .95 } elseif ($Active -and $unknown) { .55 } else { 0 }
        $shift.X = if ($Active -and $unknown -and !$sweeping) { 0 } else { -55 }
        if ($sweeping) { $shift.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,(New-BwAnimation -55 $length 1.4 $true)) }
    }
}
function Set-BwActive([string]$Status,[string]$Title,[string]$Detail,[string]$Telemetry) {
    $script:Ui.ActiveStatus.Text=$Status
    $script:Ui.ActiveTitle.Text=$Title
    $script:Ui.ActiveDetail.Text=$Detail
    $script:Ui.Telemetry.Text=$Telemetry
}
function New-BwRow($Job,[string]$Status,[string]$Detail) {
    $label = ([uri]$Job.Url).Host
    $uri = [uri]$Job.Url
    if ($uri.AbsolutePath -ne '/') { $label += $uri.AbsolutePath }
    $row=[Blackwake.QueueRow]::new()
    $row.Id=$script:NextId; $row.Job=$Job; $row.Url=$Job.Url; $row.Label=$label
    $row.Status=$Status; $row.Detail=$Detail; $row.Ink='#A0C6BA'
    return $row
}
function Update-BwRow($Row,[string]$Status,[string]$Detail) {
    $Row.Status=$Status; $Row.Detail=$Detail
    $colors=@{ Complete='#A3D6BB'; Partial='#EFCA85'; Failed='#FFAF9C'; Cancelled='#E8C0A5'; 'No captions'='#EAC684'; 'No files'='#EAC684'; Running='#F1CD8B'; Queued='#9DCBBF' }
    $Row.Ink=$colors[$Status]
}
function Update-BwQueue {
    $waiting=@($script:Rows | Where-Object { $_.Status -eq 'Queued' }).Count
    $script:Ui.QueueCount.Text = "$waiting WAITING"
    $script:Ui.EmptyQueue.Visibility=if ($script:Rows.Count) { 'Collapsed' } else { 'Visible' }
    $row=$script:Ui.Jobs.SelectedItem
    $script:Ui.Cancel.IsEnabled=($null -ne $script:Run -and !$script:Run.Token.IsCancellationRequested)
    $script:Ui.Remove.IsEnabled=($null -ne $row -and $row.Status -eq 'Queued')
    $script:Ui.Retry.IsEnabled=($null -ne $row -and $row.Status -in @('Failed','Partial','Cancelled','No captions','No files'))
    $script:Ui.Clear.IsEnabled=(@($script:Rows | Where-Object { $_.Status -notin @('Queued','Running') }).Count -gt 0)
    $script:Ui.ShowFiles.Content="Saved files ($($script:Saved.Count))"
}
function Get-BwDestination {
    $value = $script:Ui.Destination.Text.Trim()
    if (!$value -or $value -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Choose an absolute Windows folder or use Browse.' }
    return [IO.Path]::GetFullPath($value)
}
function Submit-BwQueue {
    try {
        Show-BwError ''
        $links = @(Get-BwLinks $script:Ui.Links.Text)
        if (!$links.Count) { throw 'Paste at least one source link.' }
        $modes = @()
        if ($script:Ui.VideoMode.IsChecked) { $modes+='MP4' }
        if ($script:Ui.AudioMode.IsChecked) { $modes+='MP3' }
        if ($script:Ui.CaptionMode.IsChecked) { $modes+='Captions' }
        if (!$modes.Count) { throw 'Choose at least one cargo type.' }
        $destination = Get-BwDestination
        $language = if ($modes -contains 'Captions') { Get-BwLanguages $script:Ui.Languages.Text } else { '' }
        $scope = if ($script:Ui.Collection.IsChecked) { 'collection' } else { 'single' }
        $null = [IO.Directory]::CreateDirectory($destination)
        foreach ($link in $links) {
            $job=[pscustomobject]@{ Url=$link; Modes=$modes; Scope=$scope; Destination=$destination; Languages=$language
                Height=[int]$script:Ui.HeightChoice.SelectedItem.Tag; AudioQuality=[string]$script:Ui.QualityChoice.SelectedItem.Tag
                CaptionFormat=[string]$script:Ui.CaptionChoice.SelectedItem.Tag; AutoCaptions=[bool]$script:Ui.AutoCaptions.IsChecked }
            $tag = ($modes -replace '^Captions$','Transcript') -join ' + '
            $tag += if ($scope -eq 'collection') { '  /  Playlist or channel' } else { '  /  Single item' }
            $row=New-BwRow $job 'Queued' $tag
            $script:NextId+=1; $script:Rows.Add($row)
        }
        $script:Ui.Links.Clear(); Save-BwPrefs; Update-BwQueue
        if (!$script:Run -and !$script:Setup -and !(Update-BwTools)) {
            $script:Hold=$true
            if (Show-BwChoice 'Ready the Shipyard?' 'Simple Pyrate needs yt-dlp, FFmpeg, FFprobe and Deno available on the Windows system PATH. Your queued hauls will start after setup.' 'Install missing tools' 'Later') { Start-BwSetup $false }
            else { Show-BwError 'Haul queued. Open Shipyard to install the required tools.' }
        } else { $script:Hold=$false; Start-BwNext }
    } catch { Show-BwError $_.Exception.Message }
}
function Start-BwNext {
    if ($script:Closing -or $script:Hold -or $script:Run -or $script:Setup) { return }
    $row = $script:Rows | Where-Object { $_.Status -eq 'Queued' } | Select-Object -First 1
    if (!$row) {
        if ($script:Voyage.Running) { Complete-BwVoyage $script:VoyageStatus $false }
        return
    }
    if (!(Update-BwTools)) {
        $script:Hold=$true
        Complete-BwVoyage 'Failed' $false
        Show-BwError 'Open Shipyard to install the required tools.'
        return
    }
    $worker=[PowerShell]::Create()
    $source=[Threading.CancellationTokenSource]::new()
    try {
        $script:Current=$row
        Update-BwRow $row 'Running' 'Resolving the source'
        Set-BwActive 'UNDERWAY' $row.Label 'Resolving the source' 'Contacting the site'
        Set-BwMeter $null $true
        $null=$worker.AddScript({
            param($engine,$job,$tools,$events,$source)
            . $engine
            Invoke-BwJob $job $tools $events $source
        }.ToString()).AddArgument((Join-Path $script:AppRoot 'Engine.ps1')).AddArgument($row.Job).AddArgument($script:Tools).AddArgument($script:Events).AddArgument($source)
        $script:Run=[pscustomobject]@{ Worker=$worker; Token=$source; Handle=$worker.BeginInvoke(); Result=$null; Phase='' }
        $script:Voyage.Start($script:VoyageClock.Elapsed.TotalSeconds)
        if (!$script:Ui.Motion.IsChecked) { Draw-BwVoyage }
        Add-BwLog "Haul $($row.Id) started for $($row.Label)."
        Update-BwQueue
    } catch {
        $worker.Dispose(); $source.Dispose()
        $script:Run=$null; $script:Current=$null
        $script:VoyageStatus='Failed'
        Complete-BwVoyage 'Failed' (Test-BwVoyageContinuing)
        Update-BwRow $row 'Failed' 'Could not start the download worker'
        Set-BwActive 'FAILED' $row.Label 'Could not start the download worker' 'See the ship''s log'
        Set-BwMeter 0 $false
        Add-BwLog $_.Exception.Message; Update-BwQueue
    }
}
function Read-BwEvents {
    if (!$script:Run) { return }
    for ($i=0; $i -lt 160; $i++) {
        [object]$msg=$null
        if (!$script:Events.TryDequeue([ref]$msg)) { break }
        $data=$msg.Data
        $stopping = $script:Run.Token.IsCancellationRequested
        switch ($msg.Kind) {
            'log' { Add-BwLog $data }
            'phase' {
                $script:Run.Phase=$data
                if ($stopping) { break }
                $script:Voyage.ResolvePort()
                $detail=if ($data -eq 'Captions') { 'Finding matching caption tracks' } else { "Preparing $data" }
                Set-BwActive 'UNDERWAY' $script:Current.Label $detail 'Resolving media'
                Set-BwMeter $null $true
            }
            'port' {
                if ($stopping) { break }
                $position = if ($data.Index -and $data.Count) { "Item $($data.Index) of $($data.Count)" }
                    elseif ($data.Index) { "Item $($data.Index)" } else { '' }
                $script:Voyage.EnterPort([string]$data.Mode,[string]$data.Title,[string]$position)
                if (!$script:Ui.Motion.IsChecked) { Draw-BwVoyage }
            }
            'port-done' { if (!$stopping) { $script:Voyage.ResolvePort() } }
            'source-wait' {
                if ($stopping) { break }
                $elapsed=([Diagnostics.Stopwatch]::GetTimestamp()-[long]$data.Observed)/[double][Diagnostics.Stopwatch]::Frequency
                $seconds=[Math]::Max(0,([double]$data.Seconds-$elapsed))
                if ($seconds -ge .15) { $script:Voyage.BeginWait($script:VoyageClock.Elapsed.TotalSeconds,$seconds,'Source-requested pause') }
            }
            'title' {
                if (!$stopping) { $script:Ui.ActiveTitle.Text=[string]$data }
            }
            'processing' {
                if (!$stopping) {
                    $script:Voyage.SignalActivity()
                    if ($data.Title) { $script:Ui.ActiveTitle.Text=$data.Title }
                    $script:Ui.ActiveStatus.Text='PROCESSING'
                    $script:Ui.ActiveDetail.Text="Finishing $($script:Run.Phase)"
                    $script:Ui.Telemetry.Text=$data.Operation
                    Set-BwMeter $null $true
                }
            }
            'progress' {
                if ($stopping) { break }
                $script:Voyage.SignalActivity()
                if ($data.Title) { $script:Ui.ActiveTitle.Text=$data.Title }
                $script:Ui.ActiveStatus.Text='UNDERWAY'
                $detail=if ($data.Mode -eq 'Captions') { 'Downloading captions' } else { "Downloading $($data.Mode)" }
                if ($data.Index -and $data.Count) { $detail+="  /  Item $($data.Index) of $($data.Count)" }
                elseif ($data.Index) { $detail+="  /  Item $($data.Index)" }
                $script:Ui.ActiveDetail.Text=$detail
                $telemetry=@()
                if ($data.Speed -and $data.Speed.Trim() -notin @('Unknown B/s','NA')) { $telemetry+=$data.Speed.Trim() }
                if ($data.Eta -and $data.Eta.Trim() -notin @('Unknown','NA')) { $telemetry+=('ETA ' + $data.Eta.Trim()) }
                $script:Ui.Telemetry.Text=if ($telemetry.Count) { $telemetry -join '   /   ' } else { 'Current transfer' }
                Set-BwMeter $data.Percent $true
            }
            'file' {
                if ($script:SavedPaths.Add($data)) {
                    $savedFile=[Blackwake.SavedFile]::new()
                    $savedFile.Name=[IO.Path]::GetFileName($data); $savedFile.Path=$data
                    $script:Saved.Add($savedFile)
                }
                $script:Ui.ShowFiles.Content="Saved files ($($script:Saved.Count))"
                Add-BwLog "Saved $data"
            }
            'done' { $script:Run.Result=$data }
        }
    }
    if (!$script:Run.Handle.IsCompleted -or !$script:Events.IsEmpty) { return }
    try {
        $null=$script:Run.Worker.EndInvoke($script:Run.Handle)
        foreach ($err in $script:Run.Worker.Streams.Error) { Add-BwLog $err.ToString() }
    } catch { Add-BwLog $_.Exception.Message }
    $done=$script:Run.Result
    if (!$done) { $done=@{ Status='Failed'; Files=0; Errors=1; Missing=0 } }
    $script:Run.Worker.Dispose(); $script:Run.Token.Dispose(); $script:Run=$null
    $script:VoyageStatus=$done.Status
    Complete-BwVoyage ([string]$done.Status) (Test-BwVoyageContinuing)
    $detail = if ($done.Files -eq 1) { '1 file available' } else { "$($done.Files) files available" }
    if ($done.Missing) { $detail+="  /  $($done.Missing) without matching captions" }
    Update-BwRow $script:Current $done.Status $detail
    Set-BwActive ($done.Status.ToUpperInvariant()) $script:Ui.ActiveTitle.Text $detail $(if ($done.Status -eq 'Complete') { 'Haul secured' } else { 'Details in the ship''s log' })
    Set-BwMeter $(if ($done.Status -eq 'Complete') { 100 } else { 0 }) $false
    $script:Current=$null
    Update-BwQueue
}
function Stop-BwActive {
    if (!$script:Run) { return }
    $script:Run.Token.Cancel()
    $script:Ui.ActiveStatus.Text='STOPPING'
    $script:Ui.ActiveDetail.Text='Stopping yt-dlp and its child processes'
    $script:Ui.Telemetry.Text='Finished files are kept'
    Update-BwQueue
}
function Open-BwPath([string]$Path,[bool]$Folder) {
    try {
        if ($Folder) { $null=[IO.Directory]::CreateDirectory($Path) }
        elseif (![IO.File]::Exists($Path)) { throw 'That file has been moved or deleted.' }
        if (!$Folder -and [IO.Path]::GetExtension($Path) -notin @('.txt','.srt','.mp3','.mp4')) { throw 'That file type cannot be opened from Simple Pyrate.' }
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=$Path; $info.UseShellExecute=$true
        $p=[Diagnostics.Process]::Start($info)
        if ($p) { $p.Dispose() }
    } catch {
        Add-BwLog $_.Exception.Message
        if ($script:Dialog) { $script:Dialog.Text=$_.Exception.Message } else { Show-BwError $_.Exception.Message }
    }
}
function Show-BwLog {
    $d=New-BwDialog 'Ship''s log' 850 500
    $view=[Windows.Controls.TextBox]::new()
    $view.IsReadOnly=$true; $view.AcceptsReturn=$true; $view.TextWrapping='Wrap'; $view.VerticalContentAlignment='Stretch'
    $view.VerticalScrollBarVisibility='Auto'; $view.FontFamily=[Windows.Media.FontFamily]::new('Consolas')
    $view.Text=if ($script:Lines.Count) { $script:Lines -join [Environment]::NewLine } else { 'The log is empty. Download and setup messages appear here.' }
    $null=$d.Body.Children.Add($view)
    $copy=New-BwDialogButton $d.Buttons 'Copy log'
    $copy.add_Click({ param($sender,$e) try { [Windows.Clipboard]::SetText(($script:Lines -join [Environment]::NewLine)); $sender.Content='Copied' } catch { $sender.Content='Clipboard unavailable' } })
    $close=New-BwDialogButton $d.Buttons 'Close'; $close.IsCancel=$true
    $d.Window.add_Loaded({ if ($null -ne $script:OpenLog) { $script:OpenLog.ScrollToEnd() } })
    $script:OpenLog=$view
    try { $null=$d.Window.ShowDialog() } finally { $script:OpenLog=$null }
}
function Show-BwFiles {
    $d=New-BwDialog 'Saved files' 760 480
    $list=[Windows.Controls.ListBox]::new(); $list.DisplayMemberPath='Name'; $list.ItemsSource=$script:Saved
    [Windows.Automation.AutomationProperties]::SetName($list,'Files saved in this session')
    $note=[Windows.Controls.TextBlock]::new(); $note.Text='Select a file to open it or its folder.'
    $note.TextWrapping='Wrap'; $note.Margin=[Windows.Thickness]::new(0,0,0,8)
    [Windows.Controls.DockPanel]::SetDock($note,'Top'); $null=$d.Body.Children.Add($note)
    $null=$d.Body.Children.Add($list)
    $open=New-BwDialogButton $d.Buttons 'Open file'
    $folder=New-BwDialogButton $d.Buttons 'Open containing folder'
    $open.Tag=$list; $folder.Tag=$list
    $open.add_Click({ param($sender,$e) if ($sender.Tag.SelectedItem) { Open-BwPath $sender.Tag.SelectedItem.Path $false } })
    $folder.add_Click({ param($sender,$e) if ($sender.Tag.SelectedItem) { Open-BwPath ([IO.Path]::GetDirectoryName($sender.Tag.SelectedItem.Path)) $true } })
    $list.add_MouseDoubleClick({ param($sender,$e) if ($sender.SelectedItem) { Open-BwPath $sender.SelectedItem.Path $false } })
    $close=New-BwDialogButton $d.Buttons 'Close'; $close.IsCancel=$true
    $script:Dialog=$note
    try { $null=$d.Window.ShowDialog() } finally { $script:Dialog=$null }
}
function Pick-BwFolder {
    $d=New-BwDialog 'Choose a save folder' 720 480
    $location=[Windows.Controls.TextBox]::new()
    [Windows.Automation.AutomationProperties]::SetName($location,'Folder path')
    $location.Margin=[Windows.Thickness]::new(0,0,0,7)
    [Windows.Controls.DockPanel]::SetDock($location,'Top'); $null=$d.Body.Children.Add($location)
    $errorNote=[Windows.Controls.TextBlock]::new(); $errorNote.Text='Double-click a folder to open it. Enter a new path to use a new folder.'
    $errorNote.TextWrapping='Wrap'; $errorNote.Margin=[Windows.Thickness]::new(0,0,0,8)
    [Windows.Controls.DockPanel]::SetDock($errorNote,'Top'); $null=$d.Body.Children.Add($errorNote)
    $folders=[Windows.Controls.ListBox]::new(); $folders.DisplayMemberPath='Name'
    $null=$d.Body.Children.Add($folders)
    $state=[pscustomobject]@{ Path=$location; Folders=$folders; Note=$errorNote; Current=$null }
    $go=New-BwDialogButton $d.Buttons 'Go to path'; $go.Tag=$state
    $up=New-BwDialogButton $d.Buttons 'Up'; $up.Tag=$state
    $drives=New-BwDialogButton $d.Buttons 'Drives'; $drives.Tag=$state
    $choose=New-BwDialogButton $d.Buttons 'Use this folder' $true; $choose.Tag=$state
    $close=New-BwDialogButton $d.Buttons 'Cancel'; $close.IsCancel=$true
    $folders.Tag=$state; $location.Tag=$state
    $go.add_Click({ param($sender,$e) Set-BwFolderList $sender.Tag $sender.Tag.Path.Text })
    $location.add_KeyDown({ param($sender,$e) if ($e.Key -eq 'Enter') { $e.Handled=$true; Set-BwFolderList $sender.Tag $sender.Text } })
    $up.add_Click({
        param($sender,$e)
        if (!$sender.Tag.Current) { return }
        $parent=[IO.Directory]::GetParent($sender.Tag.Current)
        if ($parent) { Set-BwFolderList $sender.Tag $parent.FullName } else { Set-BwFolderList $sender.Tag '' }
    })
    $drives.add_Click({ param($sender,$e) Set-BwFolderList $sender.Tag '' })
    $folders.add_MouseDoubleClick({ param($sender,$e) if ($sender.SelectedItem) { Set-BwFolderList $sender.Tag $sender.SelectedItem.Path } })
    $folders.add_KeyDown({ param($sender,$e) if ($e.Key -eq 'Enter' -and $sender.SelectedItem) { $e.Handled=$true; Set-BwFolderList $sender.Tag $sender.SelectedItem.Path } })
    $choose.add_Click({
        param($sender,$e)
        $p=$sender.Tag.Path.Text.Trim()
        if ($p -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { $sender.Tag.Note.Text='Enter a complete folder path or choose a drive.'; return }
        try {
            $script:Ui.Destination.Text=[IO.Path]::GetFullPath($p)
            [Windows.Window]::GetWindow($sender).DialogResult=$true
        } catch { $sender.Tag.Note.Text=$_.Exception.Message }
    })
    $initial=$script:Ui.Destination.Text; $scan=$initial
    if (![IO.Directory]::Exists($scan)) {
        try { $scan=[IO.Path]::GetDirectoryName($scan) } catch { $scan='' }
        if (![IO.Directory]::Exists($scan)) { $scan=[Environment]::GetFolderPath('UserProfile') }
    }
    Set-BwFolderList $state $scan
    if ($initial) { $location.Text=$initial }
    $null=$d.Window.ShowDialog()
}
function Set-BwFolderList($State,[string]$Path) {
    try {
        if (!$Path) {
            $State.Folders.ItemsSource=@([IO.DriveInfo]::GetDrives() | ForEach-Object { $entry=[Blackwake.FolderEntry]::new(); $entry.Name=$_.Name; $entry.Path=$_.Name; $entry })
            $State.Path.Clear(); $State.Current=$null
        } else {
            $dir=[IO.DirectoryInfo]::new($Path)
            $State.Folders.ItemsSource=@($dir.EnumerateDirectories() | Where-Object {
                ($_.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) -eq 0
            } | Sort-Object Name | ForEach-Object { $entry=[Blackwake.FolderEntry]::new(); $entry.Name=$_.Name; $entry.Path=$_.FullName; $entry })
            $State.Path.Text=$dir.FullName; $State.Current=$dir.FullName
        }
        $State.Note.Text='Double-click a folder to open it. Enter a new path to use a new folder.'
    } catch { $State.Note.Text=$_.Exception.Message }
}
function Set-BwResponsive {
    $stack = $script:Deck.ActualWidth -lt 940
    $sceneHeight=[Math]::Max(175,[Math]::Min(310,[Math]::Round($script:Deck.ActualHeight*.36)))
    $script:Ui.VoyageRow.Height=[Windows.GridLength]::new($sceneHeight)
    if ($stack) {
        $script:Ui.BoardRight.Width=[Windows.GridLength]::new(0)
        $script:Ui.BoardGap.Width=[Windows.GridLength]::new(0)
        $script:Ui.MobileRow.Height=[Windows.GridLength]::new(13)
        [Windows.Controls.Grid]::SetColumn($script:Ui.FlightCard,0); [Windows.Controls.Grid]::SetRow($script:Ui.FlightCard,2)
    } else {
        $script:Ui.BoardRight.Width=[Windows.GridLength]::new(1,'Star')
        $script:Ui.BoardGap.Width=[Windows.GridLength]::new(14)
        $script:Ui.MobileRow.Height=[Windows.GridLength]::new(0)
        [Windows.Controls.Grid]::SetColumn($script:Ui.FlightCard,2); [Windows.Controls.Grid]::SetRow($script:Ui.FlightCard,0)
    }
}

$script:StartupStage = 'Wiring the deck controls'
Load-BwPrefs
Update-BwOptions
Update-BwQueue
$script:Ui.Links.add_TextChanged({ param($sender,$e) $script:Ui.LinkHint.Visibility=if ($sender.Text) { 'Collapsed' } else { 'Visible' } })
foreach ($key in @('VideoMode','AudioMode','CaptionMode')) {
    $script:Ui[$key].add_Checked({ Update-BwOptions }); $script:Ui[$key].add_Unchecked({ Update-BwOptions })
}
$script:Ui.Paste.add_Click({
    try {
        if (![Windows.Clipboard]::ContainsText()) { throw 'The clipboard does not contain text.' }
        $existing=$script:Ui.Links.Text.TrimEnd()
        $script:Ui.Links.Text=if ($existing) { $existing+[Environment]::NewLine+[Windows.Clipboard]::GetText() } else { [Windows.Clipboard]::GetText() }
        $script:Ui.Links.CaretIndex=$script:Ui.Links.Text.Length
        $null=$script:Ui.Links.Focus()
    } catch { Show-BwError $_.Exception.Message }
})
$script:Ui.Motion.add_Checked({ Set-BwMotion }); $script:Ui.Motion.add_Unchecked({ Set-BwMotion })
$script:Ui.SeaSound.add_Checked({ Set-BwSound }); $script:Ui.SeaSound.add_Unchecked({ Set-BwSound })
$script:Ui.Queue.add_Click({ param($sender,$e) Submit-BwQueue })
$script:Ui.Browse.add_Click({ param($sender,$e) Pick-BwFolder })
$script:Ui.OpenFolder.add_Click({ param($sender,$e) try { Open-BwPath (Get-BwDestination) $true } catch { Show-BwError $_.Exception.Message } })
$script:Ui.ShowFiles.add_Click({ param($sender,$e) Show-BwFiles })
$script:Ui.ShowLog.add_Click({ param($sender,$e) Show-BwLog })
$script:Ui.ShowTools.add_Click({ param($sender,$e) Show-BwShipyard })
$script:Ui.Cancel.add_Click({ param($sender,$e) Stop-BwActive })
$script:Ui.Jobs.add_SelectionChanged({ Update-BwQueue })
$script:Ui.Remove.add_Click({ param($sender,$e) $row=$script:Ui.Jobs.SelectedItem; if ($row -and $row.Status -eq 'Queued') { $null=$script:Rows.Remove($row); Update-BwQueue } })
$script:Ui.Retry.add_Click({
    $row=$script:Ui.Jobs.SelectedItem
    if ($row -and $row.Status -in @('Failed','Partial','Cancelled','No captions','No files')) {
        Update-BwRow $row 'Queued' 'Waiting to retry'; Update-BwQueue; $script:Hold=$false; Start-BwNext
    }
})
$script:Ui.Clear.add_Click({
    foreach ($row in @($script:Rows | Where-Object { $_.Status -notin @('Queued','Running') })) { $null=$script:Rows.Remove($row) }
    Update-BwQueue
})
$script:Ui.MeterTrack.add_SizeChanged({ Set-BwMeter $script:Meter $script:MeterRun })
$script:Deck.add_SizeChanged({ Set-BwResponsive })
$script:Deck.add_PreviewKeyDown({
    param($sender,$e)
    if ($e.Key -eq 'Enter' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) { $e.Handled=$true; Submit-BwQueue }
})
$script:VoyageTimer=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
$script:VoyageTimer.Interval=[TimeSpan]::FromMilliseconds(33)
$script:VoyageTimer.add_Tick({
    if ($script:Deck.IsVisible -and $script:Deck.WindowState -ne 'Minimized' -and
        ($script:Ui.Motion.IsChecked -or $script:Voyage.NeedsClock)) {
        try { Draw-BwVoyage } catch {
            $script:VoyageTimer.Stop()
            Add-BwLog "Voyage playback stopped: $($_.Exception.Message)"
        }
    }
})
$script:Timer=[Windows.Threading.DispatcherTimer]::new()
$script:Timer.Interval=[TimeSpan]::FromMilliseconds(110)
$script:Timer.add_Tick({
    try {
        if ($script:Setup -and $script:Setup.HasExited) {
            $exitResult=$script:Setup.ExitCode
            $script:Setup.Dispose(); $script:Setup=$null
            $ready=Update-BwTools
            if ($exitResult -eq 0 -and $ready) { $script:Hold=$false; Show-BwError ''; Add-BwLog 'Shipyard setup finished.' }
            else { $script:Hold=!$ready; Show-BwError 'Setup did not finish successfully. Open Shipyard to retry.' }
        }
        Read-BwEvents
        if ($script:Closing -and !$script:Run) { $script:Deck.Close(); return }
        Start-BwNext
    } catch { Add-BwLog "Deck error: $($_.Exception.Message)" }
})
$script:Deck.add_Loaded({
    if ($script:SmokeTest) { return }
    Set-BwResponsive; Set-BwMotion; Set-BwSound; $null=$script:Ui.Links.Focus()
    $ready=Update-BwTools
    Add-BwLog 'Simple Pyrate v2.5.1 is ready for links.'
    $script:Timer.Start()
    $script:VoyageTimer.Start()
    if (!$ready) {
        $script:Hold=$true
        if (Show-BwChoice 'Welcome aboard' 'Simple Pyrate can install any missing media tools to the Windows system PATH. Windows will ask for administrator approval.' 'Install missing tools' 'Later') { Start-BwSetup $false }
    }
})
$script:Deck.add_Closing({
    param($sender,$e)
    if ($script:Run -and !$script:ClosingConfirmed) {
        $e.Cancel=$true
        if (Show-BwChoice 'Leave the deck?' 'The active transfer will stop and waiting jobs will be cleared. Completed files already on disk are kept.' 'Stop and close' 'Keep working') {
            $script:ClosingConfirmed=$true; $script:Closing=$true; Stop-BwActive
        }
    } elseif ($script:Setup) {
        $e.Cancel=$true
        Show-BwError 'Shipyard is running. Let the Windows setup window finish before closing Simple Pyrate.'
    } elseif ($script:Run) { $e.Cancel=$true }
})
$script:Deck.add_Closed({
    $script:Timer.Stop()
    $script:VoyageTimer.Stop()
    if ($script:Sound) { $script:Sound.Stop(); $script:Sound.Dispose() }
    if (!$script:SmokeTest) { Save-BwPrefs }
})
$script:StartupStage = 'Starting the Windows interface'
if ($SmokeTest) {
    $script:StartupStage = 'Running the Windows startup smoke test'
    $script:Deck.Show()
    $script:Deck.UpdateLayout()
    Set-BwResponsive
    Draw-BwVoyage
    $script:Voyage.Start(0)
    $script:Voyage.EnterPort('Captions','Smoke test','')
    $script:Voyage.SignalActivity()
    $shot=$script:Voyage.Tick(0,$false)
    $script:VoyageArt.Present($shot,0,$false)
    $script:Deck.UpdateLayout()
    $script:Deck.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Render)
    $preview=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$script:VoyageArt.ActualWidth,[int]$script:VoyageArt.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $preview.Render($script:VoyageArt)
    if ($shot.Shot -ne [Pyrate.Shot]::Battle -or $preview.PixelWidth -lt 400 -or $preview.PixelHeight -lt 150) { throw 'Voyage render smoke check failed.' }
    $stride = $preview.PixelWidth * 4
    $pixels = [byte[]]::new($stride * $preview.PixelHeight)
    $preview.CopyPixels($pixels,$stride,0)
    $colors = [Collections.Generic.HashSet[int]]::new()
    for ($y = 10; $y -lt $preview.PixelHeight; $y += 16) {
        for ($x = 10; $x -lt $preview.PixelWidth; $x += 16) {
            $offset = $y * $stride + $x * 4
            if ($pixels[$offset + 3] -eq 0) { continue }
            $rgb = ([int]$pixels[$offset + 2] -shl 16) -bor ([int]$pixels[$offset + 1] -shl 8) -bor [int]$pixels[$offset]
            $null = $colors.Add($rgb)
        }
    }
    if ($colors.Count -lt 16) { throw 'Voyage render is blank or missing its artwork.' }
    Set-BwMeter 37 $false
    if ($script:Ui.AccessibleMeter.Value -ne 37 -or $script:Ui.MeterFill.Width -le 0) { throw 'Progress meter smoke check failed.' }
    $script:Ui.CaptionMode.IsChecked=$true
    if ($script:Ui.CaptionOptions.Visibility -ne 'Visible') { throw 'Caption options smoke check failed.' }
    $script:Deck.Width=820
    $script:Deck.UpdateLayout()
    Set-BwResponsive
    if ([Windows.Controls.Grid]::GetRow($script:Ui.FlightCard) -ne 2) { throw 'Responsive layout smoke check failed.' }
    $script:Deck.Close()
    Write-Output 'Simple Pyrate v2.5.1 WPF smoke test passed.'
} else { $null=$script:Deck.ShowDialog() }
exit 0
} catch {
    $failure = $_
    $details = @(
        'Simple Pyrate v2.5.1 could not open the chart room.'
        "Stage: $script:StartupStage"
        "PowerShell: $($PSVersionTable.PSVersion)"
        $failure.ToString()
        $failure.ScriptStackTrace
        $failure.Exception.ToString()
    ) -join [Environment]::NewLine
    $logPath = $null
    try {
        $profileRoot = [Environment]::GetFolderPath('LocalApplicationData')
        if ($profileRoot) {
            $logFolder = Join-Path $profileRoot 'BGGG\Blackwake'
            $null = [IO.Directory]::CreateDirectory($logFolder)
            $logPath = Join-Path $logFolder 'startup-error.log'
            [IO.File]::WriteAllText($logPath,$details,[Text.UTF8Encoding]::new($false))
        }
    } catch { $logPath = $null }
    try { [Console]::Error.WriteLine($details) } catch { }
    if (!$SmokeTest) {
        $message = "Simple Pyrate v2.5.1 could not open the chart room.`r`n`r`nStage: $script:StartupStage`r`n$($failure.Exception.Message)"
        if ($logPath) { $message += "`r`n`r`nStartup log: $logPath" }
        try { $null = [Windows.MessageBox]::Show($message,'Simple Pyrate v2.5.1') } catch { }
    }
    exit 1
}
