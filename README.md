# FrancyPages

**Versione 1.0.0** — Libreria personale di spartiti PDF in Flutter, con profili separati, lettore integrato, metronomo e trasposizione degli accordi.

FrancyPages conserva i PDF direttamente sul dispositivo: nessun account, nessun cloud, nessun dato inviato all'esterno.

## Download

La release **v1.0.0** è disponibile nella pagina [Releases](https://github.com/FrancyCoso2010/FrancyPages/releases/latest).

- **Android:** `FrancyPages-1.0-android.apk`
- **iOS:** `FrancyPages-1.0-ios-unsigned.ipa`

> L'APK Android è pronto per l'installazione (è necessario consentire l'installazione da origini sconosciute).
>
> L'IPA iOS è **non firmato**: contiene l'app compilata per iPhone/iPad, ma per installarla serve firmarla con un certificato Apple e un provisioning profile. Senza firma non può essere installato su un dispositivo. La build iOS richiede macOS e Xcode.

## Funzionalità

- **Profili separati** (chiesa, band di scuola, personale…): crea, rinomina ed elimina profili; ogni brano appartiene a un profilo e può essere spostato in un altro.
- **Menu laterale** per passare tra **Brani** (libreria e ricerca) e **Dettagli brani** (solo i brani del profilo attivo, con gestione completa di titolo, autore, tonalità e tempo).
- **Dettagli del brano** modificabili: titolo, autore, tonalità, tempo (BPM), metro, profilo e PDF. I brani si aggiungono, modificano ed eliminano solo da **Dettagli brani**; **Brani** serve solo a consultare e aprire gli spartiti.
- **Lettura automatica del PDF all'importazione**: titolo, autore, tonalità, tempo e metro vengono ricavati dallo spartito. Se il tempo non è indicato viene impostato a **120 BPM** e il metro a **4/4**. Tutti i campi restano modificabili.
- **Ricerca** per titolo, autore e tonalità, ordinamento per recenti o nome (ricordato) e pull-to-refresh.
- **Lettore con sola barra superiore**: pagina corrente e avanzamento in alto, nessun controllo in basso. Lo scorrimento si aggancia alla pagina (snap) quando si ferma, senza interferire con lo zoom.
- **Accordi trasposti**: riconosce notazione italiana e inglese (`Fa#-`, `Si-9`, `F#m7`, `Bbmaj7`…) anche quando pdfrx divide l'accordo in più frammenti. Il riquadro bianco copre l'accordo originale con la versione trasposta, da -11 a +11 semitoni.
- **Analisi progressiva degli accordi**: il lettore parte dalla pagina aperta e mostra gli accordi man mano che le pagine vengono analizzate, senza attendere l'intero documento.
- **Metronomo integrato**: BPM 30–240, metro, accento sul primo battito, suono oppure battito visivo. Parte dal tempo e dal metro del brano.
- **Gesti configurabili**: swipe verticale o orizzontale, swipe attivo/disattivo, cambio pagina toccando i lati dello spartito.
- **Ripresa automatica** dall'ultima pagina letta, salvata anche quando l'app va in background.
- **Migrazione automatica** dei PDF della versione precedente nel profilo "Personale".
- Tema Material 3 chiaro/scuro e interfaccia in italiano.

## Come funziona il riconoscimento

1. Il testo delle prime pagine viene estratto con PDFium tramite `pdfrx`.
2. Si cercano indicazioni come `♩ = 96`, `BPM 120`, `M.M. 108`, `3/4`, `Do maggiore`, `A minor`, oltre ai metadati PDF `/Title` e `/Author`.
3. Il nome del file è un'ulteriore fonte: ad esempio `Notturno - Chopin.pdf` fornisce titolo e autore.
4. La tonalità viene ricavata anche dall'armatura: il numero di diesis o bemolli indica la tonalità (3 diesis = La maggiore oppure Fa♯ minore). Se il modo non è indicato si sceglie il maggiore.
5. Per gli accordi, i frammenti di testo vengono ricomposti in righe visive e uniti quando pdfrx separa radice, qualità e basso (`Fa#` + `-` + `7/do#`).
6. Nei PDF scansionati (solo immagini) il testo non c'è: si usa il nome del file, **120 BPM** e **4/4**. I dati sono best-effort e sempre modificabili; anche gli accordi non sono disponibili senza testo.

## Requisiti

- Flutter 3.47 o superiore (Dart 3.13).
- Android SDK per l'APK.
- macOS con Xcode e CocoaPods per compilare iOS.
- `pdfrx` supporta Android, iOS, desktop e web; lo sviluppo e le prove principali sono su Android.

## Avvio in sviluppo

```bash
flutter pub get
flutter run
```

## Build

### Android

```bash
flutter build apk --release
```

File prodotto:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Per un APK più piccolo destinato a un solo tipo di dispositivo:

```bash
flutter build apk --release --split-per-abi
```

### iOS

Su macOS con Xcode configurato:

```bash
flutter build ipa --release
```

Per verificare la compilazione senza firmare:

```bash
flutter build ios --release --no-codesign
```

Il workflow `.github/workflows/ios-unsigned.yml` compila automaticamente un IPA non firmato su un runner macOS di GitHub Actions. L'artefatto va poi firmato con un certificato Apple prima dell'installazione.

## Verifiche

```bash
flutter analyze
flutter test
```

La suite copre servizi della libreria, metadati PDF, metronomo, accordi e schermate principali.

## Struttura

```text
lib/
  main.dart                           configurazione app e tema
  models/profile.dart                 profili della libreria
  models/piece.dart                   brano con dettagli e indicazioni musicali
  screens/home_screen.dart            profili, elenco, ricerca e apertura PDF
  screens/piece_editor_screen.dart    dettagli brano: aggiungi, modifica, elimina
  screens/settings_screen.dart        profili, gesti, metronomo, riconoscimento
  screens/pdf_viewer_screen.dart      lettore, metronomo, accordi e snap
  screens/piece_details_screen.dart   dettagli dei brani del profilo attivo
  widgets/app_drawer.dart             menu laterale Brani / Dettagli brani
  widgets/meta_chip.dart              etichette compatte per i metadati
  services/library_service.dart       persistenza di profili e brani, file PDF
  services/pdf_metadata_service.dart  estrazione e riconoscimento dei dati
  services/settings_service.dart      preferenze di interfaccia
  services/metronome_controller.dart  motore del metronomo (WAV in memoria)
  services/chord_service.dart         riconoscimento e trasposizione degli accordi
test/
  widget_test.dart
  library_service_test.dart
  pdf_metadata_service_test.dart
  metronome_test.dart
  chord_service_test.dart
```

I PDF importati vengono salvati in `<Documenti dell'app>/FrancyPages`.

## Dipendenze principali

- `pdfrx` (Apache 2.0, PDFium) per il lettore PDF, l'estrazione del testo e gli accordi con posizione.
- `audioplayers` per il suono del metronomo, generato in memoria e riprodotto in loop.
- `shared_preferences`, `path_provider` e `file_picker` per persistenza e importazione locale.

### Nota di build Android

`url_launcher_android` (dipendenza indiretta di `pdfrx`) è fissata alla **6.3.20** tramite `dependency_overrides`. Le versioni 6.3.31 e successive richiedono il Kotlin integrato di AGP 9, non attivo in questa configurazione Flutter; la 6.3.20 usa lo script Gradle classico e compila correttamente.
