# Baby, Mucke! — Projektplan

Stand: 2026-06-17

## Aktueller Status

- Git-Repo unter `~/git/baby_mucke` ist initialisiert, Branch `main`.
- Aktuelle App-Version: **0.1.10**.
- iOS-Projekt `BabyMucke.xcodeproj` existiert und baut fuer den iOS-Simulator.
- Build-Befehl: `./scripts/build-simulator.sh`.
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
- Design: festes **Black MIDI**-Design, keine Theme-Auswahl.
- Nicht im MVP: Aufnahmefunktion, Visualizer, Theme-System, Mac-Menueleistenmodus.
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

Empfehlung fuer die naechste Session:

- AVPlayer auf einem echten iPhone mit wichtigen Sendern aus der Mac-App testen.
- Wenn relevante Sender wegen Codec/Container scheitern: frueh auf MobileVLCKit wechseln.

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
- `BlackMidiStyle.swift` — feste Palette, Fonts, Komponenten.
- `ContentView.swift`, `StationListView.swift`, `HistoryView.swift`, `PlayerBar.swift`.

## Umsetzung in der naechsten Session

1. Echten Device-Test mit MP3/AAC-Stream und mindestens einem problematischen Mac-App-Stream machen.
2. Verhalten von Background-Audio, Lock-Screen und Remote-Controls auf dem Geraet pruefen.
3. Sender-Edit-/Import-/Export-Flows auf einem Geraet manuell durchklicken.
4. Falls AVPlayer wichtige Sender nicht abspielt: MobileVLCKit-Variante planen und frueh einbauen.

## Bewusst spaeter

- Visualizer.
- Aufnahme und Song-Export.
- iCloud-Sync zwischen Mac und iPhone.
- Radio-browser-Suche, falls der MVP stabil ist.
- App-Store-Metadaten, Icon-Feinschliff, TestFlight.
