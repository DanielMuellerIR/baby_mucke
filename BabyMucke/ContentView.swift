import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var stationStore: StationStore
    @EnvironmentObject private var radioPlayer: RadioPlayer
    @State private var didSelectInitialStation = false
    @State private var selectedHistoryID: SongEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            // Wie in der Mac-App: Senderliste und Verlauf stehen oben buendig,
            // die Playerleiste sitzt als durchgehende Leiste am unteren Rand.
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    StationListView()
                        .frame(width: stationColumnWidth(for: proxy.size.width))

                    Rectangle()
                        .fill(BlackMidiStyle.line)
                        .frame(width: 1)

                    HistoryView(selectedEntryID: $selectedHistoryID)
                        .frame(maxWidth: .infinity)
                }
            }

            PlayerBar()
        }
        .background {
            BlackMidiBackdrop()
                .ignoresSafeArea()
        }
        .tint(BlackMidiStyle.cyan)
        .onAppear(perform: selectInitialStationIfNeeded)
        .onChange(of: stationStore.stations) { _, _ in
            selectInitialStationIfNeeded()
        }
    }

    private func stationColumnWidth(for totalWidth: CGFloat) -> CGFloat {
        // iPhone-Hochformat bleibt der Leitfall: links knapp genug fuer Sender,
        // rechts genug Luft fuer Verlauf und Aktionsleiste.
        min(max(totalWidth * 0.38, 128), 214)
    }

    private func selectInitialStationIfNeeded() {
        guard !didSelectInitialStation else { return }
        let station = stationStore.lastPlayed
            ?? stationStore.favorite
            ?? stationStore.stationsForPlaybackList.first
        guard let station else { return }
        didSelectInitialStation = true
        radioPlayer.select(station)
    }
}
