import AVFoundation
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
    private var resolveTask: Task<Void, Never>?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var remoteCommandsConfigured = false

    init() {
        icy.onTitle = { [weak self] title in
            Task { @MainActor in self?.setNowPlaying(title) }
        }
        configureRemoteCommands()
        history.pruneOnLaunchOrQuit()
    }

    func select(_ station: Station) {
        if currentStation?.id == station.id {
            if currentStation != station {
                currentStation = station
                refreshNowPlayingCenter()
            }
            return
        }

        if isPlaying || isLoading {
            play(station)
            return
        }

        currentStation = station
        nowPlayingTitle = ""
        playStartedAt = nil
        setStatus("Bereit")
        refreshNowPlayingCenter()
    }

    func refreshCurrentStation(_ station: Station) {
        guard currentStation?.id == station.id else { return }
        currentStation = station
        refreshNowPlayingCenter()
    }

    func play(_ station: Station) {
        #if DEBUG
        PlayerDiagnostics.logMemory("play '\(station.name)'")
        #endif
        history.closeCurrent()
        resetPlaybackObjects()

        currentStation = station
        nowPlayingTitle = ""
        setStatus("Lade ...")
        isLoading = true
        isPlaying = false
        playStartedAt = nil
        refreshNowPlayingCenter()

        resolveTask = Task { [weak self] in
            let resolved = await PlaylistResolver.resolve(station.url)
            guard let self else { return }
            if Task.isCancelled { return }
            await MainActor.run {
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
        #if DEBUG
        PlayerDiagnostics.logMemory("stop")
        #endif
        history.closeCurrent()
        resetPlaybackObjects()
        isPlaying = false
        isLoading = false
        playStartedAt = nil
        setStatus("Gestoppt")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Audio-Session freigeben, damit andere Apps (Musik, Podcasts) nach dem
        // Stoppen wieder weiterlaufen koennen. Best-effort wie der Rest hier.
        // Bewusst nur in stop(), nicht in resetPlaybackObjects() — letzteres laeuft
        // auch beim Senderwechsel, wo direkt wieder aktiviert wird.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggle(_ station: Station) {
        if (isPlaying || isLoading), currentStation?.id == station.id {
            stop()
        } else {
            play(station)
        }
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
            isPlaying = false
            isLoading = false
            playStartedAt = nil
            setStatus("Fehler: Stream nicht abspielbar", isError: true)
            history.closeCurrent()
            icy.stop()
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
                isPlaying = false
                isLoading = false
                setStatus("Pausiert")
                history.closeCurrent()
            }
        @unknown default:
            break
        }
        refreshNowPlayingCenter()
    }

    private func markPlaybackStarted() {
        guard player?.timeControlStatus == .playing else { return }
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

    private func resetPlaybackObjects() {
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
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
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
