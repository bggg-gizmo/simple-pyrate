Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function ConvertTo-BwWindowsArg([AllowEmptyString()][string]$Value) {
    if ($Value -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function Join-BwArguments([string[]]$Arguments) {
    return (($Arguments | ForEach-Object { ConvertTo-BwWindowsArg $_ }) -join ' ')
}
function Get-BwValue($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.PSObject.Properties[$Name].Value }
    return $Default
}
function Get-BwLinks([string]$Text) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in ($Text -split '\r?\n|\r')) {
        $link = $line.Trim()
        if (!$link) { continue }
        [uri]$parsed = $null
        if ($link.Length -gt 8192 -or $link -match '[\x00-\x20\x7f\\]' -or
            ![uri]::TryCreate($link, [UriKind]::Absolute, [ref]$parsed) -or
            $parsed.Scheme -notin @('http','https') -or !$parsed.Host -or $parsed.UserInfo) {
            throw "Use one complete HTTP or HTTPS link per line. Invalid line: $($link.Substring(0,[Math]::Min(100,$link.Length)))"
        }
        if ($seen.Add($link)) { $link }
    }
}
function Get-BwLanguages([string]$Value) {
    $items = @($Value -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if (!$items.Count) { throw 'Enter a caption language such as en, or enter all.' }
    if ($items -contains 'all') {
        if ($items.Count -ne 1) { throw 'Use all by itself or list specific caption languages.' }
        return 'all,-live_chat'
    }
    foreach ($code in $items) {
        if ($code -notmatch '^[a-z]{2,3}(-[a-z0-9]{1,8}){0,4}$') { throw "Invalid caption language '$code'. Use language codes such as en, de, or pt-BR." }
    }
    return (($items | ForEach-Object {
        if ($_ -match '-') { '(?i:' + $_ + ')' } else { '(?i:' + $_ + '(?:-[a-z0-9]+)*)' }
    }) -join ',')
}
function Get-BwToolPaths {
    $locations = [Collections.Generic.List[string]]::new()
    $own = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'BGGG\Blackwake\bin'
    foreach ($entry in ([Environment]::GetEnvironmentVariable('Path','Machine') -split ';')) {
        if (!$entry -or !$entry.Trim()) { continue }
        $dir = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
        if ($dir -notmatch '^[A-Za-z]:\\') { continue }
        try {
            $dir = [IO.Path]::GetFullPath($dir)
            if ($dir.Length -gt 3) { $dir=$dir.TrimEnd('\') }
            $locations.Add($dir)
        } catch { continue }
    }
    $tools = @{}
    foreach ($name in @('yt-dlp','ffmpeg','ffprobe','deno')) { $tools[$name] = $null }
    $preferred = @($locations | Where-Object { $_ -ieq $own }) + @($locations | Where-Object { $_ -ine $own })
    foreach ($name in @('yt-dlp','deno')) {
        foreach ($dir in $preferred) {
            $candidate = Join-Path $dir "$name.exe"
            if ([IO.File]::Exists($candidate)) { $tools[$name] = $candidate; break }
        }
    }
    foreach ($dir in $preferred) {
        $ff = Join-Path $dir 'ffmpeg.exe'
        $fp = Join-Path $dir 'ffprobe.exe'
        if ([IO.File]::Exists($ff) -and [IO.File]::Exists($fp)) {
            $tools['ffmpeg'] = $ff; $tools['ffprobe'] = $fp; break
        }
    }
    return $tools
}
function New-BwArguments($Job, [string]$Mode, $Tools) {
    $format = '%(title).100B [%(extractor_key).22B-%(id).42B].%(ext)s'
    $argsList = @('--ignore-config','--no-plugin-dirs','--encoding','utf-8','--no-colors','--newline','--progress','--progress-delta','0.25',
        '--no-overwrites','--continue','--windows-filenames','--no-mtime','--socket-timeout','25','--retries','3','--fragment-retries','3',
        '--ignore-errors','--no-simulate','--no-quiet','--ffmpeg-location',([IO.Path]::GetDirectoryName($Tools['ffmpeg'])),
        '--js-runtimes',('deno:' + $Tools['deno']),
        '-P','.','-o',$format,
        '--progress-template',('download:BW_PROGRESS %(progress._percent_str)j' + "`t" + '%(progress._speed_str)j' + "`t" + '%(progress._eta_str)j' + "`t" + '%(info.title)j' + "`t" + '%(info.playlist_index)j' + "`t" + '%(info.n_entries)j'),
        '--progress-template',('postprocess:BW_PROCESS %(progress.status)j' + "`t" + '%(info.title)j' + "`t" + '%(progress.postprocessor)j'),
        '--print',('video:BW_PORT %(id)j' + "`t" + '%(title)j' + "`t" + '%(playlist_index)j' + "`t" + '%(n_entries)j'),
        '--print',('after_video:BW_ITEM %(id)j' + "`t" + '%(title)j' + "`t" + '%(requested_downloads.0.filepath)j' + "`t" + '%(requested_downloads.0.requested_subtitles,requested_subtitles)j'))
    if ($Job.Scope -eq 'collection') { $argsList += '--yes-playlist' }
    else { $argsList += @('--no-playlist','--playlist-items','1') }
    switch ($Mode) {
        'MP4' {
            $limit = if ($Job.Height -gt 0) { "[height<=$($Job.Height)]" } else { '' }
            $spec = "bv*${limit}+ba/b${limit}/bv${limit}"
            $argsList += @('-f',$spec,'--merge-output-format','mp4/mkv','--recode-video','mp4')
        }
        'MP3' { $argsList += @('-f','bestaudio/best','--extract-audio','--audio-format','mp3','--audio-quality',$Job.AudioQuality) }
        'Captions' {
            $argsList += @('--skip-download','--ignore-no-formats-error','--write-subs','--sub-langs',$Job.Languages,
                '--sub-format','srt/vtt/best','--convert-subs','srt')
            if ($Job.AutoCaptions) { $argsList += '--write-auto-subs' }
        }
        default { throw "Unknown output mode $Mode." }
    }
    $argsList += @('--',$Job.Url)
    return $argsList
}
function ConvertFrom-BwTranscript([string]$Text) {
    $written = [Collections.Generic.List[string]]::new()
    [string[]]$previous = @()
    $groups = [regex]::Split(($Text -replace '\r','').TrimStart([char]0xFEFF), '\n[ \t]*\n+')
    foreach ($group in $groups) {
        $cue = $group -split '\n'
        $start = -1
        for ($i = 0; $i -lt $cue.Count; $i++) {
            if ($cue[$i] -match '^\s*(?:\d+:)?\d{2}:\d{2}[,.]\d{3}\s+-->\s+') { $start = $i; break }
        }
        if ($start -lt 0 -or $start -ge $cue.Count-1) { continue }
        $words = ($cue[($start + 1)..($cue.Count - 1)] -join ' ') -replace '<[^>]*>','' -replace '\{\\[^}]*\}',''
        $words = [Net.WebUtility]::HtmlDecode($words).Trim()
        if (!$words) { continue }
        [string[]]$tokens = $words -split '\s+'
        $overlap = 0
        for ($count = [Math]::Min($previous.Count,$tokens.Count); $count -gt 0; $count--) {
            $equal = $true
            for ($j = 0; $j -lt $count; $j++) {
                if ($previous[($previous.Count-$count+$j)] -cne $tokens[$j]) { $equal = $false; break }
            }
            if ($equal) { $overlap = $count; break }
        }
        if ($overlap -eq 1 -and $tokens.Count -gt 1) { $overlap = 0 }
        if ($overlap -lt $tokens.Count) { $written.Add(($tokens[$overlap..($tokens.Count-1)] -join ' ')) }
        $previous = $tokens
    }
    if ($written.Count) { return ($written -join [Environment]::NewLine) + [Environment]::NewLine }
    return ''
}
function Get-BwContainedFile([string]$Path, [string]$Root) {
    if (!$Path) { return $null }
    try {
        $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $Root $Path)) }
        $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if (!$full.StartsWith($prefix,$comparison) -or ![IO.File]::Exists($full)) { return $null }
        return $full
    } catch { return $null }
}
function Write-BwTextFile([string]$Path, [string]$Text) {
    if ([IO.File]::Exists($Path)) { return }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new($false))
        try { [IO.File]::Move($temporary,$Path) }
        catch [IO.IOException] { if (![IO.File]::Exists($Path)) { throw } }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Publish-Bw($Events, [string]$Kind, $Data) {
    $Events.Enqueue([pscustomobject]@{ Kind=$Kind; Data=$Data })
}
function ConvertFrom-BwJson([string]$Value) {
    if (!$Value -or $Value -eq 'NA' -or $Value -eq 'null') { return $null }
    return (ConvertFrom-Json -InputObject $Value)
}
function Stop-BwChild([Diagnostics.Process]$Process) {
    if ($Process.HasExited) { return }
    if ([IO.Path]::DirectorySeparatorChar -eq '\') {
        $kill = [Diagnostics.ProcessStartInfo]::new()
        $kill.FileName = Join-Path ([Environment]::SystemDirectory) 'taskkill.exe'
        $kill.Arguments = "/F /T /PID $($Process.Id)"
        $kill.UseShellExecute = $false
        $kill.CreateNoWindow = $true
        try {
            $killer = [Diagnostics.Process]::Start($kill)
            try { $null = $killer.WaitForExit(3000) } finally { $killer.Dispose() }
        } catch { }
    }
    try { if (!$Process.HasExited) { $Process.Kill() } } catch { }
}
function Invoke-BwProcess([string]$Exe,[string[]]$Arguments,[scriptblock]$HandleLine,$Cancel,[string]$WorkingDirectory) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Exe
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    $start.Arguments = Join-BwArguments $Arguments
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        $started = $process.Start()
        if (!$started) { throw "Could not start $Exe." }
        $process.StandardInput.Close()
        $streams = @($process.StandardOutput,$process.StandardError)
        $reads = @($streams[0].ReadLineAsync(),$streams[1].ReadLineAsync())
        while ($null -ne $reads[0] -or $null -ne $reads[1] -or !$process.HasExited) {
            if ($Cancel.IsCancellationRequested) { Stop-BwChild $process; return -999 }
            $ready = $false
            for ($i=0; $i -lt 2; $i++) {
                if ($null -eq $reads[$i] -or !$reads[$i].IsCompleted) { continue }
                $ready = $true
                $line = $reads[$i].GetAwaiter().GetResult()
                if ($null -eq $line) { $reads[$i] = $null }
                else {
                    $reads[$i] = $streams[$i].ReadLineAsync()
                    if ($line) { & $HandleLine $line ($i -eq 1) }
                }
            }
            if (!$ready) { [Threading.Thread]::Sleep(35) }
        }
        return $process.ExitCode
    } finally {
        if ($started -and !$process.HasExited) { Stop-BwChild $process }
        $process.Dispose()
    }
}
function Invoke-BwJob($Job,$Tools,$Events,$Cancel) {
    $outputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stats = @{ Errors=0; Missing=0; Items=0; Cancelled=$false; ExitFailures=0 }
    try {
        foreach ($mode in $Job.Modes) {
            if ($Cancel.IsCancellationRequested) { $stats.Cancelled = $true; break }
            $output = Join-Path $Job.Destination (@{ MP4='Video'; MP3='Audio'; Captions='Transcripts' }[$mode])
            $null = [IO.Directory]::CreateDirectory($output)
            $actual = $output
            $scratch = $null
            if ($mode -eq 'Captions') {
                $scratch = Join-Path ([IO.Path]::GetTempPath()) ('SimplePyrate-' + [guid]::NewGuid().ToString('N'))
                $null = [IO.Directory]::CreateDirectory($scratch)
                $actual = $scratch
            }
            Publish-Bw $Events 'phase' $mode
            try {
                $port = @{ Open=$false; Id=$null }
                $handler = {
                    param([string]$Line,[bool]$IsErrorChannel)
                    if ($Line.StartsWith('BW_PORT ')) {
                        $f = $Line.Substring(8) -split "`t",4
                        if ($f.Count -ne 4) { return }
                        $id = ConvertFrom-BwJson $f[0]
                        if ($port.Open -and $id -eq $port.Id) { return }
                        $port.Open=$true; $port.Id=$id
                        Publish-Bw $Events 'port' @{
                            Mode=$mode; Id=$id; Title=(ConvertFrom-BwJson $f[1]);
                            Index=(ConvertFrom-BwJson $f[2]); Count=(ConvertFrom-BwJson $f[3])
                        }
                        return
                    }
                    if ($Line.StartsWith('BW_PROGRESS ')) {
                        $f = $Line.Substring(12) -split "`t",6
                        if ($f.Count -ne 6) { return }
                        $percent = ConvertFrom-BwJson $f[0]
                        $count = ConvertFrom-BwJson $f[5]
                        $index = ConvertFrom-BwJson $f[4]
                        $pct = $null
                        if ([string]$percent -match '(\d+(?:\.\d+)?)\s*%') {
                            $pct = [Math]::Min(100,[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture))
                        }
                        Publish-Bw $Events 'progress' @{
                            Mode=$mode; Percent=$pct; Speed=(ConvertFrom-BwJson $f[1]); Eta=(ConvertFrom-BwJson $f[2]);
                            Title=(ConvertFrom-BwJson $f[3]); Index=$index; Count=$count
                        }
                        return
                    }
                    if ($Line.StartsWith('BW_PROCESS ')) {
                        $f = $Line.Substring(11) -split "`t",3
                        if ($f.Count -eq 3 -and (ConvertFrom-BwJson $f[0]) -eq 'started') {
                            Publish-Bw $Events 'processing' @{ Title=(ConvertFrom-BwJson $f[1]); Operation=(ConvertFrom-BwJson $f[2]) }
                        }
                        return
                    }
                    if ($Line.StartsWith('BW_ITEM ')) {
                        $f = $Line.Substring(8) -split "`t",4
                        if ($f.Count -ne 4) { return }
                        $title = ConvertFrom-BwJson $f[1]
                        $port.Open=$false; $port.Id=$null
                        Publish-Bw $Events 'port-done' $mode
                        if ($title) { Publish-Bw $Events 'title' $title }
                        if ($mode -ne 'Captions') {
                            $path = Get-BwContainedFile (ConvertFrom-BwJson $f[2]) $output
                            if ($path -and [IO.Path]::GetExtension($path) -ieq ".$mode") {
                                if ($outputs.Add($path)) { Publish-Bw $Events 'file' $path }
                                $stats.Items += 1
                            }
                            return
                        }
                        $subs = ConvertFrom-BwJson $f[3]
                        $found = $false
                        if ($null -ne $subs) {
                            foreach ($language in $subs.PSObject.Properties) {
                                $path = Get-BwContainedFile (Get-BwValue $language.Value 'filepath') $actual
                                if (!$path -or [IO.Path]::GetExtension($path) -ine '.srt') { continue }
                                $found = $true
                                try {
                                    if ($Job.CaptionFormat -ne 'TXT') {
                                        $srt = Join-Path $output ([IO.Path]::GetFileName($path))
                                        if (![IO.File]::Exists($srt)) {
                                            try { [IO.File]::Copy($path,$srt,$false) }
                                            catch [IO.IOException] { if (![IO.File]::Exists($srt)) { throw } }
                                        }
                                        if ($outputs.Add($srt)) { Publish-Bw $Events 'file' $srt }
                                    }
                                    if ($Job.CaptionFormat -ne 'SRT') {
                                        $body = ConvertFrom-BwTranscript ([IO.File]::ReadAllText($path))
                                        if (!$body) { throw 'The caption track has no readable cues.' }
                                        $txt = Join-Path $output ([IO.Path]::GetFileNameWithoutExtension($path) + '.txt')
                                        Write-BwTextFile $txt $body
                                        if ($outputs.Add($txt)) { Publish-Bw $Events 'file' $txt }
                                    }
                                } catch {
                                    $stats.Errors += 1
                                    Publish-Bw $Events 'log' "Transcript export failed for $($language.Name): $($_.Exception.Message)"
                                }
                            }
                        }
                        if (!$found) {
                            $stats.Missing += 1
                            Publish-Bw $Events 'log' "No matching captions for $title."
                        } else { $stats.Items += 1 }
                        return
                    }
                    if ($Line -match '^\[[A-Za-z][A-Za-z0-9 :._+/-]*\]\s+(?:[\w.-]+:\s+)?Sleeping\s+(\d+(?:\.\d+)?)\s+seconds?\b') {
                        $seconds=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)
                        if ($seconds -ge 0.15) {
                            Publish-Bw $Events 'source-wait' @{ Seconds=$seconds; Observed=[Diagnostics.Stopwatch]::GetTimestamp() }
                        }
                    }
                    if ($Line -match '^ERROR:') { $stats.Errors += 1 }
                    if ($Line.Length -gt 2200) { $Line = $Line.Substring(0,2200) }
                    Publish-Bw $Events 'log' $Line
                }
                $previousSize = $outputs.Count
                $result = Invoke-BwProcess $Tools['yt-dlp'] (New-BwArguments $Job $mode $Tools) $handler $Cancel $actual
                if ($result -eq -999) { $stats.Cancelled=$true; break }
                if ($result -ne 0) {
                    $stats.ExitFailures += 1
                    Publish-Bw $Events 'log' "$mode finished with yt-dlp exit code $result."
                }
                if ($outputs.Count -eq $previousSize -and $mode -ne 'Captions' -and $result -eq 0) {
                    $stats.Errors += 1
                    Publish-Bw $Events 'log' "$mode reported no finished media file."
                }
            } finally {
                if ($scratch -and [IO.Directory]::Exists($scratch)) {
                    try { [IO.Directory]::Delete($scratch,$true) } catch { Publish-Bw $Events 'log' 'Could not remove the temporary transcript files.' }
                }
            }
        }
    } catch {
        $stats.Errors += 1
        Publish-Bw $Events 'log' "ERROR: $($_.Exception.Message)"
    } finally {
        $status = if ($stats.Cancelled -or $Cancel.IsCancellationRequested) { 'Cancelled' }
        elseif ($outputs.Count -and ($stats.Errors -or $stats.ExitFailures -or $stats.Missing)) { 'Partial' }
        elseif ($outputs.Count) { 'Complete' }
        elseif ($stats.Errors -or $stats.ExitFailures) { 'Failed' }
        elseif ($stats.Missing) { 'No captions' }
        else { 'No files' }
        Publish-Bw $Events 'done' @{ Status=$status; Files=$outputs.Count; Errors=$stats.Errors; Missing=$stats.Missing; Items=$stats.Items }
    }
}
