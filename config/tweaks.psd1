# Tweak di ItsmeOS, letti da build-iso.ps1 (immagine offline) e da
# Set-ItsmeProfile.ps1 (Windows già installato).
#
# Registry:
#   Hive     SOFTWARE | SYSTEM | USER  (vedi ItsmeOS.psm1)
#   Value    valore unico, applicato ai profili in Presets (o a tutti se manca),
#            oppure @{ Competitive = ..; Balanced = ..; Streaming = .. }
#            (un profilo assente dalla tabella non viene toccato)
#   Delete   $true per cancellare il valore invece di scriverlo
#
# Services: Start per profilo (Automatic, Manual, Disabled). I servizi che
# non esistono sulla macchina vengono saltati.
#
# Ogni modifica viene salvata nello stato e annullata da -Rollback.

@{
    Registry = @(
        # --- CPU e scheduler -------------------------------------------------
        @{
            Id = 'sched.quantum'; Hive = 'SYSTEM'; Path = 'Control\PriorityControl'
            Name = 'Win32PrioritySeparation'; Type = 'DWord'
            # 0x26: quanti brevi e variabili, boost 3:1 alla finestra in primo piano (il gioco)
            # 0x28: quanti brevi e fissi, nessun boost: OBS e l'encoder non perdono CPU
            Value = @{ Competitive = 0x26; Balanced = 0x26; Streaming = 0x28 }
        }
        @{
            Id = 'power.throttling.off'; Hive = 'SYSTEM'; Path = 'Control\Power\PowerThrottling'
            Name = 'PowerThrottlingOff'; Type = 'DWord'; Value = 1; Presets = @('Competitive', 'Streaming')
            Note = 'Niente EcoQoS sui processi in background (OBS, Discord) mentre giochi'
        }

        # --- MMCSS: priorità a giochi e audio ------------------------------
        @{
            Id = 'mmcss.responsiveness'; Hive = 'SOFTWARE'
            Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Name = 'SystemResponsiveness'; Type = 'DWord'
            # percentuale di CPU riservata ai task a bassa priorità (10 è il minimo accettato)
            Value = @{ Competitive = 10; Balanced = 10; Streaming = 20 }
        }
        @{
            Id = 'mmcss.network'; Hive = 'SOFTWARE'
            Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            Name = 'NetworkThrottlingIndex'; Type = 'DWord'; Value = 0xFFFFFFFF
        }
        @{ Id = 'mmcss.games.gpu'; Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Type = 'DWord'; Value = 8 }
        @{ Id = 'mmcss.games.priority'; Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Type = 'DWord'; Value = 6 }
        @{ Id = 'mmcss.games.category'; Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Type = 'String'; Value = 'High' }
        @{ Id = 'mmcss.games.sfio'; Hive = 'SOFTWARE'; Path = 'Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Type = 'String'; Value = 'High' }

        # --- Timer e GPU ---------------------------------------------------
        @{
            Id = 'timer.global'; Hive = 'SYSTEM'; Path = 'Control\Session Manager\kernel'
            Name = 'GlobalTimerResolutionRequests'; Type = 'DWord'; Value = 1
            Note = 'La risoluzione chiesta dal gioco (0,5-1 ms) vale per tutto il sistema, anche a finestra ridotta'
        }
        @{
            Id = 'gpu.hags'; Hive = 'SYSTEM'; Path = 'Control\GraphicsDrivers'
            Name = 'HwSchMode'; Type = 'DWord'; Value = 2
            Note = 'Hardware-accelerated GPU scheduling, serve anche al frame generation DLSS 3/4'
        }

        # --- Game Mode e Game DVR --------------------------------------------
        @{ Id = 'gamemode.auto'; Hive = 'USER'; Path = 'Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Type = 'DWord'; Value = 1 }
        @{ Id = 'gamemode.allow'; Hive = 'USER'; Path = 'Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Type = 'DWord'; Value = 1 }
        @{ Id = 'gamebar.startup.panel'; Hive = 'USER'; Path = 'Software\Microsoft\GameBar'; Name = 'ShowStartupPanel'; Type = 'DWord'; Value = 0 }
        @{
            Id = 'gamedvr.user'; Hive = 'USER'; Path = 'System\GameConfigStore'
            Name = 'GameDVR_Enabled'; Type = 'DWord'; Value = 0; Presets = @('Competitive', 'Balanced')
            Note = 'Niente registrazione continua in background (in Streaming registra OBS)'
        }
        @{ Id = 'gamedvr.policy'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Type = 'DWord'; Value = 0; Presets = @('Competitive', 'Balanced') }

        # --- Niente interruzioni ------------------------------------------
        @{ Id = 'keys.sticky'; Hive = 'USER'; Path = 'Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Type = 'String'; Value = '506'; Note = 'Shift premuto 5 volte non apre più il popup' }
        @{ Id = 'keys.filter'; Hive = 'USER'; Path = 'Control Panel\Accessibility\Keyboard Response'; Name = 'Flags'; Type = 'String'; Value = '122' }
        @{ Id = 'keys.toggle'; Hive = 'USER'; Path = 'Control Panel\Accessibility\ToggleKeys'; Name = 'Flags'; Type = 'String'; Value = '58' }
        @{ Id = 'tips.welcome'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Type = 'DWord'; Value = 0 }
        @{ Id = 'tips.suggestions'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Type = 'DWord'; Value = 0 }
        @{ Id = 'tips.softlanding'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Type = 'DWord'; Value = 0 }
        @{ Id = 'tips.silentapps'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Type = 'DWord'; Value = 0; Note = 'Windows non installa più app suggerite da solo' }
        @{ Id = 'tips.scoobe'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Type = 'DWord'; Value = 0; Note = 'Niente schermata "completa la configurazione del PC" dopo gli aggiornamenti' }
        @{ Id = 'defender.summary'; Hive = 'SOFTWARE'; Path = 'Microsoft\Windows Defender Security Center\Virus and threat protection'; Name = 'SummaryNotificationDisabled'; Type = 'DWord'; Value = 1; Note = 'Solo i riepiloghi: gli avvisi di minaccia restano' }
        @{
            Id = 'background.uwp'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\AppPrivacy'
            Name = 'LetAppsRunInBackground'; Type = 'DWord'; Value = 2; Presets = @('Competitive')
            Note = 'Le app dello Store non girano in background. Le app desktop (Discord, Steam) non sono toccate'
        }
        @{ Id = 'edge.startupboost'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Type = 'DWord'; Value = 0 }
        @{ Id = 'edge.background'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled'; Type = 'DWord'; Value = 0 }

        # --- Windows Update: limitato, non spento -----------------------------
        @{ Id = 'wu.noreboot'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoRebootWithLoggedOnUsers'; Type = 'DWord'; Value = 1; Note = 'Mai riavvii automatici con un utente collegato' }
        @{ Id = 'wu.nodrivers'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ExcludeWUDriversInQualityUpdate'; Type = 'DWord'; Value = 1; Note = 'Windows Update non sostituisce il driver GPU che hai scelto' }
        @{ Id = 'wu.p2p'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Type = 'DWord'; Value = 0; Note = 'Niente upload P2P degli aggiornamenti verso altri PC' }

        # --- Telemetria, AI e pubblicità ------------------------------------
        @{ Id = 'telemetry.policy'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0 }
        @{ Id = 'consumer.features'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Type = 'DWord'; Value = 1 }
        @{ Id = 'ads.id'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Type = 'DWord'; Value = 0 }
        @{ Id = 'recall.off'; Hive = 'SOFTWARE'; Path = 'Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1; Note = 'Recall non cattura lo schermo in background' }
        @{ Id = 'copilot.off'; Hive = 'USER'; Path = 'Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1 }
        @{ Id = 'search.web'; Hive = 'USER'; Path = 'Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Type = 'DWord'; Value = 1; Note = 'La ricerca di Start non interroga Bing' }
        @{ Id = 'onedrive.autosetup'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run'; Name = 'OneDriveSetup'; Delete = $true; Note = 'OneDrive non si installa da solo al primo accesso (resta installabile)' }

        # --- Input e grafica del desktop ------------------------------------
        @{ Id = 'mouse.accel.speed'; Hive = 'USER'; Path = 'Control Panel\Mouse'; Name = 'MouseSpeed'; Type = 'String'; Value = '0'; Presets = @('Competitive') }
        @{ Id = 'mouse.accel.t1'; Hive = 'USER'; Path = 'Control Panel\Mouse'; Name = 'MouseThreshold1'; Type = 'String'; Value = '0'; Presets = @('Competitive') }
        @{ Id = 'mouse.accel.t2'; Hive = 'USER'; Path = 'Control Panel\Mouse'; Name = 'MouseThreshold2'; Type = 'String'; Value = '0'; Presets = @('Competitive') }
        @{ Id = 'ui.transparency'; Hive = 'USER'; Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Type = 'DWord'; Value = 0; Presets = @('Competitive') }
    )

    Services = @(
        @{ Name = 'DiagTrack'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' }; Note = 'Telemetria' }
        @{ Name = 'dmwappushservice'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' } }
        @{ Name = 'MapsBroker'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' } }
        @{ Name = 'RetailDemo'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' } }
        @{ Name = 'TrkWks'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' } }
        @{ Name = 'Fax'; Start = @{ Competitive = 'Disabled'; Balanced = 'Disabled'; Streaming = 'Disabled' } }
        @{ Name = 'SysMain'; Start = @{ Competitive = 'Disabled'; Streaming = 'Disabled' }; Note = 'Superfetch: utile sugli HDD, sugli SSD occupa RAM e disco mentre giochi' }
        @{ Name = 'WSearch'; Start = @{ Competitive = 'Disabled' }; Note = 'Indicizzazione: la ricerca file da Start diventa più lenta' }
        @{ Name = 'PcaSvc'; Start = @{ Competitive = 'Manual' } }
        # I servizi Xbox (XblAuthManager, XboxGipSvc, ...) restano Manuali:
        # servono a Game Pass e ai controller Xbox e partono solo se usati.
    )
}
