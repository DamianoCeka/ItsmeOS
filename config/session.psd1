# Sessione di gioco: cosa fa ItsmeOS mentre un gioco è aperto.
# Start-ItsmeGameSession.ps1 controlla i processi ogni PollSeconds secondi.
# Quando trova un gioco spegne le notifiche, sospende i processi in Suspend e
# mette in pausa i servizi in PauseServices. Quando il gioco è chiuso da
# EndGraceSeconds secondi rimette tutto come prima.

@{
    PollSeconds     = 3
    EndGraceSeconds = 15

    # Notifiche di Windows spente durante il gioco
    MuteNotifications = $true

    # Giochi riconosciuti per nome dell'eseguibile (senza .exe)
    Games = @(
        'VALORANT-Win64-Shipping'
        'cs2'
        'League of Legends'
        'FortniteClient-Win64-Shipping'
        'r5apex', 'r5apex_dx12'
        'RainbowSix', 'RainbowSix_Vulkan'
        'cod'
        'Overwatch'
        'RocketLeague'
        'TslGame'
        'Marvel-Win64-Shipping'
        'GTA5', 'GTA5_Enhanced'
    )

    # Ogni eseguibile dentro queste cartelle è considerato un gioco
    GameFolders = @(
        '*\steamapps\common\*'
        '*\Epic Games\*'
        '*\Riot Games\*'
        '*\XboxGames\*'
        '*\EA Games\*'
        '*\Ubisoft Game Launcher\games\*'
    )

    # Eseguibili nelle cartelle dei giochi che non sono il gioco
    # (launcher, anti-cheat, crash handler, installer)
    NotGames = @(
        'RiotClientServices', 'RiotClientUx', 'RiotClientUxRender', 'RiotClientCrashHandler'
        'LeagueClient', 'LeagueClientUx', 'LeagueClientUxRender', 'LeagueCrashHandler64'
        'EpicGamesLauncher', 'EpicWebHelper', 'EpicOnlineServicesHost'
        'EasyAntiCheat', 'EasyAntiCheat_EOS', 'EasyAntiCheat_EOS_Setup', 'start_protected_game'
        'BEService', 'BEService_x64'
        'UnityCrashHandler32', 'UnityCrashHandler64', 'CrashReportClient'
        'vc_redist.x64', 'vc_redist.x86', 'DXSETUP', 'dotNetFx40_Full_setup'
    )

    # Processi sospesi (congelati, 0% CPU) durante il gioco e ripresi dopo.
    # Aggiungi solo programmi che non ti servono mentre giochi: un processo
    # sospeso non risponde finché la partita non finisce.
    Suspend = @(
        'OneDrive'
        'ms-teams'
        'Widgets'
        'WidgetService'
        'PhoneExperienceHost'
        'CrossDeviceService'
    )

    # Servizi fermati durante il gioco e fatti ripartire dopo:
    # download degli aggiornamenti, upload P2P e indicizzazione dei file.
    PauseServices = @(
        'wuauserv'
        'BITS'
        'DoSvc'
        'WSearch'
    )
}
