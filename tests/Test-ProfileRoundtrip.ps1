#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
    Prova su Windows vero (la CI usa il runner windows-latest):
    applica ogni profilo, controlla che i valori siano scritti, fa il rollback
    e verifica che il registro torni identico a prima.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'ItsmeOS.psm1') -Force
$config = Import-PowerShellDataFile -Path (Join-Path $root 'config\tweaks.psd1')
$failures = 0

function Get-Snapshot {
    param([object[]]$Operation)
    $snapshot = @{}
    foreach ($op in $Operation) {
        $key = '{0}\{1}\{2}' -f $op.Hive, $op.Path, $op.Name
        $value = Get-ItsmeValue -Hive $op.Hive -Path $op.Path -Name $op.Name
        $snapshot[$key] = '{0}|{1}|{2}' -f $value.Exists, $value.Type, (@($value.Value) -join ',')
    }
    return $snapshot
}

foreach ($preset in 'Competitive', 'Balanced', 'Streaming') {
    Write-Host "=== $preset ===" -ForegroundColor Cyan
    $ops = @(Get-ItsmeOperation -Config $config -Preset $preset)
    $before = Get-Snapshot $ops

    & (Join-Path $root 'Set-ItsmeProfile.ps1') -Preset $preset

    foreach ($op in $ops) {
        if ($op.RequireKey -and -not (Test-ItsmeKey -Hive $op.Hive -Path $op.Path)) { continue }
        $value = Get-ItsmeValue -Hive $op.Hive -Path $op.Path -Name $op.Name
        if ($op.Delete) { $ok = -not $value.Exists }
        else { $ok = $value.Exists -and ((@($value.Value) -join ',') -eq (@($op.Value) -join ',')) }
        if (-not $ok) {
            # 0xFFFFFFFF viene letto come -1: stesso valore a 32 bit
            if ($op.Type -eq 'DWord' -and $value.Exists -and ([int64]$value.Value -band 0xFFFFFFFFL) -eq ([int64]$op.Value -band 0xFFFFFFFFL)) { continue }
            Write-Host "  NON APPLICATO: $($op.Id) = $($value.Value)" -ForegroundColor Red
            $failures++
        }
    }

    $task = Get-ScheduledTask -TaskName 'ItsmeOS Game Session' -TaskPath '\ItsmeOS\' -ErrorAction SilentlyContinue
    if (-not $task) { Write-Host '  attività pianificata mancante' -ForegroundColor Red; $failures++ }

    & (Join-Path $root 'Set-ItsmeProfile.ps1') -Rollback

    $after = Get-Snapshot $ops
    foreach ($key in $before.Keys) {
        if ($before[$key] -ne $after[$key]) {
            Write-Host "  ROLLBACK DIVERSO: $key prima=$($before[$key]) dopo=$($after[$key])" -ForegroundColor Red
            $failures++
        }
    }
    if (Get-ScheduledTask -TaskName 'ItsmeOS Game Session' -TaskPath '\ItsmeOS\' -ErrorAction SilentlyContinue) {
        Write-Host '  attività pianificata ancora presente dopo il rollback' -ForegroundColor Red
        $failures++
    }
}

Write-Host '=== Sessione di gioco (-Once) ===' -ForegroundColor Cyan
& (Join-Path $root 'Start-ItsmeGameSession.ps1') -Once

if ($failures) { Write-Host "$failures errori" -ForegroundColor Red; exit 1 }
Write-Host 'Tutto ok' -ForegroundColor Green
