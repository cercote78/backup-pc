# Backup PC

Utility PowerShell per Windows per creare un catalogo dei programmi e dei giochi
installati, reinstallare i pacchetti riconosciuti da winget e copiare in modo
selettivo file personali di configurazione e salvataggio. Non copia programmi,
giochi o installer nel backup dei dati personali.

## Installazione

Apri PowerShell nella cartella del repository ed esegui:

```powershell
.\Installa-BackupPC.ps1
```

Non servono privilegi amministrativi. L'installazione copia lo strumento in
`%LOCALAPPDATA%\Programs\BackupPC` e crea il collegamento “Backup PC” nel menu
Start. Per rimuoverlo, elimina quella cartella e il collegamento.

## Catalogo

Dal menu di Backup PC scegli l'opzione 1. Il catalogo include i programmi
registrati da Windows, le app Microsoft Store dell'utente corrente e i giochi
Steam ed Epic Games trovati nei rispettivi manifest. I giochi di altri launcher
possono apparire se registrati da Windows; il catalogo non è garantito completo.

Vengono creati file JSON e CSV in `Documenti\Backup PC\Inventario`. Per ogni
elemento sono riportati nome, versione, editore, posizione di installazione,
tipo e origine del rilevamento. Il catalogo non contiene i file installati,
licenze o credenziali.

## Reinstallare i programmi

Sul PC originale, scegli l'opzione 3. Winget crea un manifest JSON in
`Documenti\Backup PC\Ripristino`; copia quel file su un supporto o in una
posizione accessibile dal nuovo PC. Sul nuovo PC installa Backup PC e scegli
l'opzione 4, indicando il manifest. La utility mostra i pacchetti che verranno
installati e procede solo dopo la conferma esatta `INSTALL`. Le versioni
disponibili correnti vengono usate al posto delle versioni originarie.

La reinstallazione funziona solo per i pacchetti che winget riconosce e trova
nei cataloghi configurati. Esamina l'output di winget per avvisi o pacchetti
non installati; la utility interrompe l'operazione se winget restituisce un
errore. Giochi Steam/Epic, software non catalogato, acquisti, account, licenze
e attivazioni possono richiedere il launcher originale e un intervento manuale.
Questo manifest è separato dall'inventario CSV/JSON e va copiato
separatamente sul PC nuovo.

## Backup dei dati personali

Scegli l'opzione 2 e inserisci il percorso di una cartella specifica con
impostazioni o salvataggi, quindi il percorso di destinazione. Prima della
copia, lo strumento mostra i file riconosciuti (configurazioni e salvataggi),
il numero e la dimensione totale. La copia parte solo dopo aver digitato
esattamente `BACKUP`.

Sono inclusi solo file con estensioni comuni di configurazione e salvataggio:
`.cfg`, `.conf`, `.dat`, `.db`, `.dsv`, `.ini`, `.json`, `.log`, `.plist`,
`.sav`, `.save`, `.srm`, `.sqlite`, `.sqlite3`, `.toml`, `.txt`, `.xml`,
`.yaml` e `.yml`. Le estensioni eseguibili note, i file con intestazione
eseguibile Windows e le altre estensioni non vengono copiati.
Collegamenti simbolici e cartelle reparse point vengono saltati; errori di
lettura o copia interrompono l'operazione.

Non vengono scelti automaticamente cartelle personali né profili applicativi:
seleziona una sottocartella mirata che contenga solo i dati che vuoi conservare.
Sono rifiutate le cartelle radice del profilo e le posizioni di sistema o dei
programmi, nonché le cartelle di installazione rilevate e quelle che le
contengono. Esamina comunque attentamente l'anteprima prima di confermare.
Ogni backup è creato in una nuova cartella `BackupPC-<data-ora>` nella
destinazione scelta e contiene un manifest dei file copiati.

I dati in cartelle esterne alla sorgente scelta non vengono inclusi
automaticamente. Il backup non salva account, licenze, chiavi prodotto o
impostazioni di sistema.
