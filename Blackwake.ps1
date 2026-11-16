param([switch]$SmokeTest)
& (Join-Path $PSScriptRoot 'SimplePyrate.ps1') -SmokeTest:$SmokeTest
