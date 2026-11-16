param([switch]$Refresh,[switch]$NonInteractiveSetup)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')

function Set-BwMachinePath([string]$Path) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment',$true)
    if (!$key) { throw 'Could not open the machine PATH registry key.' }
    try {
        $raw = [string]$key.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $present = $false
        foreach ($item in ($raw -split ';')) {
            if ([Environment]::ExpandEnvironmentVariables($item.Trim().Trim('"')).TrimEnd('\') -ieq $Path) { $present=$true; break }
        }
        if (!$present) {
            $next = if ($raw) { $raw.TrimEnd(';') + ';' + $Path } else { $Path }
            if ($next.Length -gt 32766) { throw 'The Windows system PATH is too long to add the tools directory.' }
            $type = if ($raw) { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $key.SetValue('Path',$next,$type)
        }
    } finally { $key.Close() }
    try {
        Add-Type -Namespace Blackwake -Name PathNotification -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode, SetLastError=true)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint msg, System.UIntPtr wParam,
  string lParam, uint flags, uint timeout, out System.UIntPtr result);
'@
        [UIntPtr]$result = [UIntPtr]::Zero
        $null = [Blackwake.PathNotification]::SendMessageTimeout([IntPtr]0xffff,0x1a,[UIntPtr]::Zero,'Environment',2,1000,[ref]$result)
    } catch { Write-Host 'PATH saved. Restart Explorer or open a fresh sign-in session if an existing terminal does not see it.' -ForegroundColor Yellow }
}
function New-BwProtectedDirectory([string]$Path) {
    $null = [IO.Directory]::CreateDirectory($Path)
    if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The install location must not be a symbolic link or junction: $Path"
    }
}
function Get-BwReleaseAsset($Package) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Package.Repo)/releases/$($Package.Release)" -Headers @{
        'User-Agent'='BGGG-SimplePyrate/2.5.2'; 'Accept'='application/vnd.github+json'
    } -TimeoutSec 45
    $matchesFound = @($release.assets | Where-Object { $_.name -ceq $Package.Asset })
    if ($matchesFound.Count -ne 1) { throw "Expected exactly one release asset named $($Package.Asset)." }
    $asset = $matchesFound[0]
    $digest = [string](Get-BwValue $asset 'digest')
    if ($digest -notmatch '^sha256:[0-9a-fA-F]{64}$') { throw "No published SHA-256 digest for $($Package.Asset)." }
    $url = [uri]$asset.browser_download_url
    $repos = @($Package.Repo)
    if ($Package.Repo -eq 'FFmpeg-Builds/FFmpeg-Builds') { $repos += 'BtbN/FFmpeg-Builds' }
    $approvedPath = $false
    foreach ($repo in $repos) {
        if ($url.AbsolutePath.StartsWith('/' + $repo + '/releases/download/',[StringComparison]::OrdinalIgnoreCase)) { $approvedPath=$true; break }
    }
    if ($url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or !$approvedPath -or
        !$url.AbsolutePath.EndsWith('/'+$Package.Asset,[StringComparison]::Ordinal)) { throw 'The release asset URL was unexpected.' }
    if ([int64]$asset.size -le 0 -or [int64]$asset.size -gt 536870912) { throw 'The release asset size was unexpected.' }
    return [pscustomobject]@{ Url=$url; Digest=$digest.Substring(7); Size=[int64]$asset.size; Version=$release.tag_name }
}
function Copy-BwZipTools([string]$Source,[string]$Stage,[string[]]$Names) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Source)
    try {
        foreach ($name in $Names) {
            $matched = @($zip.Entries | Where-Object { $_.Name -ceq $name -and $_.Length -gt 0 -and $_.Length -lt 536870912 })
            if ($matched.Count -ne 1) { throw "The verified archive did not contain exactly one $name." }
            $target = Join-Path $Stage $name
            $entryStream = $matched[0].Open()
            try {
                $out = [IO.File]::Open($target,[IO.FileMode]::CreateNew)
                try { $entryStream.CopyTo($out) } finally { $out.Dispose() }
            } finally { $entryStream.Dispose() }
        }
    } finally { $zip.Dispose() }
}
function Install-BwPackage($Package,[string]$Stage,[string]$Bin) {
    $asset = Get-BwReleaseAsset $Package
    $source = Join-Path $Stage $Package.Asset
    Write-Host "Fetching $($Package.Name) $($asset.Version) ($([Math]::Round($asset.Size / 1MB,1)) MB)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.Url -OutFile $source -UseBasicParsing -TimeoutSec 900 -UserAgent 'BGGG-SimplePyrate/2.5.2'
    if ((Get-Item -LiteralPath $source).Length -ne $asset.Size -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $asset.Digest) {
        throw "SHA-256 or byte count did not match for $($Package.Asset). The package was not installed."
    }
    Write-Host "Verified SHA-256 for $($Package.Name)." -ForegroundColor DarkCyan
    if ($Package.Asset.EndsWith('.zip')) { Copy-BwZipTools $source $Stage $Package.Names }
    else {
        $target = Join-Path $Stage $Package.Names[0]
        if ($source -ine $target) { [IO.File]::Move($source,$target) }
    }
    $committed = [Collections.Generic.List[object]]::new()
    try {
        foreach ($name in $Package.Names) {
            $from = Join-Path $Stage $name
            $to = Join-Path $Bin $name
            $backup = Join-Path $Stage ($name + '.previous')
            if ([IO.File]::Exists($to)) {
                if (([IO.File]::GetAttributes($to) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing to replace a linked executable: $to" }
                [IO.File]::Replace($from,$to,$backup)
            } else { [IO.File]::Move($from,$to) }
            $committed.Add(@{Target=$to;Backup=$backup})
        }
    } catch {
        foreach ($item in $committed) {
            if ([IO.File]::Exists($item.Backup)) { [IO.File]::Replace($item.Backup,$item.Target,$null) }
            elseif ([IO.File]::Exists($item.Target)) { [IO.File]::Delete($item.Target) }
        }
        throw
    }
}
$stage = $null
$lock = $null
$exitCode = 0
try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator approval is required to install on the Windows system PATH.' }
    $Host.UI.RawUI.WindowTitle = 'Simple Pyrate v2.5.2 | Shipyard'
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -notin @('AMD64','ARM64')) { throw 'Simple Pyrate dependency setup supports 64-bit Windows on x64 and ARM64.' }
    $arm = $architecture -eq 'ARM64'
    $top = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'BGGG'
    $base = Join-Path $top 'Blackwake'
    $bin = Join-Path $base 'bin'
    New-BwProtectedDirectory $top
    New-BwProtectedDirectory $base
    New-BwProtectedDirectory $bin
    $lock = [IO.File]::Open((Join-Path $base 'setup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $tools = Get-BwToolPaths
    $ytAsset = if ($arm) { 'yt-dlp_arm64.exe' } else { 'yt-dlp.exe' }
    $ffAsset = if ($arm) { 'ffmpeg-master-latest-winarm64-gpl.zip' } else { 'ffmpeg-master-latest-win64-gpl.zip' }
    $denoAsset = if ($arm) { 'deno-aarch64-pc-windows-msvc.zip' } else { 'deno-x86_64-pc-windows-msvc.zip' }
    $packages = @(
        @{ Name='yt-dlp'; Repo='yt-dlp/yt-dlp'; Release='latest'; Asset=$ytAsset; Names=@('yt-dlp.exe'); Key='yt-dlp' },
        @{ Name='FFmpeg + FFprobe'; Repo='FFmpeg-Builds/FFmpeg-Builds'; Release='tags/latest'; Asset=$ffAsset; Names=@('ffmpeg.exe','ffprobe.exe'); Key='ffmpeg' },
        @{ Name='Deno'; Repo='denoland/deno'; Release='latest'; Asset=$denoAsset; Names=@('deno.exe'); Key='deno' }
    )
    Write-Host 'SIMPLE PYRATE V2.5.2 / SHIPYARD' -ForegroundColor DarkYellow
    Write-Host "Machine-wide tools: $bin"
    $stage = Join-Path $base ('setup-' + [guid]::NewGuid().ToString('N'))
    New-BwProtectedDirectory $stage
    foreach ($package in $packages) {
        $managed = [IO.File]::Exists((Join-Path $bin $package.Names[0]))
        if ($Refresh -and $managed) { Install-BwPackage $package $stage $bin; continue }
        if ($tools[$package.Key]) {
            Write-Host "$($package.Name) already available: $($tools[$package.Key])"
        } elseif ((@($package.Names | Where-Object { ![IO.File]::Exists((Join-Path $bin $_)) })).Count) {
            Install-BwPackage $package $stage $bin
        } else { Write-Host "Restoring system PATH access to $($package.Name)." }
    }
    if ((@($packages | Where-Object { [IO.File]::Exists((Join-Path $bin $_.Names[0])) })).Count) {
        Set-BwMachinePath $bin
    }
    $checked = Get-BwToolPaths
    if (@($checked.Values | Where-Object { !$_ }).Count) { throw 'Setup finished but one or more tools were still missing from the system PATH.' }
    Write-Host 'Shipyard ready. Returning to Simple Pyrate.' -ForegroundColor Green
} catch {
    $exitCode = 1
    Write-Host "Shipyard could not complete setup. $($_.Exception.Message)" -ForegroundColor Red
    if ($NonInteractiveSetup) {
        try {
            $profile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BGGG\Blackwake'
            $null=[IO.Directory]::CreateDirectory($profile)
            [IO.File]::WriteAllText((Join-Path $profile 'setup-error.log'),($_ | Out-String),[Text.UTF8Encoding]::new($false))
        } catch { }
    } else {
        Write-Host 'Press Enter to return to Simple Pyrate.'
        $null = Read-Host
    }
} finally {
    if ($stage -and [IO.Directory]::Exists($stage)) {
        try { [IO.Directory]::Delete($stage,$true) } catch { Write-Host "Could not clean up $stage." -ForegroundColor Yellow }
    }
    if ($lock) { $lock.Dispose() }
}
exit $exitCode
