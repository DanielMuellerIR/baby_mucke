import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var stationStore: StationStore
    @EnvironmentObject private var radioPlayer: RadioPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button(action: primaryAction) {
                Image(systemName: radioPlayer.isPlaying || radioPlayer.isLoading ? "stop.fill" : "play.fill")
                    .accessibilityLabel(radioPlayer.isPlaying || radioPlayer.isLoading ? Text("Wiedergabe stoppen") : Text("Wiedergabe starten"))
            }
            .buttonStyle(PlaybackButtonStyle(
                tint: radioPlayer.isPlaying ? BlackMidiStyle.green : BlackMidiStyle.cyan,
                active: radioPlayer.isPlaying || radioPlayer.isLoading
            ))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Group {
                        // Sendername woertlich; nur der Platzhalter wird lokalisiert.
                        if let name = radioPlayer.currentStation?.name {
                            Text(verbatim: name)
                        } else {
                            Text("Sender auswählen")
                        }
                    }
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(BlackMidiStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    if radioPlayer.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BlackMidiStyle.cyan)
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BlackMidiStyle.amber)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                HStack(spacing: 6) {
                    MIDIChip(text: radioPlayer.statusText, color: statusColor)
                    if let started = radioPlayer.playStartedAt {
                        MIDIChip(text: started.formatted(.dateTime.hour().minute()), color: BlackMidiStyle.pink)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Durchgehende Bodenleiste wie in der Mac-App: fast deckende Flaeche
        // (Cyber-Textur scheint dezent durch) mit feiner Trennlinie nach oben.
        .background(BlackMidiStyle.surface.opacity(0.8))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BlackMidiStyle.line)
                .frame(height: 1)
        }
    }

    private var subtitle: String {
        if !radioPlayer.nowPlayingTitle.isEmpty { return radioPlayer.nowPlayingTitle }
        return ""
    }

    private var statusColor: Color {
        if radioPlayer.isError { return BlackMidiStyle.red }
        if radioPlayer.isPlaying { return BlackMidiStyle.green }
        if radioPlayer.isLoading { return BlackMidiStyle.cyan }
        return BlackMidiStyle.secondaryText
    }

    private func primaryAction() {
        if radioPlayer.isPlaying || radioPlayer.isLoading {
            radioPlayer.stop()
            return
        }
        let station = radioPlayer.currentStation ?? stationStore.favorite ?? stationStore.lastPlayed
            ?? stationStore.stationsForPlaybackList.first
        guard let station else { return }
        stationStore.markPlayed(station)
        radioPlayer.play(station)
    }
}
