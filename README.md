# Backup PC

Inventario personale dei programmi riconosciuti da [winget](https://learn.microsoft.com/windows/package-manager/winget/) e script PowerShell per reinstallarli su Windows. Il repository e `manifest\apps.json` sono personali: mantieni privato il repository.

## Installare Backup PC

Per installare lo strumento nel profilo utente e aggiungere il collegamento
“Backup PC” al menu Start, apri PowerShell nella cartella del repository ed
esegui:

```powershell
.\Installa-BackupPC.ps1
```

Non servono privilegi amministrativi. Questo installa solo gli script e il
manifest di Backup PC, non i programmi elencati. Per rimuovere lo strumento,
elimina la cartella `%LOCALAPPDATA%\Programs\BackupPC` e il collegamento
“Backup PC” dal menu Start.

## Inventario

Lo script `scripts\Export-BackupManifest.ps1` crea o aggiorna il manifest sul PC:

```powershell
.\scripts\Export-BackupManifest.ps1
```

Il manifest incluso è stato generato con `winget export` dal PC corrente e contiene solo identificativi winget, non installer. Lo script filtra componenti Windows, runtime condivisi, servizi di supporto ai driver e programmi di stampa specifici del dispositivo; non include i programmi “Disable Windows Defender” o “Disable Windows Defender 2.0”. Rivedi il manifest prima di ogni ripristino. L'esportazione winget non è un elenco completo di tutte le applicazioni: quelle non riconosciute o non disponibili in winget non vengono installate automaticamente.

## Ripristino

Su Windows con winget disponibile, esegui:

```powershell
.\scripts\Restore-Backup.ps1
```

Lo script mostra tutti i pacchetti e procede solo se digiti esattamente `INSTALL`. Ogni errore di winget interrompe l'operazione e viene riportato. Non modifica Defender, firewall o altre impostazioni di sicurezza.

Il collegamento del menu Start avvia PowerShell con `-ExecutionPolicy Bypass`
solo per quel processo, così una policy locale che blocca gli script non
impedisce il ripristino. Non cambia la policy permanente del sistema.

## Limiti

- I programmi non disponibili in winget richiedono installazione manuale.
- Programmi a pagamento, licenze, chiavi prodotto, account e attivazioni non vengono copiati o ripristinati. In particolare, le installazioni Microsoft Office, Project e Visio presenti sul PC richiedono i rispettivi canali e licenze.
- Driver, runtime condivisi, componenti di Windows, dati personali e impostazioni non fanno parte del ripristino.
- Le versioni disponibili in winget possono essere diverse o più recenti di quelle installate originariamente.
