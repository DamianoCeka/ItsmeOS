#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Crea la ISO di ItsmeOS partendo dalla ISO ufficiale di Windows 11.

.DESCRIPTION
    1. Copia la ISO ufficiale e tiene solo l'edizione scelta
    2. Rimuove le app preinstallate e le funzionalità inutili
    3. Scrive i tweak del profilo scelto nel registro dell'immagine
    4. Copia ItsmeOS in C:\ItsmeOS e lo collega al primo avvio
    5. Pulisce i componenti superati e ricomprime l'immagine
    6. Genera la nuova ISO con oscdimg

    TPM 2.0, Secure Boot, Defender e Windows Update restano intatti:
    Vanguard, FACEIT e gli altri anti-cheat funzionano come su Windows
    originale. La ISO resta personale: ognuno la crea dalla propria copia
    di Windows.

.PARAMETER IsoPath
    ISO ufficiale di Windows 11 scaricata da microsoft.com.

.PARAMETER Preset
    Profilo scritto nell'immagine: Competitive, Balanced o Streaming.
    Dopo l'installazione si cambia con C:\ItsmeOS\Set-ItsmeProfile.ps1.

.PARAMETER Edition
    Edizione da tenere, come la riporta Get-WindowsImage (es. "Windows 11 Pro").

.PARAMETER LocalUser
    Crea questo account locale amministratore e salta l'account Microsoft.
    La password è vuota: impostala al primo accesso.

.PARAMETER DisableVBS
    Spegne VBS e HVCI nell'immagine. Sconsigliato con VALORANT e FACEIT
    (vedi README).

.PARAMETER Esd
    Comprime l'immagine in install.esd: ISO molto più piccola, creazione
    più lenta.

.EXAMPLE
    .\build-iso.ps1 -IsoPath D:\Win11_24H2_Italian_x64.iso -Preset Competitive -LocalUser Damiano
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IsoPath,

    [ValidateSet('Competitive', 'Balanced', 'Streaming')]
    [string]$Preset = 'Balanced',

    [string]$Edition = 'Windows 11 Pro',

    [ValidatePattern('^[^\\/\[\]:;|=,+*?<>"@]{1,20}$')]
    [string]$LocalUser,

    [switch]$DisableVBS,

    [switch]$Esd,

    [string]$OutputIso,

    [string]$WorkDir = (Join-Path $env:SystemDrive 'ItsmeOS-build'),

    [switch]$KeepWorkDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'ItsmeOS.psm1') -Force

$IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
if (-not $OutputIso) { $OutputIso = Join-Path (Split-Path -Parent $IsoPath) "ItsmeOS-$Preset.iso" }
$IsoDir = Join-Path $WorkDir 'iso'
$MountDir = Join-Path $WorkDir 'mount'
$SingleWim = Join-Path $WorkDir 'install.wim'

$script:Step = 0
function Write-Step {
    param([string]$Message)
    $script:Step++
    Write-Host ''
    Write-Host ("[{0}/10] {1}" -f $script:Step, $Message) -ForegroundColor Cyan
}

function Find-Oscdimg {
    $command = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $adk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools'
    foreach ($arch in 'amd64', 'arm64', 'x86') {
        $candidate = Join-Path $adk "$arch\Oscdimg\oscdimg.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function New-AutounattendXml {
    $account = ''
    $hideOnline = 'false'
    if ($LocalUser) {
        $hideOnline = 'true'
        $name = [Security.SecurityElement]::Escape($LocalUser)
        $account = @"
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$name</Name>
            <Group>Administrators</Group>
            <Password><Value></Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
"@
    }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generato da ItsmeOS build-iso.ps1. Non tocca dischi e partizioni. -->
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOnlineAccountScreens>$hideOnline</HideOnlineAccountScreens>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
$account    </component>
  </settings>
</unattend>
"@
}

# --- Controlli iniziali --------------------------------------------------------

if ($WorkDir -match '\s') { throw "WorkDir non può contenere spazi (limite di oscdimg): $WorkDir" }
$oscdimg = Find-Oscdimg
if (-not $oscdimg) {
    throw @'
oscdimg.exe non trovato. Installa i Deployment Tools di Windows ADK:
  winget install Microsoft.WindowsADK
(durante l'installazione basta selezionare "Deployment Tools")
'@
}
$drive = Get-PSDrive -Name ($WorkDir.Substring(0, 1))
if ($drive.Free -lt 25GB) {
    throw ("Servono almeno 25 GB liberi su {0}: (liberi {1:N1} GB)" -f $drive.Name, ($drive.Free / 1GB))
}
if (Test-Path -LiteralPath $WorkDir) {
    $stale = Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $MountDir }
    if ($stale) { Dismount-WindowsImage -Path $MountDir -Discard | Out-Null }
    Remove-Item -LiteralPath $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Path $IsoDir, $MountDir -Force | Out-Null

$isoMounted = $false
$imageMounted = $false
$started = Get-Date
try {
    # --- 1. Copia della ISO ---------------------------------------------------
    Write-Step 'Copio la ISO ufficiale'
    $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $isoMounted = $true
    $letter = ($disk | Get-Volume).DriveLetter
    $copy = Invoke-ItsmeNative robocopy.exe @("$($letter):\", $IsoDir, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1')
    if ($copy.ExitCode -ge 8) { throw "robocopy fallito (codice $($copy.ExitCode)): $($copy.Output)" }
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    $isoMounted = $false
    Get-ChildItem -LiteralPath $IsoDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    # --- 2. Edizione --------------------------------------------------------
    Write-Step "Estraggo l'edizione $Edition"
    $sources = Join-Path $IsoDir 'sources'
    $sourceImage = Join-Path $sources 'install.wim'
    if (-not (Test-Path -LiteralPath $sourceImage)) { $sourceImage = Join-Path $sources 'install.esd' }
    if (-not (Test-Path -LiteralPath $sourceImage)) { throw 'install.wim / install.esd non trovato: è una ISO di Windows?' }

    $images = @(Get-WindowsImage -ImagePath $sourceImage)
    $image = $images | Where-Object { $_.ImageName -eq $Edition } | Select-Object -First 1
    if (-not $image) {
        throw ("Edizione '{0}' non trovata. Disponibili: {1}" -f $Edition, (($images | ForEach-Object ImageName) -join ', '))
    }
    Export-WindowsImage -SourceImagePath $sourceImage -SourceIndex $image.ImageIndex `
        -DestinationImagePath $SingleWim -CompressionType max | Out-Null
    Remove-Item -LiteralPath $sourceImage -Force

    $info = Get-WindowsImage -ImagePath $SingleWim -Index 1
    if ([version]$info.Version -lt [version]'10.0.22000') {
        throw "Serve Windows 11 (build 22000 o successiva), trovata $($info.Version)"
    }
    Write-ItsmeLog "Windows $($info.Version), $($info.ImageName)"

    Write-Step "Monto l'immagine"
    Mount-WindowsImage -ImagePath $SingleWim -Index 1 -Path $MountDir | Out-Null
    $imageMounted = $true

    # --- 3. App e funzionalità ---------------------------------------------
    Write-Step 'Rimuovo app preinstallate e funzionalità inutili'
    $appx = @(Get-ItsmeListFile -Path (Join-Path $PSScriptRoot 'config\appx-remove.txt'))
    foreach ($package in Get-AppxProvisionedPackage -Path $MountDir) {
        if ($appx -notcontains $package.DisplayName) { continue }
        try {
            Remove-AppxProvisionedPackage -Path $MountDir -PackageName $package.PackageName | Out-Null
            Write-ItsmeLog "  app rimossa: $($package.DisplayName)"
        } catch { Write-ItsmeLog "  non rimossa: $($package.DisplayName) ($($_.Exception.Message))" 'WARN' }
    }
    $capabilities = @(Get-ItsmeListFile -Path (Join-Path $PSScriptRoot 'config\capabilities-remove.txt'))
    foreach ($capability in Get-WindowsCapability -Path $MountDir | Where-Object State -eq 'Installed') {
        foreach ($prefix in $capabilities) {
            if ($capability.Name -notlike "$prefix*") { continue }
            try {
                Remove-WindowsCapability -Path $MountDir -Name $capability.Name | Out-Null
                Write-ItsmeLog "  funzionalità rimossa: $($capability.Name)"
            } catch { Write-ItsmeLog "  non rimossa: $($capability.Name)" 'WARN' }
        }
    }

    # --- 4. Tweak nel registro dell'immagine -------------------------------
    Write-Step "Applico il profilo $Preset al registro dell'immagine"
    $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config\tweaks.psd1')
    $state = New-ItsmeState
    $state.Preset = $Preset
    Enable-ItsmeOfflineMode -ImagePath $MountDir
    try {
        $ops = @(Get-ItsmeOperation -Config $config -Preset $Preset)
        if ($DisableVBS) { $ops += @(Get-ItsmeVbsOperation) }
        $result = Invoke-ItsmeOperation -Operation $ops -State $state
        Write-ItsmeLog ("Registro: {0} applicati, {1} saltati, {2} falliti" -f $result.Applied, $result.Skipped, $result.Failed) 'OK'

        # Al primo avvio compare "Non ho Internet": l'account locale è sempre possibile.
        # Non è un tweak di gioco, quindi non finisce nel backup.
        Set-ItsmeValue -Hive SOFTWARE -Path 'Microsoft\Windows\CurrentVersion\OOBE' -Name 'BypassNRO' -Type DWord -Value 1
    } finally {
        Disable-ItsmeOfflineMode
    }

    # --- 5. ItsmeOS dentro l'immagine -----------------------------------------
    Write-Step 'Copio ItsmeOS in C:\ItsmeOS'
    $payload = Join-Path $MountDir 'ItsmeOS'
    New-Item -ItemType Directory -Path (Join-Path $payload 'config') -Force | Out-Null
    foreach ($file in 'ItsmeOS.psm1', 'Set-ItsmeProfile.ps1', 'Start-ItsmeGameSession.ps1', 'README.md', 'LICENSE') {
        $src = Join-Path $PSScriptRoot $file
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $payload }
    }
    Copy-Item -Path (Join-Path $PSScriptRoot 'config\*') -Destination (Join-Path $payload 'config') -Recurse
    # Backup dei valori originali dell'immagine: il rollback funziona anche su questi
    Save-ItsmeState -State $state -Path (Join-Path $payload 'state\backup.json')

    $setupScripts = Join-Path $MountDir 'Windows\Setup\Scripts'
    New-Item -ItemType Directory -Path $setupScripts -Force | Out-Null
    $arguments = "-Preset $Preset"
    if ($DisableVBS) { $arguments += ' -DisableVBS' }
    (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'setup\SetupComplete.cmd') -Raw).Replace('__ARGS__', $arguments) |
        Set-Content -LiteralPath (Join-Path $setupScripts 'SetupComplete.cmd') -Encoding Ascii -NoNewline

    # --- 6. Pulizia componenti --------------------------------------------
    Write-Step 'Pulisco i componenti superati (alcuni minuti)'
    $cleanup = Invoke-ItsmeNative dism.exe @('/English', "/Image:$MountDir", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')
    if ($cleanup.ExitCode -ne 0) { Write-ItsmeLog "Pulizia componenti non completata (codice $($cleanup.ExitCode)), continuo" 'WARN' }

    # --- 7. Salvataggio e compressione --------------------------------------
    Write-Step "Salvo e ricomprimo l'immagine"
    Dismount-WindowsImage -Path $MountDir -Save | Out-Null
    $imageMounted = $false
    if ($Esd) {
        Export-WindowsImage -SourceImagePath $SingleWim -SourceIndex 1 `
            -DestinationImagePath (Join-Path $sources 'install.esd') -CompressionType recovery | Out-Null
    } else {
        Export-WindowsImage -SourceImagePath $SingleWim -SourceIndex 1 `
            -DestinationImagePath (Join-Path $sources 'install.wim') -CompressionType max | Out-Null
    }
    Remove-Item -LiteralPath $SingleWim -Force

    # --- 8. Primo avvio senza account Microsoft (opzionale) ----------------
    Write-Step 'Preparo il primo avvio'
    New-AutounattendXml | Set-Content -LiteralPath (Join-Path $IsoDir 'autounattend.xml') -Encoding UTF8
    if ($LocalUser) { Write-ItsmeLog "Account locale: $LocalUser (password vuota, impostala al primo accesso)" }

    # --- 9. ISO -------------------------------------------------------------
    Write-Step 'Creo la ISO'
    $bootData = '2#p0,e,b{0}#pEF,e,b{1}' -f (Join-Path $IsoDir 'boot\etfsboot.com'), (Join-Path $IsoDir 'efi\microsoft\boot\efisys.bin')
    $iso = Invoke-ItsmeNative $oscdimg @('-m', '-o', '-u2', '-udfver102', "-bootdata:$bootData", '-lITSMEOS', $IsoDir, $OutputIso)
    if ($iso.ExitCode -ne 0) { throw "oscdimg fallito (codice $($iso.ExitCode)): $($iso.Output)" }

    $size = (Get-Item -LiteralPath $OutputIso).Length / 1GB
    $minutes = ((Get-Date) - $started).TotalMinutes
    Write-Host ''
    Write-ItsmeLog ("ISO pronta: {0} ({1:N2} GB, {2:N0} minuti)" -f $OutputIso, $size, $minutes) 'OK'
    Write-ItsmeLog 'Scrivila su chiavetta con Rufus o Ventoy e installa come un Windows normale.' 'OK'
} finally {
    if ($imageMounted) {
        Write-ItsmeLog "Errore: scarto le modifiche all'immagine" 'ERROR'
        Dismount-WindowsImage -Path $MountDir -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
    if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
