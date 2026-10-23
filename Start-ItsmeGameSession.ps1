#Requires -Version 5.1
<#
.SYNOPSIS
    Sessione di gioco di ItsmeOS: niente interruzioni mentre giochi.

.DESCRIPTION
    Parte all'accesso (attività pianificata "\ItsmeOS\ItsmeOS Game Session")
    e controlla i processi ogni pochi secondi. Quando si apre un gioco:
      - spegne le notifiche di Windows
      - sospende i processi in background elencati in config\session.psd1
      - ferma download degli aggiornamenti, upload P2P e indicizzazione
    Quando il gioco si chiude rimette tutto com'era.

    Non apre handle sul processo del gioco: legge solo il percorso
    dell'eseguibile, come Gestione attività, quindi non interferisce con
    gli anti-cheat (Vanguard, FACEIT, EAC, BattlEye).

    Se lo script si interrompe a metà partita, al riavvio successivo
    ripristina quanto lasciato in sospeso (state\session.json).

.PARAMETER Once
    Controlla una volta, stampa i giochi trovati ed esce. Utile per provare
    la configurazione.
#>
[CmdletBinding()]
param([switch]$Once)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ItsmeOS.psm1') -Force

$Config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config\session.psd1')
$SessionPath = Join-Path $PSScriptRoot 'state\session.json'
$LogPath = Join-Path $PSScriptRoot 'logs\session.log'
$MySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

# Toggle principale "Notifiche" di Impostazioni e il suo gemello del Centro notifiche
$ToastValues = @(
    @{ Path = 'Software\Microsoft\Windows\CurrentVersion\PushNotifications'; Name = 'ToastEnabled' }
    @{ Path = 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name = 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' }
)

if (-not ('ItsmeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class ItsmeNative {
    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const uint PROCESS_SUSPEND_RESUME = 0x0800;

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool QueryFullProcessImageName(IntPtr handle, int flags, StringBuilder name, ref int size);
    [DllImport("ntdll.dll")]
    static extern int NtSuspendProcess(IntPtr handle);
    [DllImport("ntdll.dll")]
    static extern int NtResumeProcess(IntPtr handle);

    public static string GetImagePath(int pid) {
        IntPtr h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return null;
        try {
            StringBuilder sb = new StringBuilder(1024);
            int size = sb.Capacity;
            return QueryFullProcessImageName(h, 0, sb, ref size) ? sb.ToString() : null;
        } finally { CloseHandle(h); }
    }

    public static bool Suspend(int pid) { return Call(pid, true); }
    public static bool Resume(int pid) { return Call(pid, false); }

    static bool Call(int pid, bool suspend) {
        IntPtr h = OpenProcess(PROCESS_SUSPEND_RESUME, false, pid);
        if (h == IntPtr.Zero) return false;
        try { return (suspend ? NtSuspendProcess(h) : NtResumeProcess(h)) == 0; }
        finally { CloseHandle(h); }
    }
}
'@
}

function Write-SessionLog {
    param([string]$Message)
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
}

function Test-IsGame {
    param([System.Diagnostics.Process]$Process)
    $name = $Process.ProcessName
    if ($Config.NotGames -contains $name) { return $false }
    if ($Config.Games -contains $name) { return $true }
    $path = [ItsmeNative]::GetImagePath($Process.Id)
    if (-not $path) { return $false }
    foreach ($pattern in $Config.GameFolders) {
        if ($path -like $pattern) { return $true }
    }
    return $false
}

function Save-Session {
    param($Session)
    $dir = Split-Path -Parent $SessionPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Session | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SessionPath -Encoding UTF8
}

function Start-GameSession {
    param([string]$Game)
    $session = @{ Game = $Game; Started = (Get-Date).ToString('o'); Toasts = @(); Suspended = @(); Services = @() }
    # Salvato subito: se qualcosa va storto a metà, il prossimo avvio ripristina
    Save-Session $session

    if ($Config.MuteNotifications) {
        foreach ($t in $ToastValues) {
            $current = Get-ItsmeValue -Hive USER -Path $t.Path -Name $t.Name
            $session.Toasts += @{ Path = $t.Path; Name = $t.Name; Existed = $current.Exists; Value = $current.Value }
            Set-ItsmeValue -Hive USER -Path $t.Path -Name $t.Name -Type DWord -Value 0
        }
        Save-Session $session
    }

    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            if ($p.SessionId -ne $MySession -or $Config.Suspend -notcontains $p.ProcessName) { continue }
            if ([ItsmeNative]::Suspend($p.Id)) {
                $session.Suspended += @{ Id = $p.Id; Name = $p.ProcessName }
            }
        } catch {
            # Processo chiuso mentre lo leggevamo
        }
    }
    Save-Session $session

    foreach ($name in $Config.PauseServices) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') { continue }
        try {
            Stop-Service -Name $name -NoWait -ErrorAction Stop
            $session.Services += $name
        } catch {
            # Senza diritti di amministratore i servizi restano attivi: va bene così
        }
    }
    Save-Session $session

    Write-SessionLog ("Gioco: {0}. Notifiche spente, {1} processi sospesi, {2} servizi in pausa" -f
        $Game, @($session.Suspended).Count, @($session.Services).Count)
}

function Stop-GameSession {
    if (-not (Test-Path -LiteralPath $SessionPath)) { return }
    $session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
    $props = $session.PSObject.Properties

    if ($props['Suspended'] -and $session.Suspended) {
        foreach ($s in @($session.Suspended)) {
            # Il PID potrebbe essere stato riusato: riprendi solo se il nome coincide
            $p = Get-Process -Id $s.Id -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -eq $s.Name) { [void][ItsmeNative]::Resume($s.Id) }
        }
    }
    if ($props['Toasts'] -and $session.Toasts) {
        foreach ($t in @($session.Toasts)) {
            if ($t.Existed) { Set-ItsmeValue -Hive USER -Path $t.Path -Name $t.Name -Type DWord -Value $t.Value }
            else { Remove-ItsmeValue -Hive USER -Path $t.Path -Name $t.Name }
        }
    }
    if ($props['Services'] -and $session.Services) {
        foreach ($name in @($session.Services)) {
            try { Start-Service -Name $name -ErrorAction Stop } catch { }
        }
    }
    Remove-Item -LiteralPath $SessionPath -Force
    Write-SessionLog 'Gioco chiuso. Tutto ripristinato'
}

function Find-Game {
    param([hashtable]$Cache)
    $alive = @{}
    $found = $null
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $key = '{0}:{1}' -f $p.Id, $p.ProcessName
            $alive[$key] = $true
            if (-not $Cache.ContainsKey($key)) { $Cache[$key] = Test-IsGame $p }
            if ($Cache[$key] -and -not $found) { $found = $p.ProcessName }
        } catch {
            # Processo chiuso mentre lo leggevamo
        }
    }
    foreach ($key in @($Cache.Keys)) { if (-not $alive.ContainsKey($key)) { $Cache.Remove($key) } }
    return $found
}

$cache = @{}

if ($Once) {
    $game = Find-Game -Cache $cache
    if ($game) { Write-Host "Gioco trovato: $game" } else { Write-Host 'Nessun gioco aperto' }
    return
}

# Il controllo non deve mai rubare CPU al gioco
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'

# Ripristina una sessione rimasta aperta (crash, riavvio a metà partita)
Stop-GameSession

$active = $false
$lastSeen = Get-Date
while ($true) {
    try {
        $game = Find-Game -Cache $cache
        if ($game) {
            $lastSeen = Get-Date
            if (-not $active) { Start-GameSession -Game $game; $active = $true }
        } elseif ($active -and ((Get-Date) - $lastSeen).TotalSeconds -ge $Config.EndGraceSeconds) {
            Stop-GameSession
            $active = $false
        }
    } catch {
        Write-SessionLog "Errore: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $Config.PollSeconds
}
