#Requires -Version 5.1
<#
    Motore di ItsmeOS.

    Applica i tweak di config\tweaks.psd1 al registro di Windows, sia sul
    sistema in uso (online) sia su un'immagine montata da DISM (offline).
    Prima di ogni modifica salva il valore originale in uno "stato", così
    Set-ItsmeProfile.ps1 -Rollback riporta tutto com'era.

    Le hive logiche sono tre:
      SOFTWARE  HKLM\SOFTWARE
      SYSTEM    HKLM\SYSTEM\CurrentControlSet (ControlSet00x offline)
      USER      HKCU (offline: il profilo Default, copiato da ogni nuovo utente)
#>

Set-StrictMode -Version 3.0

$script:Offline = $null
$script:LoadedHives = New-Object System.Collections.Generic.List[string]

$script:StartTypes = @{
    Automatic = 2
    Manual    = 3
    Disabled  = 4
}

function Write-ItsmeLog {
    param([Parameter(Mandatory)][string]$Message, [string]$Level = 'INFO')
    $line = '[{0:HH:mm:ss}] {1,-5} {2}' -f (Get-Date), $Level, $Message
    switch ($Level) {
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Invoke-ItsmeNative {
    # In Windows PowerShell 5.1, con ErrorActionPreference Stop, una riga su
    # stderr di un eseguibile (powercfg, reg) diventa un errore che ferma lo
    # script anche se il comando è riuscito. Conta solo il codice di uscita.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @())
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    } finally {
        $ErrorActionPreference = $previous
    }
}

# --- Modalità offline (immagine montata) -----------------------------------

function Enable-ItsmeOfflineMode {
    param([Parameter(Mandatory)][string]$ImagePath)

    $hives = [ordered]@{
        ITSME_SOFTWARE = Join-Path $ImagePath 'Windows\System32\config\SOFTWARE'
        ITSME_SYSTEM   = Join-Path $ImagePath 'Windows\System32\config\SYSTEM'
        ITSME_USER     = Join-Path $ImagePath 'Users\Default\NTUSER.DAT'
    }
    foreach ($name in $hives.Keys) {
        if (-not (Test-Path -LiteralPath $hives[$name])) {
            throw "Hive non trovata: $($hives[$name])"
        }
        $result = Invoke-ItsmeNative reg.exe @('load', "HKLM\$name", $hives[$name])
        if ($result.ExitCode -ne 0) { throw "reg load fallito per $($name): $($result.Output)" }
        $script:LoadedHives.Add($name)
    }

    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $select = $base.OpenSubKey('ITSME_SYSTEM\Select')
        $current = 1
        if ($select) { $current = [int]$select.GetValue('Current', 1); $select.Dispose() }
    } finally { $base.Dispose() }

    $script:Offline = @{ ControlSet = 'ControlSet{0:d3}' -f $current }
}

function Disable-ItsmeOfflineMode {
    # PowerShell tiene aperti handle al registro finché il GC non li chiude:
    # senza questo, reg unload fallisce con "accesso negato".
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    foreach ($name in @($script:LoadedHives)) {
        $unloaded = $false
        for ($i = 0; $i -lt 5 -and -not $unloaded; $i++) {
            if ((Invoke-ItsmeNative reg.exe @('unload', "HKLM\$name")).ExitCode -eq 0) { $unloaded = $true }
            else { Start-Sleep -Seconds 1; [GC]::Collect() }
        }
        if ($unloaded) { [void]$script:LoadedHives.Remove($name) }
        else { Write-ItsmeLog "Impossibile scaricare HKLM\$name, chiudi regedit e riprova" 'ERROR' }
    }
    $script:Offline = $null
}

# --- Accesso al registro ------------------------------------------------------

function Get-ItsmeKeyTarget {
    param([string]$Hive, [string]$Path)
    switch ($Hive) {
        'SOFTWARE' {
            if ($script:Offline) { return @{ Root = 'LocalMachine'; SubKey = "ITSME_SOFTWARE\$Path" } }
            return @{ Root = 'LocalMachine'; SubKey = "SOFTWARE\$Path" }
        }
        'SYSTEM' {
            if ($script:Offline) { return @{ Root = 'LocalMachine'; SubKey = "ITSME_SYSTEM\$($script:Offline.ControlSet)\$Path" } }
            return @{ Root = 'LocalMachine'; SubKey = "SYSTEM\CurrentControlSet\$Path" }
        }
        'USER' {
            if ($script:Offline) { return @{ Root = 'LocalMachine'; SubKey = "ITSME_USER\$Path" } }
            return @{ Root = 'CurrentUser'; SubKey = $Path }
        }
        default { throw "Hive sconosciuta: $Hive" }
    }
}

function Open-ItsmeKey {
    param([string]$Hive, [string]$Path, [switch]$Write, [switch]$Create)
    $target = Get-ItsmeKeyTarget -Hive $Hive -Path $Path
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]$target.Root, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        if ($Create) {
            return $base.CreateSubKey($target.SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        }
        return $base.OpenSubKey($target.SubKey, [bool]$Write)
    } finally { $base.Dispose() }
}

function Test-ItsmeKey {
    param([string]$Hive, [string]$Path)
    $key = Open-ItsmeKey -Hive $Hive -Path $Path
    if (-not $key) { return $false }
    $key.Dispose()
    return $true
}

function Get-ItsmeSubKeyName {
    param([string]$Hive, [string]$Path)
    $key = Open-ItsmeKey -Hive $Hive -Path $Path
    if (-not $key) { return @() }
    try { return $key.GetSubKeyNames() } finally { $key.Dispose() }
}

function Get-ItsmeValue {
    param([string]$Hive, [string]$Path, [string]$Name)
    $key = Open-ItsmeKey -Hive $Hive -Path $Path
    if (-not $key) { return [pscustomobject]@{ Exists = $false; Type = $null; Value = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{ Exists = $false; Type = $null; Value = $null }
        }
        $kind = $key.GetValueKind($Name)
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [pscustomobject]@{ Exists = $true; Type = $kind.ToString(); Value = $value }
    } finally { $key.Dispose() }
}

function ConvertTo-ItsmeRegistryData {
    param([string]$Type, $Value)
    switch ($Type) {
        'DWord' {
            # 0xFFFFFFFF può arrivare come -1 (Int32) o 4294967295 (Int64)
            $n = [long]$Value
            if ($n -gt [int]::MaxValue) { $n -= 4294967296 }
            return [int]$n
        }
        'QWord'       { return [long]$Value }
        'MultiString' { return [string[]]@($Value) }
        'Binary'      { return [byte[]]@($Value) }
        default       { return [string]$Value }
    }
}

function Set-ItsmeValue {
    param([string]$Hive, [string]$Path, [string]$Name, [string]$Type, $Value)
    $data = ConvertTo-ItsmeRegistryData -Type $Type -Value $Value
    $key = Open-ItsmeKey -Hive $Hive -Path $Path -Create
    try { $key.SetValue($Name, $data, [Microsoft.Win32.RegistryValueKind]$Type) } finally { $key.Dispose() }
}

function Set-ItsmeServiceStart {
    # Online passa dal gestore dei servizi: alcune chiavi Services\* sono
    # protette e non si scrivono direttamente nemmeno da amministratore.
    param([string]$Name, [int]$Start)
    $types = @{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }
    if (-not $types.ContainsKey($Start)) { throw "Tipo di avvio non gestito: $Start" }
    try {
        Set-Service -Name $Name -StartupType $types[$Start] -ErrorAction Stop
    } catch {
        Set-ItsmeValue -Hive SYSTEM -Path "Services\$Name" -Name 'Start' -Type DWord -Value $Start
    }
}

function Remove-ItsmeValue {
    param([string]$Hive, [string]$Path, [string]$Name)
    $key = Open-ItsmeKey -Hive $Hive -Path $Path -Write
    if (-not $key) { return }
    try { $key.DeleteValue($Name, $false) } finally { $key.Dispose() }
}

# --- Stato e rollback ---------------------------------------------------------

function New-ItsmeState {
    return @{
        Version  = 1
        Created  = (Get-Date).ToString('o')
        Preset   = $null
        Registry = New-Object System.Collections.ArrayList
        Actions  = @{}
    }
}

function Read-ItsmeState {
    param([Parameter(Mandatory)][string]$Path)
    $state = New-ItsmeState
    if (-not (Test-Path -LiteralPath $Path)) { return $state }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $props = $json.PSObject.Properties
    if ($props['Created']) { $state.Created = $json.Created }
    if ($props['Preset']) { $state.Preset = $json.Preset }
    if ($props['Registry'] -and $json.Registry) {
        foreach ($e in @($json.Registry)) {
            $service = $null
            if ($e.PSObject.Properties['Service']) { $service = $e.Service }
            [void]$state.Registry.Add(@{
                    Hive = $e.Hive; Path = $e.Path; Name = $e.Name; Service = $service
                    Existed = [bool]$e.Existed; Type = $e.Type; Value = $e.Value
                })
        }
    }
    if ($props['Actions'] -and $json.Actions) {
        foreach ($p in $json.Actions.PSObject.Properties) { $state.Actions[$p.Name] = $p.Value }
    }
    return $state
}

function Save-ItsmeState {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-ItsmeOriginal {
    # Registra il valore originale solo la prima volta: cambiando profilo
    # più volte, il rollback torna comunque allo stato di partenza.
    param($State, [string]$Hive, [string]$Path, [string]$Name, [string]$Service)
    foreach ($e in $State.Registry) {
        if ($e.Hive -eq $Hive -and $e.Path -eq $Path -and $e.Name -eq $Name) { return }
    }
    $current = Get-ItsmeValue -Hive $Hive -Path $Path -Name $Name
    if (-not $Service) { $Service = $null }
    [void]$State.Registry.Add(@{
            Hive = $Hive; Path = $Path; Name = $Name; Service = $Service
            Existed = $current.Exists; Type = $current.Type; Value = $current.Value
        })
}

function Restore-ItsmeRegistry {
    param([Parameter(Mandatory)]$State)
    $entries = @($State.Registry)
    [array]::Reverse($entries)
    $restored = 0
    foreach ($e in $entries) {
        try {
            if ($e.Existed) {
                if ($e.Type -notin 'String', 'ExpandString', 'DWord', 'QWord', 'MultiString', 'Binary') {
                    Write-ItsmeLog "Tipo $($e.Type) non ripristinabile: $($e.Hive)\$($e.Path)\$($e.Name)" 'WARN'
                    continue
                }
                if ($e.Service -and -not $script:Offline) {
                    Set-ItsmeServiceStart -Name $e.Service -Start $e.Value
                } else {
                    Set-ItsmeValue -Hive $e.Hive -Path $e.Path -Name $e.Name -Type $e.Type -Value $e.Value
                }
            } else {
                Remove-ItsmeValue -Hive $e.Hive -Path $e.Path -Name $e.Name
            }
            $restored++
        } catch {
            Write-ItsmeLog "Ripristino fallito $($e.Hive)\$($e.Path)\$($e.Name): $($_.Exception.Message)" 'WARN'
        }
    }
    return $restored
}

# --- Operazioni ---------------------------------------------------------------

function Test-ItsmePreset {
    param([hashtable]$Entry, [string]$Preset)
    if (-not $Entry.ContainsKey('Presets')) { return $true }
    return @($Entry.Presets) -contains $Preset
}

function Get-ItsmeOperation {
    <#
        Trasforma la configurazione in una lista di operazioni per un profilo.
        Value può essere un valore unico (vale per i profili in Presets, o per
        tutti) oppure una tabella @{ Competitive = ..; Streaming = .. }.
    #>
    param([Parameter(Mandatory)][hashtable]$Config, [Parameter(Mandatory)][string]$Preset)

    foreach ($t in $Config.Registry) {
        $note = ''
        if ($t.ContainsKey('Note')) { $note = $t.Note }

        if ($t.ContainsKey('Delete') -and $t.Delete) {
            if (-not (Test-ItsmePreset $t $Preset)) { continue }
            @{ Id = $t.Id; Hive = $t.Hive; Path = $t.Path; Name = $t.Name; Delete = $true; RequireKey = $false; Note = $note }
            continue
        }

        if ($t.Value -is [hashtable]) {
            if (-not $t.Value.ContainsKey($Preset)) { continue }
            $value = $t.Value[$Preset]
        } else {
            if (-not (Test-ItsmePreset $t $Preset)) { continue }
            $value = $t.Value
        }
        @{ Id = $t.Id; Hive = $t.Hive; Path = $t.Path; Name = $t.Name; Type = $t.Type; Value = $value; Delete = $false; RequireKey = $false; Note = $note }
    }

    foreach ($s in $Config.Services) {
        if (-not $s.Start.ContainsKey($Preset)) { continue }
        $note = ''
        if ($s.ContainsKey('Note')) { $note = $s.Note }
        @{
            Id = "service.$($s.Name)"; Service = $s.Name; Hive = 'SYSTEM'; Path = "Services\$($s.Name)"; Name = 'Start'
            Type = 'DWord'; Value = $script:StartTypes[$s.Start[$Preset]]; Delete = $false
            RequireKey = $true; Note = $note
        }
    }
}

function Get-ItsmeVbsOperation {
    # Opzionale: VBS/HVCI spenti valgono qualche punto percentuale in alcuni
    # giochi ma riducono la protezione del kernel. Vanguard e FACEIT
    # funzionano in entrambi i casi.
    @{ Id = 'vbs.off'; Hive = 'SYSTEM'; Path = 'Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Type = 'DWord'; Value = 0; Delete = $false; RequireKey = $false; Note = '' }
    @{ Id = 'hvci.off'; Hive = 'SYSTEM'; Path = 'Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Type = 'DWord'; Value = 0; Delete = $false; RequireKey = $false; Note = '' }
}

function Get-ItsmeMsiOperation {
    # Interrupt MSI per le schede video PCI. I driver recenti spesso lo
    # attivano già, in quel caso l'operazione non cambia nulla.
    $gpus = @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like 'PCI\*' })
    foreach ($gpu in $gpus) {
        @{
            Id = "msi.$($gpu.FriendlyName)"; Hive = 'SYSTEM'
            Path = "Enum\$($gpu.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            Name = 'MSISupported'; Type = 'DWord'; Value = 1; Delete = $false; RequireKey = $false; Note = ''
        }
    }
}

function Get-ItsmeNagleOperation {
    # Disattiva l'ACK ritardato sulle interfacce con un IP. Conta per i giochi
    # che usano TCP; i giochi su UDP (la maggior parte degli FPS) non cambiano.
    $base = 'Services\Tcpip\Parameters\Interfaces'
    foreach ($guid in Get-ItsmeSubKeyName -Hive 'SYSTEM' -Path $base) {
        $path = "$base\$guid"
        $dhcp = Get-ItsmeValue -Hive 'SYSTEM' -Path $path -Name 'DhcpIPAddress'
        $static = Get-ItsmeValue -Hive 'SYSTEM' -Path $path -Name 'IPAddress'
        $hasIp = ($dhcp.Exists -and $dhcp.Value -and $dhcp.Value -ne '0.0.0.0') -or
                 ($static.Exists -and @($static.Value | Where-Object { $_ -and $_ -ne '0.0.0.0' }).Count -gt 0)
        if (-not $hasIp) { continue }
        @{ Id = "nagle.ack.$guid"; Hive = 'SYSTEM'; Path = $path; Name = 'TcpAckFrequency'; Type = 'DWord'; Value = 1; Delete = $false; RequireKey = $true; Note = '' }
        @{ Id = "nagle.nodelay.$guid"; Hive = 'SYSTEM'; Path = $path; Name = 'TCPNoDelay'; Type = 'DWord'; Value = 1; Delete = $false; RequireKey = $true; Note = '' }
    }
}

function Invoke-ItsmeOperation {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Operation,
        [Parameter(Mandatory)]$State,
        [string[]]$SkipHive = @()
    )
    $applied = 0; $skipped = 0; $failed = 0
    foreach ($op in $Operation) {
        if ($SkipHive -contains $op.Hive) { $skipped++; continue }
        try {
            if ($op.RequireKey -and -not (Test-ItsmeKey -Hive $op.Hive -Path $op.Path)) {
                $skipped++
                continue
            }
            $service = $null
            if ($op.ContainsKey('Service')) { $service = $op.Service }
            Add-ItsmeOriginal -State $State -Hive $op.Hive -Path $op.Path -Name $op.Name -Service $service
            if ($op.Delete) {
                Remove-ItsmeValue -Hive $op.Hive -Path $op.Path -Name $op.Name
            } elseif ($service -and -not $script:Offline) {
                Set-ItsmeServiceStart -Name $service -Start $op.Value
            } else {
                Set-ItsmeValue -Hive $op.Hive -Path $op.Path -Name $op.Name -Type $op.Type -Value $op.Value
            }
            $applied++
            Write-Verbose "[ok] $($op.Id)"
        } catch {
            $failed++
            Write-ItsmeLog "[$($op.Id)] $($_.Exception.Message)" 'WARN'
        }
    }
    return [pscustomobject]@{ Applied = $applied; Skipped = $skipped; Failed = $failed }
}

function Get-ItsmeListFile {
    # Legge un file .txt di elenco: una voce per riga, # per i commenti.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $item = ($line -split '#', 2)[0].Trim()
        if ($item) { $item }
    }
}

Export-ModuleMember -Function `
    Write-ItsmeLog, Invoke-ItsmeNative, Enable-ItsmeOfflineMode, Disable-ItsmeOfflineMode, `
    Test-ItsmeKey, Get-ItsmeSubKeyName, Get-ItsmeValue, Set-ItsmeValue, Remove-ItsmeValue, `
    New-ItsmeState, Read-ItsmeState, Save-ItsmeState, Restore-ItsmeRegistry, `
    Get-ItsmeOperation, Get-ItsmeVbsOperation, Get-ItsmeMsiOperation, Get-ItsmeNagleOperation, `
    Invoke-ItsmeOperation, Get-ItsmeListFile
