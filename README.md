# Backup PC

Backup PC salva su un disco esterno le cartelle personali comuni e un
inventario dei programmi installati. In seguito può ricopiare i file mancanti
e reinstallare, con winget, i programmi disponibili nel suo catalogo.

## Installazione

Installa il programma una volta con `Installa-BackupPC.ps1`. Nel menu Start
trovi due collegamenti: **Backup PC - Crea backup** e **Backup PC** (ripristino).

## Due comandi PowerShell

Collega il disco USB come unità `E:`. Le stringhe seguenti usano
`E:\BackupPC`; per un altro percorso aggiungi il parametro
`-DestinationRoot "F:\BackupPC"`.

**Creare un backup:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\BackupPC\scripts\Backup-PC.ps1"
```

**Ripristinare il backup più recente:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\BackupPC\scripts\Restore-PC.ps1"
```

Il ripristino mostra il backup e i programmi trovati e continua solo se digiti
`RIPRISTINA`. Copia i file mancanti senza sovrascrivere o cancellare quelli già
presenti. I programmi vengono installati solo dopo la conferma. Per selezionare
un backup diverso, passa il suo percorso come argomento:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\BackupPC\scripts\Restore-PC.ps1" -BackupPath "E:\BackupPC\2026-10-18_140000"
```

## Cosa viene salvato

- Desktop, Documenti, Download, Immagini, Musica, Video e la cartella Windows
  “Saved Games”, se esistono. Dentro Documenti sono inclusi anche eventuali
  salvataggi di gioco che i giochi conservano lì.
- Un inventario dei programmi desktop e delle app Microsoft Store.
- Gli identificativi dei programmi che `winget` riesce a riconoscere e
  reinstallare da `winget`.

Ogni backup è una nuova cartella datata (`E:\BackupPC\AAAA-MM-GG_HHMMSS`): non
elimina i backup precedenti. Durante la copia i file non accessibili o gli
errori di spazio vengono segnalati.

## Cosa non può garantire

Un backup di file e inventario **non è un’immagine completa del PC**. Non
salva Windows, il contenuto delle cartelle Program Files, i giochi installati
e le relative librerie, i profili completi di AppData, le impostazioni di ogni
programma, né tutti i salvataggi di gioco. I launcher come Steam, Epic e Xbox
possono dover riscaricare i giochi; verifica che i salvataggi siano sincronizzati
nel cloud o presenti nelle cartelle salvate. Per proteggere i salvataggi in
AppData occorre aggiungere consapevolmente le cartelle specifiche del gioco.

Un'app non riconosciuta da winget resta nell'inventario, ma richiede
reinstallazione manuale dal produttore. Non vengono salvati installer,
password, chiavi prodotto, licenze, account o attivazioni. Alcuni programmi
a pagamento potrebbero richiedere nuovamente la licenza. Per link ai produttori
e alle ricerche Microsoft Store, consulta
[Installazioni manuali](INSTALLAZIONI-MANUALI.md).

Il ripristino **non promette di non perdere nulla** e non sostituisce una copia
completa o un'immagine di sistema. Controlla periodicamente che il disco USB
sia leggibile e che i file di backup si aprano.
