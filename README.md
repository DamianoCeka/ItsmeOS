# ItsmeOS

Windows 11 ottimizzato per il gaming competitivo e per chi gioca e streamma
sullo stesso PC.

ItsmeOS non è una ISO da scaricare. È un insieme di script che:

- **crea la tua ISO** partendo dalla ISO ufficiale di Windows 11 (`build-iso.ps1`)
- **ottimizza un Windows già installato**, senza reinstallare (`Set-ItsmeProfile.ps1`)
- **mentre giochi spegne tutto ciò che interrompe**: notifiche, processi in
  background, download degli aggiornamenti e indicizzazione
  (`Start-ItsmeGameSession.ps1`)

Ogni modifica viene salvata in un backup e si annulla con un comando.

> Stato: **v0.1, in sviluppo**. La CI prova profili e rollback su Windows a
> ogni commit, ma la ISO va ancora provata su PC veri. Vedi
> [Da verificare](#da-verificare).

## Perché non una ISO già pronta

Ridistribuire una ISO di Windows modificata viola la licenza Microsoft, e una
ISO scaricata da sconosciuti è il modo più semplice per prendersi un malware.
Qui ognuno crea la propria ISO dalla propria copia ufficiale di Windows, e
può leggere ogni riga di quello che cambia.

## Compatibilità con gli anti-cheat

Gli anti-cheat chiedono sempre più sicurezza a Windows:

- **Vanguard** (VALORANT, League of Legends) può richiedere TPM 2.0, Secure
  Boot, Memory Integrity (HVCI) e IOMMU. Senza, il gioco non parte (errori
  VAN 9001, VAN 9003, VAN:RESTRICTION:5).
- **FACEIT** richiede TPM 2.0 e Secure Boot a tutti dal 25 novembre 2025,
  VBS e IOMMU sopra i 3000 Elo, e Windows aggiornato.
- **Call of Duty** (Ricochet), **Battlefield 6**, i tornei di **Fortnite** e
  alcuni server di **Rust** (Easy Anti-Cheat) richiedono TPM 2.0 e Secure Boot.

ItsmeOS lascia acceso tutto questo: TPM, Secure Boot, VBS, Memory Integrity,
Defender e gli aggiornamenti di sicurezza. Non aggira i controlli
hardware dell'installazione. Diversi progetti simili invece spengono VBS
di default (vedi [Differenze con gli altri progetti](#differenze-con-gli-altri-progetti)).

La sessione di gioco non apre il processo del gioco: legge solo il percorso
dell'eseguibile, come fa Gestione attività.

## Cosa migliora davvero

| | Windows 11 standard | ItsmeOS (obiettivo) |
|---|---|---|
| Spazio su disco dopo l'installazione | 25-30 GB | 15-18 GB |
| RAM occupata a riposo | 3-4 GB | 2-2,5 GB |
| Processi a riposo | 150-200 | 90-120 |
| Interruzioni durante il gioco | notifiche, aggiornamenti, popup | nessuna |

### Stima: quanto meglio gira un gioco rispetto a Windows normale

| Situazione | FPS medi | 1% low (scatti) |
|---|---|---|
| Esport limitati dalla CPU (VALORANT, CS2, Fortnite competitivo, 300+ FPS) | +2-8% | +3-10% |
| PC medio o portatile (6 core, 16 GB) | +3-10% | +5-15% |
| Mentre Windows lavora in background (aggiornamenti, indicizzazione, OneDrive) | +5-15% | +10-30% |
| Tripla A limitati dalla GPU (1440p-4K, sotto i 144 FPS) | +0-2% | +0-5% |

Esempio su VALORANT con un PC da 400 FPS medi e 1% low a 220: con
Competitive ci aspettiamo circa 410-430 FPS medi e 1% low tra 225 e 240.
La differenza più grande si sente quando Windows lavora in background:
spariscono gli scatti causati da aggiornamenti, indicizzazione e notifiche
a metà partita.

Il guadagno principale è nella **stabilità dei frame** (1% low, frame time
regolari) e nell'**assenza di interruzioni**, non negli FPS medi. Più il PC è
potente e il gioco pesa sulla GPU, meno si guadagna. Chi promette +50% FPS
da un tweak di Windows sta vendendo qualcosa.

Le prime due righe si basano sull'unico test indipendente trovato su un
progetto simile: PC Games Hardware, marzo 2024, AtlasOS 0.3.2 contro
Windows 11 23H2 su 11 giochi a 1080p. FPS medi da +2% a +8%, 1% low fino a
+8%, RAM a riposo 1,6 GB contro 2,4. Le righe sul carico in background sono
nostre stime, non ancora misurate. Le misureremo con
CapFrameX o PresentMon prima e dopo, sullo stesso PC e sulle stesse partite,
e sostituiremo questa tabella con i risultati reali.

## Differenze con gli altri progetti

| | Come funziona | VBS / Memory Integrity | Defender e Update | Torna indietro senza reinstallare | Durante il gioco |
|---|---|---|---|---|---|
| **ItsmeOS** | ISO personale dalla tua ISO ufficiale, oppure profilo su Windows già installato | restano accesi (`-DisableVBS` opzionale) | Defender acceso, Update attivi senza riavvii forzati | sì, ai tuoi valori di partenza | notifiche spente, app in background sospese, Update in pausa |
| **AtlasOS** | playbook AME Wizard su Windows appena installato | opzione "Disattiva isolamento core" attiva di default | Defender acceso, aggiornamenti automatici spenti di default | no, si reinstalla | nessuna funzione automatica |
| **ReviOS** | playbook AME Wizard | spenti sempre | Defender rimosso di default, Update in pausa fino al 2038 | in parte, dalla 25.10 | nessuna funzione automatica |
| **tiny11** | ISO ridotta da installare da zero, salta i controlli TPM/Secure Boot del setup | non documentato | standard: restano; Core: tolti | no | nessuna funzione automatica |
| **WinUtil** | tweak su Windows installato e creatore ISO | non li tocca | Defender intatto, Update a scelta | in parte, ai default di Windows | nessuna funzione automatica |
| **ISO già modificate** (Ghost Spectre e simili) | ISO scaricate da terzi, pensate anche per PC senza TPM | non documentato | esistono versioni senza Defender, Update sospendibili fino al 2077 | no | non documentato |
| **Game Mode, Razer Cortex, Process Lasso** | impostazioni o app sopra Windows normale | non li toccano | Defender intatto; Game Mode blocca driver e riavvii mentre giochi | sì, è tutto temporaneo | priorità al gioco, "Non disturbare", chiusura processi |

In sintesi, cosa cambia con ItsmeOS:

- **Anti-cheat**: non spegne la sicurezza che Vanguard e FACEIT richiedono.
  Atlas e ReviOS spengono VBS di default; FACEIT dichiara di non supportare i
  Windows modificati che bloccano gli aggiornamenti.
- **Rollback ai tuoi valori**: ogni modifica si annulla senza reinstallare.
  WinUtil torna ai default di Windows, Atlas e tiny11 richiedono una
  reinstallazione.
- **Sessione di gioco nello stesso strumento**: i progetti di debloat non
  fanno nulla mentre giochi. Game Mode e i game booster fanno pezzi simili;
  ItsmeOS in più ferma aggiornamenti e indicizzazione, non apre mai il
  processo del gioco e non chiede un account.
- **Profilo Streaming** per chi gioca e trasmette con OBS sullo stesso PC.

Dove gli altri sono avanti: anni di uso reale e community grandi (Atlas,
tiny11, WinUtil), un'interfaccia grafica, toggle singoli, configurazioni
esportabili e punti di ripristino. Sono nei prossimi passi.

Fonti: [Riot, requisiti di sicurezza di Vanguard](https://support.riotgames.com/riot/performance/vanguard-security-requirements),
[Riot, VAN:RESTRICTION:5](https://support.riotgames.com/riot/penalties/error-van-restriction-5),
[FACEIT, requisiti di sicurezza di Windows](https://support.faceit.com/hc/en-us/articles/23117181142556-Windows-Security-Requirements-FAQ),
[FACEIT, aggiornamenti mancanti](https://support.faceit.com/hc/en-us/articles/360014237719-Your-system-is-missing-important-Windows-security-updates),
[Atlas, playbook.conf](https://github.com/Atlas-OS/Atlas/blob/main/src/playbook/playbook.conf),
[Atlas, tornare indietro](https://docs.atlasos.net/faq/install-faq/reverting-atlas/),
[ReviOS, vbs.yml](https://github.com/meetrevision/playbook/blob/main/src/Configuration/Tasks/registry/security/vbs.yml),
[tiny11builder](https://github.com/ntdevlabs/tiny11builder),
[WinUtil, tweaks.json](https://github.com/ChrisTitusTech/winutil/blob/main/config/tweaks.json),
[PC Games Hardware, AtlasOS contro Windows 11](https://www.pcgameshardware.de/Windows-11-Software-277633/Specials/AtlosOS-im-Vergleich-mit-Windows-11-1442750/).
Verificato a ottobre 2026: questi progetti cambiano spesso.

## Profili

| | Competitive | Balanced | Streaming |
|---|:---:|:---:|:---:|
| Scheduler: priorità al gioco in primo piano | ✓ | ✓ | |
| Scheduler: CPU equa per gioco e OBS | | | ✓ |
| MMCSS: GPU e CPU prioritarie per i giochi | ✓ | ✓ | ✓ |
| Rete senza throttling multimediale | ✓ | ✓ | ✓ |
| Timer ad alta risoluzione globale | ✓ | ✓ | ✓ |
| Hardware GPU scheduling (serve al frame generation) | ✓ | ✓ | ✓ |
| Interrupt MSI per la scheda video | ✓ | ✓ | ✓ |
| Piano energetico Prestazioni eccellenti, core parking spento | ✓ | | ✓ |
| Nessun EcoQoS sui processi in background | ✓ | | ✓ |
| Game DVR spento | ✓ | ✓ | |
| Accelerazione del mouse spenta | ✓ | | |
| ACK TCP immediato (Nagle) | ✓ | | |
| App dello Store bloccate in background | ✓ | | |
| SysMain (Superfetch) spento | ✓ | | ✓ |
| Indicizzazione dei file spenta | ✓ | | |
| Telemetria, Recall, Copilot, pubblicità e suggerimenti spenti | ✓ | ✓ | ✓ |
| Windows Update senza riavvii automatici e senza driver GPU | ✓ | ✓ | ✓ |
| Popup tasti permanenti (Shift x5) spento | ✓ | ✓ | ✓ |
| Ibernazione e spazio riservato agli aggiornamenti liberati | ✓ | ✓ | ✓ |
| Sessione di gioco automatica | ✓ | ✓ | ✓ |

Sui portatili il piano energetico e l'ibernazione restano invariati.

Ogni tweak, con il motivo, è in [`config/tweaks.psd1`](config/tweaks.psd1).

## Sessione di gioco

Parte da sola all'accesso. Quando apri un gioco:

- spegne le notifiche di Windows
- sospende OneDrive, Teams, Widget, Collegamento al telefono (0% CPU, 0 I/O)
- ferma il download degli aggiornamenti, l'upload P2P e l'indicizzazione dei file

Quando chiudi il gioco, dopo 15 secondi rimette tutto com'era.

Riconosce i giochi per nome (VALORANT, CS2, League of Legends, Fortnite,
Apex, Rainbow Six, Call of Duty, Overwatch, Rocket League, PUBG, Marvel
Rivals, GTA V) e qualsiasi eseguibile nelle cartelle di Steam, Epic, Riot,
Xbox, EA e Ubisoft. Lista dei giochi e dei processi da sospendere in
[`config/session.psd1`](config/session.psd1).

Cosa ha fatto in ogni partita è scritto in `%LOCALAPPDATA%\ItsmeOS\session.log`.

Per provare la configurazione con un gioco aperto:

```powershell
C:\ItsmeOS\Start-ItsmeGameSession.ps1 -Once
```

## Creare la ISO

Serve un PC con Windows 10 o 11, 25 GB liberi e circa 30-45 minuti.

1. Scarica la ISO ufficiale di Windows 11 da
   [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11)
2. Installa i Deployment Tools di Windows ADK (servono per `oscdimg`):
   ```powershell
   winget install Microsoft.WindowsADK
   ```
3. Scarica questo repository, apri PowerShell **come amministratore** nella
   sua cartella e lancia:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\build-iso.ps1 -IsoPath D:\Win11_24H2_Italian_x64.iso -Preset Competitive -LocalUser TuoNome
   ```
4. Scrivi la ISO generata su una chiavetta con [Rufus](https://rufus.ie) o
   [Ventoy](https://www.ventoy.net) e installa come un Windows normale.

Opzioni di `build-iso.ps1`:

| Opzione | |
|---|---|
| `-Preset` | `Competitive`, `Balanced` (predefinito) o `Streaming` |
| `-Edition` | edizione da tenere, predefinita `Windows 11 Pro` |
| `-LocalUser` | crea un account locale e salta l'account Microsoft (password vuota, impostala al primo accesso) |
| `-DisableVBS` | spegne VBS e HVCI, sconsigliato con VALORANT e FACEIT (vedi sotto) |
| `-Esd` | ISO più piccola, creazione più lenta |
| `-OutputIso` | percorso della ISO generata |

Consiglio: durante la creazione escludi la cartella `C:\ItsmeOS-build` dalla
scansione in tempo reale di Defender, la creazione è molto più veloce.

## Usarlo su Windows già installato

Non serve reinstallare. Da PowerShell come amministratore, nella cartella del
repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Set-ItsmeProfile.ps1 -Preset Competitive
```

Poi riavvia. Su ItsmeOS installato dalla ISO gli script sono in `C:\ItsmeOS`.

## Tornare indietro

```powershell
.\Set-ItsmeProfile.ps1 -Rollback
```

Ripristina ogni valore di registro, servizio, piano energetico, ibernazione
e spazio riservato com'era prima del primo profilo applicato, e rimuove la
sessione di gioco. Le app tolte dalla ISO si reinstallano dal Microsoft
Store.

## VBS e HVCI

`-DisableVBS` spegne la sicurezza basata sulla virtualizzazione
(Isolamento core). In alcuni giochi vale qualche punto percentuale, ma
riduce la protezione del kernel da driver malevoli.

**Non usarlo se giochi a VALORANT o su FACEIT.** Vanguard può bloccare il
gioco quando Memory Integrity non è attivo (errore VAN:RESTRICTION:5), e
FACEIT richiede VBS sopra i 3000 Elo. È spenta di default: usala solo per
giochi senza anti-cheat kernel e solo se misuri un guadagno sul tuo PC.

## Cosa non facciamo

- **Non disattiviamo Windows Update né Defender.** Li limitiamo: niente
  riavvii automatici, niente driver GPU sostituiti, niente download mentre
  giochi. Un PC da gaming senza aggiornamenti di sicurezza è un bersaglio.
- **Non rimuoviamo componenti di sistema** (Edge WebView2, .NET, servizi
  Xbox, codec): giochi, launcher, OBS e anti-cheat ne hanno bisogno.
- **Non aggiriamo TPM e Secure Boot**: Vanguard e FACEIT li richiedono.

## Struttura

| File | |
|---|---|
| `build-iso.ps1` | crea la ISO |
| `Set-ItsmeProfile.ps1` | applica un profilo o fa il rollback |
| `Start-ItsmeGameSession.ps1` | sessione di gioco senza interruzioni |
| `ItsmeOS.psm1` | motore: registro online e offline, backup, rollback |
| `config/tweaks.psd1` | tutti i tweak, per profilo |
| `config/session.psd1` | giochi, processi da sospendere, servizi da mettere in pausa |
| `config/appx-remove.txt` | app rimosse dalla ISO |
| `config/capabilities-remove.txt` | funzionalità opzionali rimosse dalla ISO |
| `setup/SetupComplete.cmd` | applica il profilo al primo avvio |
| `tests/` | prova profili e rollback su Windows (in CI) |

## Da verificare

La CI applica ogni profilo e fa il rollback su Windows a ogni commit. Restano
da provare su PC e VM:

- [ ] `build-iso.ps1` con la ISO italiana di Windows 11 24H2 e 25H2
- [ ] installazione da chiavetta, primo avvio con `-LocalUser`
- [ ] `SetupComplete.cmd` applica il profilo (log in `C:\ItsmeOS\logs`)
- [ ] le notifiche si spengono davvero durante il gioco senza riavviare Explorer
- [ ] VALORANT (Vanguard) e CS2 su FACEIT partono senza errori
- [ ] misure prima/dopo con CapFrameX: FPS medi, 1% low, frame time
- [ ] RAM, processi e spazio su disco a riposo

## Prossimi passi

- affinità degli interrupt (GPU e scheda di rete su core diversi da quelli del gioco)
- rilevamento dei giochi a schermo intero, oltre alla lista
- interfaccia grafica per scegliere profilo e opzioni
- attivare e disattivare i singoli tweak, non solo i profili interi
- esportare e importare una configurazione (stessa config su tutti i PC di un team o di un evento)
- punto di ripristino di Windows prima di applicare un profilo

## Licenza

[GPL-3.0](LICENSE). Puoi usarlo, modificarlo e ridistribuirlo, ma chi
pubblica una versione modificata deve rilasciarne il codice con la stessa
licenza.
