#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applica un profilo ItsmeOS a Windows già installato, oppure lo annulla.

.DESCRIPTION
    Funziona sia su ItsmeOS installato dalla ISO (C:\ItsmeOS) sia su un
    Windows 11 normale, lanciandolo dalla cartella del repository.
    Ogni valore cambiato viene salvato in state\backup.json: -Rollback
    riporta il sistema allo stato precedente al primo profilo applicato.

.PARAMETER Preset
    Competitive  massime prestazioni e latenza minima
    Balanced     ottimizzato ma senza rinunce nell'uso quotidiano
    Streaming    gioco e OBS sullo stesso PC

.PARAMETER DisableVBS
    Spegne VBS e HVCI (Core isolation). Qualche punto percentuale in più in
    alcuni giochi, meno protezione del kernel. Richiede un riavvio.

.PARAMETER NoGameSession
    Non installa la sessione di gioco automatica (notifiche spente e
    processi in background sospesi mentre giochi).

.EXAMPLE
    .\Set-ItsmeProfile.ps1 -Preset Competitive

.EXAMPLE
    .\Set-ItsmeProfile.ps1 -Rollback
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [ValidateSet('Competitive', 'Balanced', 'Streaming')]
    [string]$Preset = 'Balanced',

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$DisableVBS,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$NoGameSession,

    # Usato da SetupComplete.cmd: gira come SYSTEM prima del primo accesso,
    # quindi salta i tweak utente (già scritti nel profilo Default dalla ISO).
    [Parameter(ParameterSetName = 'Apply')]
    [switch]$FirstBoot,

    [Parameter(ParameterSetName = 'Rollback', Mandatory)]
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ItsmeOS.psm1') -Force

$StatePath = Join-Path $PSScriptRoot 'state\backup.json'
$LogDir = Join-Path $PSScriptRoot 'logs'
$TaskName = 'ItsmeOS Game Session'
$ItsmeSchemeGuid = 'c196ac9d-5db6-48fa-806b-362d546bb915'
$UltimateSchemeGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

function Test-HasBattery {
    return @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0
}

function Get-ActiveSchemeGuid {
    $out = (& powercfg.exe /getactivescheme) -join ' '
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}

function Set-ItsmePowerPlan {
    param($State)
    if ($Preset -eq 'Balanced') { return }
    if (Test-HasBattery) {
        Write-ItsmeLog 'Portatile rilevato: piano energetico lasciato invariato (la batteria durerebbe molto meno)' 'WARN'
        return
    }
    if (-not $State.Actions.ContainsKey('PowerScheme')) { $State.Actions['PowerScheme'] = Get-ActiveSchemeGuid }

    & powercfg.exe /query $ItsmeSchemeGuid *> $null
    if ($LASTEXITCODE -ne 0) {
        & powercfg.exe /duplicatescheme $UltimateSchemeGuid $ItsmeSchemeGuid | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-ItsmeLog 'Impossibile creare il piano Prestazioni eccellenti' 'WARN'; return }
        & powercfg.exe /changename $ItsmeSchemeGuid 'ItsmeOS' 'Prestazioni massime per il gaming' | Out-Null
    }
    # Core parking spento: tutti i core restano pronti, niente risvegli a metà frame
    & powercfg.exe /setacvalueindex $ItsmeSchemeGuid SUB_PROCESSOR CPMINCORES 100 | Out-Null
    & powercfg.exe /setactive $ItsmeSchemeGuid | Out-Null
    Write-ItsmeLog 'Piano energetico ItsmeOS attivo (Prestazioni eccellenti, core parking spento)' 'OK'
}

function Set-ItsmeHibernation {
    param($State)
    if (Test-HasBattery) { return }
    if (-not $State.Actions.ContainsKey('HibernateEnabled')) {
        $State.Actions['HibernateEnabled'] = (Get-ItsmeValue -Hive SYSTEM -Path 'Control\Power' -Name 'HibernateEnabled').Value
    }
    & powercfg.exe /hibernate off | Out-Null
    Write-ItsmeLog 'Ibernazione spenta: liberato hiberfil.sys (circa il 40% della RAM su disco)' 'OK'
}

function Set-ItsmeReservedStorage {
    param($State)
    try {
        if (-not $State.Actions.ContainsKey('ReservedStorage')) {
            $State.Actions['ReservedStorage'] = [string](Get-WindowsReservedStorageState).ReservedStorageState
        }
        Set-WindowsReservedStorageState -State Disabled | Out-Null
        Write-ItsmeLog 'Spazio riservato agli aggiornamenti liberato (circa 7 GB)' 'OK'
    } catch {
        Write-ItsmeLog 'Spazio riservato non modificabile adesso (aggiornamento in corso?), riprova dopo un riavvio' 'WARN'
    }
}

function Register-ItsmeGameSession {
    $script = Join-Path $PSScriptRoot 'Start-ItsmeGameSession.ps1'
    $arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    # S-1-5-32-545 = gruppo Utenti (il nome cambia con la lingua di Windows).
    # RunLevel Highest: serve per mettere in pausa i servizi durante il gioco.
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Priority 7
    Register-ScheduledTask -TaskName $TaskName -TaskPath '\ItsmeOS\' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-ItsmeLog 'Sessione di gioco automatica installata (parte al prossimo accesso)' 'OK'
}

function Unregister-ItsmeGameSession {
    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath '\ItsmeOS\' -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -InputObject $task -Confirm:$false
        Write-ItsmeLog 'Sessione di gioco automatica rimossa' 'OK'
    }
}

function Invoke-Apply {
    $state = Read-ItsmeState -Path $StatePath
    $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config\tweaks.psd1')

    Write-ItsmeLog "Profilo $Preset"
    $ops = @(Get-ItsmeOperation -Config $config -Preset $Preset)
    $ops += @(Get-ItsmeMsiOperation)
    if ($Preset -eq 'Competitive') { $ops += @(Get-ItsmeNagleOperation) }
    if ($DisableVBS) { $ops += @(Get-ItsmeVbsOperation) }

    $skip = @()
    if ($FirstBoot) { $skip = @('USER') }
    $result = Invoke-ItsmeOperation -Operation $ops -State $state -SkipHive $skip
    Save-ItsmeState -State $state -Path $StatePath
    Write-ItsmeLog ("Registro: {0} applicati, {1} saltati, {2} falliti" -f $result.Applied, $result.Skipped, $result.Failed) 'OK'

    Set-ItsmePowerPlan -State $state
    Set-ItsmeHibernation -State $state
    Set-ItsmeReservedStorage -State $state

    if ($NoGameSession) { Unregister-ItsmeGameSession } else { Register-ItsmeGameSession }

    $state.Preset = $Preset
    Save-ItsmeState -State $state -Path $StatePath
    Write-ItsmeLog "Fatto. Backup in $StatePath. Riavvia per applicare tutto." 'OK'
}

function Invoke-Rollback {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        Write-ItsmeLog 'Nessun backup trovato: niente da ripristinare' 'WARN'
        return
    }
    $state = Read-ItsmeState -Path $StatePath

    $restored = Restore-ItsmeRegistry -State $state
    Write-ItsmeLog "Registro: $restored valori ripristinati" 'OK'

    if ($state.Actions.ContainsKey('PowerScheme') -and $state.Actions['PowerScheme']) {
        & powercfg.exe /setactive $state.Actions['PowerScheme'] | Out-Null
        & powercfg.exe /delete $ItsmeSchemeGuid 2>$null | Out-Null
        Write-ItsmeLog 'Piano energetico originale ripristinato' 'OK'
    }
    if ($state.Actions.ContainsKey('HibernateEnabled') -and [int]$state.Actions['HibernateEnabled'] -eq 1) {
        & powercfg.exe /hibernate on | Out-Null
        Write-ItsmeLog 'Ibernazione riattivata' 'OK'
    }
    if ($state.Actions.ContainsKey('ReservedStorage') -and $state.Actions['ReservedStorage'] -eq 'Enabled') {
        try { Set-WindowsReservedStorageState -State Enabled | Out-Null; Write-ItsmeLog 'Spazio riservato riattivato' 'OK' }
        catch { Write-ItsmeLog 'Spazio riservato non riattivabile adesso, riprova dopo un riavvio' 'WARN' }
    }
    Unregister-ItsmeGameSession

    $archived = Join-Path (Split-Path -Parent $StatePath) ('backup-restored-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))
    Move-Item -LiteralPath $StatePath -Destination $archived
    Write-ItsmeLog 'Rollback completato. Le app rimosse dalla ISO si reinstallano dal Microsoft Store. Riavvia.' 'OK'
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir ('profile-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))) | Out-Null
try {
    if ($Rollback) { Invoke-Rollback } else { Invoke-Apply }
} finally {
    Stop-Transcript | Out-Null
}
