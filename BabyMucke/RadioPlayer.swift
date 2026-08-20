import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os

// iOS-Player-Fassade. Sie kapselt AVPlayer, Playlist-Aufloesung,
// Audio-Session, Lock-Screen-Infos, Remote-Controls und den separaten
// ICY-Metadatenleser hinter einer kleinen SwiftUI-tauglichen ObservableObject-API.
@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = String(localized: "Bereit")
    @Published private(set) var isError = false
    @Published private(set) var nowPlayingTitle = ""
    @Published private(set) var playStartedAt: Date?

    let history = SongHistory()

    private var player: AVPlayer?
    private let icy = ICYMetadataReader()
    // Monoton wachsender Zaehler: wird bei jedem Abbau/Start erhoeht.
    // setNowPlaying verwirft Titel, deren Generation nicht mehr aktuell ist,
    // damit verspätete icy-Callbacks einer alten Session keinen Phantom-Eintrag
    // in den Verlauf schreiben oder den Titel dem falschen Sender zuordnen.
    private var playGeneration: Int = 0
    private var resolveTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var historyCancellable: AnyCancellable?

    init() {
        configureRemoteCommands()
        historyCancellable = history.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func select(_ station: Station) {
        currentStation = station
        nowPlayingTitle = ""
        playStartedAt = nil
        setStatus("Bereit")
        refreshNowPlayingCenter()
    }

    func refreshCurrentStation(_ station: Station) {
        guard let current = currentStation, current.id == station.id else { return }

        // Wird der gerade laufende Sender im Edit-Sheet ueber den "Aktiv"-Toggle
        // deaktiviert, darf er nicht weiterspielen — sonst zeigt die Liste ihn als
        // deaktiviert, waehrend der Player ihn noch abspielt. Analog zum
        // enabled-Guard in play() hier stoppen und Status setzen.
        if !station.enabled && (isPlaying || isLoading) {
            currentStation = station
            stop()
            setStatus("Sender deaktiviert", isError: true)
            return
        }

        // Wurde die Stream-URL des gerade laufenden/ladenden Senders geaendert
        // (z. B. im Edit-Sheet korrigiert), spielt das alte AVPlayer-Item sonst
        // weiter die alte URL, waehrend die Liste bereits die neue zeigt. Deshalb
        // den Sender mit der neuen URL neu laden. play() setzt currentStation selbst.
        if current.url != station.url && (isPlaying || isLoading) {
            play(station)
            return
        }

        currentStation = station
        refreshNowPlayingCenter()
    }

    func play(_ station: Station) {
        // Deaktivierte Sender nicht abspielen — kann z. B. auftreten, wenn der
        // Lock-Screen-Steuerbefehl (Remote Control) den zuletzt gehoerten Sender
        // erneut starten will, der inzwischen deaktiviert wurde.
        guard station.enabled else {
            setStatus("Sender deaktiviert", isError: true)
            return
        }
        prepareForPlay(station)
        resolveAndStart(station)
    }

    // Synchroner Teil von play(): den alten Player abbauen und den UI-Zustand auf
    // "laedt gerade" setzen, bevor die (asynchrone) URL-Aufloesung anlaeuft.
    private func prepareForPlay(_ station: Station) {
        #if DEBUG
        PlayerDiagnostics.logMemory("play '\(station.name)'")
        #endif
        teardownPlayback(closeHistory: true, clearSelection: false)

        currentStation = station
        nowPlayingTitle = ""
        setStatus("Lade ...")
        isLoading = true
        refreshNowPlayingCenter()
    }

    // Asynchroner Teil von play(): Playlist-/Redirect-URL aufloesen und dann den
    // eigentlichen AVPlayer starten. Laeuft als abbrechbarer Task, damit ein
    // schnelles stop()/play() die alte Aufloesung verwerfen kann.
    private func resolveAndStart(_ station: Station) {
        // codereview-ok: kein separates Steckenbleiben — steigt der Task nicht in MainActor.run ein, wird start()/setStatus("Puffert") nie erreicht; die enge Race ist mit dem Cancel-Check im MainActor.run-Block erledigt (2026-07-01)
        resolveTask = Task { [weak self] in
            let resolved = await PlaylistResolver.resolve(station.url)
            guard let self else { return }
            if Task.isCancelled { return }
            await MainActor.run {
                // Erneuter Abbruch-Check IM MainActor-Block: Zwischen dem synchronen
                // Setup in prepareForPlay und diesem Body kann ein stop()/play()
                // dazwischenfunken, das via teardownPlayback() diesen resolveTask
                // cancelt. Ohne den erneuten Check wuerde start() trotzdem einen neuen
                // AVPlayer+ICY aufbauen und currentStation/isLoading/isPlaying ueberschreiben.
                if Task.isCancelled { return }
                guard let url = resolved else {
                    self.isLoading = false
                    self.setStatus("Ungültige URL", isError: true)
                    self.refreshNowPlayingCenter()
                    return
                }
                self.start(url: url)
            }
        }
    }

    func stop() {
        // codereview-ok: currentStation bleibt nach stop() bewusst gesetzt, damit PlayerBar/Remote-Commands den Sender fortsetzen koennen; nil setzen wuerde die Resume-Logik brechen (2026-07-01)
        #if DEBUG
        PlayerDiagnostics.logMemory("stop")
        #endif
        teardownPlayback(closeHistory: true, clearSelection: false)
        setStatus("Gestoppt")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Audio-Session freigeben, damit andere Apps (Musik, Podcasts) nach dem
        // Stoppen wieder weiterlaufen koennen. Best-effort wie der Rest hier.
        // Bewusst nur in stop(), nicht in teardownPlayback() — letzteres laeuft
        // auch beim Senderwechsel, wo direkt wieder aktiviert wird.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Listenimport/-loeschung braucht einen staerkeren Vertrag als der normale
    // Stop-Button: Ein nicht mehr vorhandener oder deaktivierter Sender darf weder
    // angezeigt noch ueber PlayerBar/Remote Controls erneut gestartet werden.
    func stopAndClearSelection() {
        #if DEBUG
        PlayerDiagnostics.logMemory("stopAndClearSelection")
        #endif
        teardownPlayback(closeHistory: true, clearSelection: true)
        setStatus("Bereit")
        refreshNowPlayingCenter()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start(url: URL) {
        guard activateAudioSession() else { return }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.handleItemStatus(item.status, error: item.error, observedItem: item) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in self?.handleTimeControlStatus(player.timeControlStatus, observedPlayer: player) }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 2),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markPlaybackStarted() }
        }

        player.play()
        let capturedGeneration = playGeneration
        // codereview-ok: onTitle wird NICHT in ICYMetadataReader.stop() genullt — start() ruft stop() als erste Zeile, das wuerde den gerade gesetzten Callback sofort wieder loeschen; verspaetete Callbacks fangen wir stattdessen ueber capturedGeneration ab (2026-07-08)
        icy.onTitle = { [weak self] title in
            // Inneres [weak self] weggelassen: self ist hier schon das (schwache)
            // Optional der aeusseren Closure, ein erneutes weak-Capture waere redundant.
            Task { @MainActor in
                guard let self, self.playGeneration == capturedGeneration else { return }
                self.setNowPlaying(title)
            }
        }
        icy.start(url: url)
        setStatus("Puffert ...")
        isLoading = true
        refreshNowPlayingCenter()
    }

    private func activateAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            return true
        } catch {
            isLoading = false
            isPlaying = false
            setStatus("Fehler: Audio-Session nicht verfügbar", isError: true)
            return false
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?, observedItem: AVPlayerItem) {
        // Verspaetete KVO-Callbacks eines bereits ersetzten Items ignorieren, damit
        // ein alter Fehler nicht die frisch gestartete Wiedergabe stoert.
        guard observedItem === player?.currentItem else { return }
        switch status {
        case .readyToPlay:
            if !isPlaying { setStatus("Puffert ...") }
        case .failed:
            teardownPlayback(closeHistory: true, clearSelection: false)
            setStatus("Fehler: Stream nicht abspielbar", isError: true)
        case .unknown:
            break
        @unknown default:
            break
        }
        refreshNowPlayingCenter()
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus, observedPlayer: AVPlayer) {
        // Nur Callbacks des aktuellen Players auswerten (siehe handleItemStatus).
        guard observedPlayer === player, currentStation != nil else { return }
        switch status {
        case .playing:
            markPlaybackStarted()
        case .waitingToPlayAtSpecifiedRate:
            if !isPlaying {
                isLoading = true
                setStatus("Puffert ...")
            }
        case .paused:
            if isPlaying {
                teardownPlayback(closeHistory: true, clearSelection: false)
                setStatus("Pausiert")
            }
        @unknown default:
            break
        }
        refreshNowPlayingCenter()
    }

    private func markPlaybackStarted() {
        // codereview-ok: teardownPlayback() setzt player=nil; ein alter/queued Callback faellt durch diesen Guard, kein Phantom-Write moeglich (2026-07-01)
        guard player?.timeControlStatus == .playing else { return }
        // Der periodische Time-Observer diente nur dazu, den Start der Wiedergabe
        // zuverlaessig zu erkennen (als Ergaenzung zur timeControlStatus-KVO).
        // Sobald sie laeuft, ist er ueberfluessig und wuerde sonst jede halbe
        // Sekunde setStatus()/refreshNowPlayingCenter() umsonst neu aufrufen.
        // Deshalb hier einmalig entfernen (teardownPlayback() nullt den Token
        // beim Senderwechsel, ein Doppel-Remove kann also nicht passieren).
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if playStartedAt == nil { playStartedAt = Date() }
        isPlaying = true
        isLoading = false
        setStatus("Wiedergabe")
        refreshNowPlayingCenter()
    }

    // Setzt den lokalisierten Statustext und merkt sich, ob es ein Fehlerzustand
    // ist (statt den Text per Praefix zu pruefen — das bricht bei Uebersetzung).
    private func setStatus(_ key: String.LocalizationValue, isError: Bool = false) {
        statusText = String(localized: key)
        self.isError = isError
    }

    private func setNowPlaying(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != nowPlayingTitle else { return }
        nowPlayingTitle = t
        if let station = currentStation {
            history.note(station: station.name, raw: t)
        }
        refreshNowPlayingCenter()
    }

    private func teardownPlayback(closeHistory: Bool = true, clearSelection: Bool = false) {
        playGeneration &+= 1
        resolveTask?.cancel()
        resolveTask = nil
        icy.stop()
        itemStatusObservation = nil
        timeControlObservation = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        if closeHistory {
            history.closeCurrent()
        }
        if clearSelection {
            currentStation = nil
            nowPlayingTitle = ""
        }
        isPlaying = false
        isLoading = false
        playStartedAt = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let station = self.currentStation else { return }
                self.play(station)
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let station = self.currentStation else { return }
                self.isPlaying ? self.stop() : self.play(station)
            }
            return .success
        }
    }

    private func refreshNowPlayingCenter() {
        guard let station = currentStation else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: "Baby, Mucke!",
            MPMediaItemPropertyArtist: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        if nowPlayingTitle.isEmpty {
            info[MPMediaItemPropertyTitle] = station.name
        } else {
            let split = SongEntry.split(nowPlayingTitle)
            info[MPMediaItemPropertyTitle] = split.title ?? nowPlayingTitle
            info[MPMediaItemPropertyArtist] = split.artist ?? station.name
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// Kleine Player-Grenze fuer die deterministisch testbare Synchronisation nach
// Senderlisten-Aenderungen. Der echte RadioPlayer und Tests mit einem Fake teilen
// denselben Vertrag; dabei wird kein Stream geoeffnet.
@MainActor
protocol StationListPlayback: AnyObject {
    var currentStation: Station? { get }
    func select(_ station: Station)
    func refreshCurrentStation(_ station: Station)
    func stopAndClearSelection()
}

extension RadioPlayer: StationListPlayback {}

@MainActor
enum StationListSynchronizer {
    static func synchronize<Player: StationListPlayback>(store: StationStore, player: Player) {
        guard let current = player.currentStation else {
            if let fallback = store.defaultStation {
                player.select(fallback)
            }
            return
        }

        if let retained = store.stations.first(where: { $0.id == current.id && $0.enabled }) {
            // Auch Name/URL aus einem Import uebernehmen. RadioPlayer startet bei
            // geaenderter URL einen laufenden Sender kontrolliert neu.
            player.refreshCurrentStation(retained)
            return
        }

        player.stopAndClearSelection()
        if let fallback = store.defaultStation {
            player.select(fallback)
        }
    }
}

#if DEBUG
// Leichte Debug-Diagnostik: protokolliert den Speicherbedarf (phys_footprint)
// bei jedem Senderwechsel und beim Stoppen. Steigt der Wert ueber viele Wechsel
// hinweg monoton an, ist das ein Leak-Hinweis. Sichtbar in der Xcode-Konsole
// bzw. Console.app (Subsystem de.babymucke.BabyMucke, Kategorie "perf").
// Nur im DEBUG-Build vorhanden -> kein Einfluss auf Release-CPU/-Speicher.
enum PlayerDiagnostics {
    static let log = Logger(subsystem: "de.babymucke.BabyMucke", category: "perf")

    static func logMemory(_ context: String) {
        guard let mb = footprintMB() else { return }
        log.notice("\(context, privacy: .public) — Speicher \(mb, format: .fixed(precision: 1)) MB")
    }

    private static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1024 / 1024
    }
}
#endif
