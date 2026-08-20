# Baby, Mucke! — Projektplan

Stand: 2026-08-20

## Typ & Zweck
- **Typ:** GUI-App
- **Zweck:** Internetradio-App fürs iPhone (Sender, Playback, Now-Playing, Verlauf) — iOS-Ableger von „Mucke, Baby!".
- **Plattform:** iOS

## Aktueller Status

- Git-Repo unter `~/git/baby_mucke` ist initialisiert, Branch `main`.
- Aktuelle App-Version: **0.1.17**.
- iOS-Projekt `BabyMucke.xcodeproj` existiert und baut fuer den iOS-Simulator.
- Build-Befehl: `./scripts/build-simulator.sh`.
- Unit-Test-Target `BabyMuckeTests` (54 Tests: reine Logik plus Verlauf-Pruning,
  Persistenz-Roundtrip und Sender-Store ueber injizierbaren Ordner) vorhanden;
  Lauf: `./scripts/run-tests.sh` (waehlt Simulator automatisch).
- Audio-Engine fuer den MVP: **AVPlayer zuerst**.
- Portiert/angelegt: Sender-Modelle, Sender-Store, Playlist-Aufloesung, ICY-Metadatenleser,
  Verlauf, Apple-Music-/Spotify-Suchlinks, Black-MIDI-SwiftUI-Oberflaeche, Background-Audio-
  Plist-Eintrag und Remote-Command-Grundlage.
- UI-Stand 2026-06-17: kompakte Zwei-Spalten-Ansicht mit Senderliste links, Verlauf rechts,
  Playerleiste oben, gemeinsamem Verlauf-Aktionsbereich und Sender-Edit-/Import-/Export-Grundlage.
- Bestehende Installationen mit der alten unberuehrten 4-Sender-Demoliste werden einmalig auf
  `seed-stations.json` migriert; bearbeitete Nutzerlisten bleiben erhalten.
- Geprueft: `./scripts/build-simulator.sh` sowie Simulator-Screenshots auf iPhone 17 und iPhone 17e.

## Projektfakten

- Anzeigename: **Baby, Mucke!**
- Kurzname / Ordner: `baby_mucke`
- Plattform: iPhone, Hochformat zuerst.
- Ursprung: iPhone-Ableger von `../mucke_baby` ("Mucke, Baby!").
- Design: feste **Black MIDI**-Designsprache, als helle und dunkle Darstellung.
- Nicht im MVP: Aufnahmefunktion, Visualizer, weitere Themes, Mac-Menueleistenmodus.
- Kern im MVP: Senderliste, Playback, Now-Playing, Verlauf, Apple-Music- und Spotify-Buttons.

## Grundannahmen

- Die Antwort auf offene Fachfragen ist standardmaessig: **wie in der Mac-App**.
- UI-Sprache: Deutsch (Quellsprache) und Englisch, lokalisiert ueber `BabyMucke/Localizable.xcstrings`; folgt der Systemsprache.
- Senderdaten bleiben kompatibel zur Mac-App (`Station`/`SeedStation`, JSON).
- `BabyMucke/Resources/seed-stations.json` ist die gebuendelte Default-Senderliste und wird
  absichtlich mit dem Projekt verteilt.
- ICY-Metadaten werden wie in der Mac-App separat gelesen, weil Player-Frameworks Live-Stream-Titel
  nicht verlaesslich als Now-Playing-Metadaten liefern.
- Verlauf ist lokal auf dem iPhone; kein Sync im MVP.
- App-Lautstaerkeregler wird im iPhone-MVP weggelassen. iOS-Nutzer verwenden Systemlautstaerke.

## Wichtigste Entscheidung vor Umsetzung

### Audio-Engine

Fuer den MVP ist **AVPlayer zuerst** umgesetzt:

1. **AVPlayer zuerst**: kleinster iOS-typischer MVP, gute Integration mit Background-Audio,
   Lock-Screen/Remote-Controls und App-Store-Review. Nachteil: moegliche Codec-Luecken gegenueber
   der Mac-App, besonders bei Ogg/Opus/Vorbis-Streams.
2. **MobileVLCKit/VLCKit fuer iOS zuerst**: beste Codec-Paritaet zur Mac-App. Nachteil:
   groesseres Dependency-/Lizenz-/Build-Thema und potenziell mehr Aufwand fuer Background-Audio
   und Systemintegration.

Stand nach On-Device-Test (2026-07-08, echtes iPhone):

- AVPlayer spielt auf dem Geraet auch **Ogg/Opus- und Ogg/Vorbis-Streams** ab
  (Hirschmilch Progressive `.opus`, RainWave Chiptune Ogg/Opus, Kohina Ogg/Vorbis
  laufen einwandfrei). Die frueher vermutete Codec-Luecke besteht fuer die reine
  Wiedergabe also NICHT — MobileVLCKit ist dafuer aktuell nicht noetig.
- ABER: Diese Ogg-Icecast-Streams liefern keinen Live-Titel -> kein Verlaufs-
  Eintrag (Details siehe "## Fallen / Agent-Hinweise").

## Offene Fragen an Daniel

- Mindest-iOS-Version: Empfehlung **iOS 17+** fuer breitere Nutzbarkeit; **iOS 18+** waere okay,
  falls moderne Codec-Unterstuetzung wichtiger ist als Reichweite.
- Distribution: nur lokal/TestFlight oder mittelfristig App Store?
- Autoplay: wie Mac-App beim Start den zuletzt gespielten Sender/Favoriten starten, oder auf iPhone
  lieber erst nach Nutzeraktion?
- Verlauf-Retention: exakt wie Mac-App uebernehmen oder auf iPhone kuerzer halten?
- Apple-Music/Spotify-Buttons: nur Websuche per URL oder zusaetzlich App-URL-Schemes bevorzugen?

## UI-Stand / UI-Plan

- Kein sichtbarer App-Name in der iOS-App.
- Einstellungen bieten Hell, Dunkel und Automatisch (folgt der iOS-Systemdarstellung).
- Umgesetzt ist eine kompakte Black-MIDI-Oberflaeche, staerker an der Mac-App orientiert:
  - schmalere Senderliste links, breiterer Verlauf rechts, beide gleichzeitig sichtbar.
  - Sendernamen klein/normalgewichtig, keine grossen fetten Zeilen.
  - Keine Play-Buttons pro Sender.
  - Keine dekorativen Cyan-Punkte und kein `>>>` vor Sendernamen.
  - Aktiver Sender wird ueber Zeilenhighlight markiert und zeigt darunter den aktuellen Song in Grau
    wie in der Mac-App.
  - Sender-URLs werden in der normalen Liste nicht angezeigt; nur im Edit-Modus.
  - Favoriten-Sternchen in der iOS-UI entfernen. Das Feld bleibt nur fuer JSON-Kompatibilitaet erhalten.
  - Zuletzt gehoerter Sender soll beim Programmstart automatisch ausgewaehlt/angezeigt werden,
    aber nicht ohne Nutzeraktion starten.
- Verlauf:
  - Optik/Inhalt an der Mac-App orientieren: Zeitspanne in Cyan, Titel darunter, Sendername in Grau.
  - Apple-Music- und Spotify-Aktionen nicht pro Verlaufseintrag wiederholen.
  - Ein Verlaufseintrag wird markiert; eine gemeinsame Aktionsleiste zeigt Apple Music, Spotify
    und Loeschen.
  - Buttons sollen visuell wie in der Mac-App wirken (Icon + kurze Beschriftung, dezenter Toolbar-Stil).
  - Native Swipe-Actions koennen spaeter zusaetzlich kommen, verbrauchen aber nicht dauerhaft Platz.
- Senderdaten:
  - Standardmaessig die gebuendelte Senderliste aus `seed-stations.json` laden.
  - Import, Export und Bearbeiten der Senderliste sind als MVP-Grundlage umgesetzt.
- Kein Visualizer im MVP. Wenn spaeter gewuenscht: kleiner Spektrumstreifen nur als Kuer, nicht als
  Layout-Traeger.
- iPad/quer spaeter optional als Zwei-Spalten-Layout; iPhone-Hochformat ist zuerst massgeblich.

## Technische Architektur

- `BabyMuckeApp.swift` — SwiftUI-App-Einstieg, globale Stores.
- `Models.swift` — `Station`, `SeedStation`, `AppInfo`.
- `StationStore.swift` — Senderliste laden/speichern, Seed-Import, Favorit/Sortierung,
  Bearbeiten, Loeschen und JSON-Import.
- `RadioPlayer.swift` — iOS-Player-Fassade (`AVPlayer` oder VLCKit-Adapter), Status, Laufzeit.
- `ICYMetadataReader.swift` — aus Mac-App portieren, ohne Aufnahme-Callbacks.
- `PlaylistResolver.swift` — aus Mac-App portieren.
- `SongHistory.swift` — aus Mac-App portieren, ohne Aufnahme-/Export-Bezug.
- `MusicLinks.swift` — Apple Music / Spotify Such-URLs.
- `BlackMidiStyle.swift` — adaptive Hell-/Dunkel-Palette, Fonts, Komponenten.
- `ContentView.swift`, `StationListView.swift`, `HistoryView.swift`, `PlayerBar.swift`.

## Umsetzung in der naechsten Session

1. Echten Device-Test mit MP3/AAC-Stream und mindestens einem problematischen Mac-App-Stream machen.
2. Verhalten von Background-Audio, Lock-Screen und Remote-Controls auf dem Geraet pruefen.
3. Sender-Edit-/Import-/Export-Flows auf einem Geraet manuell durchklicken.
4. MobileVLCKit ist fuer die Wiedergabe NICHT noetig (AVPlayer spielt on-device
   auch Ogg/Opus/Vorbis, verifiziert 2026-07-08). Nur falls ein Sender WIRKLICH
   nicht spielt (nicht nur ohne Titel/Verlauf), erneut abwaegen.
5. Spotify-Such-Button prueft: Landet auf der Spotify-Suchseite, aber das Suchfeld
   bleibt leer (kein Treffer). Apple-Music-Button funktioniert. `MusicLinks.spotifySearchURL`
   baut das dokumentierte Format `https://open.spotify.com/search/<query>` (mit %20) — der
   URL-Bau ist also plausibel korrekt. Verdacht: Spotifys Web-Player traegt den Suchbegriff
   nur eingeloggt / in der installierten App durch; ausgeloggt zeigt er die Preview-Seite
   ohne Query. MUSS mit echtem Spotify-Account bzw. installierter Spotify-App verifiziert
   werden. Falls es auch dann leer bleibt: `spotify:search:<query>`-URI (App) bzw. eine
   Query-Param-Variante testen. (Stand 2026-07-08, on-device beobachtet.)

## Fallen / Agent-Hinweise

- **Ogg/Opus/Vorbis-Streams: Wiedergabe ja, Verlauf nein.** AVPlayer spielt diese
  Streams on-device ab (verifiziert 2026-07-08: Hirschmilch Progressive, RainWave
  Chiptune, Kohina), sie erscheinen aber NIE im Song-Verlauf. Grund: Der
  `ICYMetadataReader` liest die Shoutcast/Icecast-ICY-Metadaten ueber das
  `icy-metaint`-Interleaving — das bieten praktisch nur MP3/AAC-Mounts. Ein
  Ogg-Mount sendet keinen `icy-metaint`-Header, worauf der Reader die
  Metadaten-Verbindung bewusst abbricht (`didReceive response` -> `.cancel`-Zweig).
  Den Live-Titel tragen Ogg-Streams stattdessen in-band in Ogg-Comment-Paketen
  (Vorbis/Opus comment), die der Reader nicht dekodiert. Kein Bug, sondern
  Container-Grenze. Ein Titel-Feed fuer Ogg wuerde einen eigenen Ogg-Page-/
  Comment-Parser brauchen (bewusst spaeter, siehe unten).

## Bewusst spaeter

- Ogg-/Opus-Metadaten (Ogg-Comment) fuer den Verlauf lesen — siehe "Fallen".
- Visualizer.
- Aufnahme und Song-Export.
- iCloud-Sync zwischen Mac und iPhone.
- Radio-browser-Suche, falls der MVP stabil ist.
- App-Store-Metadaten, Icon-Feinschliff, TestFlight.

## Verzeichnisstruktur

<!-- directory-structure: generated -->
- [AGENTS.md](AGENTS.md) — Projektprofil, Arbeitsregeln und dieses Datei-Verzeichnis.
- [README.de.md](README.de.md) — Projekt-Einstieg und Nutzerdokumentation.
- [README.md](README.md) — Projekt-Einstieg und Nutzerdokumentation.
- `BabyMucke/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
- `BabyMucke.xcodeproj/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
- `BabyMuckeTests/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
- `icons/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
- `screenshots/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
- `scripts/` — Projektbestandteil; Details stehen im Code bzw. in der verlinkten Dokumentation.
<!-- /directory-structure -->
