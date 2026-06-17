import SwiftUI

struct HistoryView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var radioPlayer: RadioPlayer
    @Binding var selectedEntryID: SongEntry.ID?

    // Merkt sich den zuletzt gesehenen juengsten Eintrag, um einen NEU
    // angehaengten Eintrag von Loeschungen/Selektionswechseln zu unterscheiden.
    @State private var lastNewestID: SongEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if entries.isEmpty {
                            Text("Noch kein Verlauf")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BlackMidiStyle.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            ForEach(entries) { entry in
                                HistoryRow(entry: entry, isSelected: selectedEntryID == entry.id) {
                                    selectedEntryID = entry.id
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .onAppear { syncToNewest(using: proxy, animated: false) }
                .onChange(of: radioPlayer.history.entries) { _, _ in
                    syncToNewest(using: proxy, animated: true)
                }
            }

            actionBar
        }
        .background(BlackMidiStyle.panelFill)
    }

    // Eintraege chronologisch: aeltester oben, neuester unten (wie in der Mac-App).
    private var entries: [SongEntry] {
        radioPlayer.history.entries
    }

    private var selectedEntry: SongEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("VERLAUF")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(BlackMidiStyle.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Verlauf-Loesch-Menue, oben rechts wie der Bearbeiten-Button der
            // Senderliste. Loescht nur Verlaufs-Eintraege (per Zeitstempel).
            Menu {
                Button("Älter als 1 Tag löschen") { removeOlderThan(.day, 1) }
                Button("Älter als 3 Tage löschen") { removeOlderThan(.day, 3) }
                Button("Älter als 1 Woche löschen") { removeOlderThan(.day, 7) }
                Button("Älter als 1 Monat löschen") { removeOlderThan(.month, 1) }
                Divider()
                Button("Gesamten Verlauf löschen", role: .destructive) {
                    radioPlayer.history.clear()
                    selectedEntryID = nil
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Verlauf-Optionen")
            }
            .menuOrder(.fixed)
            .buttonStyle(CompactIconButtonStyle(tint: BlackMidiStyle.text))
            .disabled(radioPlayer.history.entries.isEmpty)
            .help("Verlauf-Optionen")
        }
        // Gleiche feste Zeilenhoehe wie der SENDER-Header (Button-Hoehe),
        // damit beide Header und ihre Trennlinien auf einer Hoehe liegen.
        .frame(height: 30)
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BlackMidiStyle.line)
                .frame(height: 1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                if let selectedEntry {
                    openURL(MusicLinks.appleMusicSearchURL(for: selectedEntry))
                }
            } label: {
                Label("\u{F8FF} Music", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HistoryActionButtonStyle(tint: BlackMidiStyle.text))
            .disabled(selectedEntry == nil)
            .help("Apple Music")

            Button {
                if let selectedEntry {
                    openURL(MusicLinks.spotifySearchURL(for: selectedEntry))
                }
            } label: {
                Label("Spotify", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HistoryActionButtonStyle(tint: BlackMidiStyle.text))
            .disabled(selectedEntry == nil)
            .help("Spotify")

            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Label("Löschen", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HistoryActionButtonStyle(tint: BlackMidiStyle.text))
            .disabled(selectedEntry == nil)
            .help("Eintrag löschen")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BlackMidiStyle.line)
                .frame(height: 1)
        }
    }

    private func removeOlderThan(_ component: Calendar.Component, _ value: Int) {
        let cutoff = Calendar.current.date(byAdding: component, value: -value, to: Date()) ?? Date()
        radioPlayer.history.remove(olderThan: cutoff)
        ensureSelection()
    }

    // Bei jeder Verlaufsaenderung: ist ein neuer juengster Eintrag dazugekommen,
    // wird er markiert und ans untere Ende gescrollt. Sonst nur die Auswahl
    // gueltig halten (z.B. nach einer Loeschung).
    private func syncToNewest(using proxy: ScrollViewProxy, animated: Bool) {
        let newestID = entries.last?.id
        guard newestID != lastNewestID else {
            ensureSelection()
            return
        }
        lastNewestID = newestID
        guard let newestID else {
            selectedEntryID = nil
            return
        }
        selectedEntryID = newestID
        if animated {
            withAnimation { proxy.scrollTo(newestID, anchor: .bottom) }
        } else {
            proxy.scrollTo(newestID, anchor: .bottom)
        }
    }

    private func ensureSelection() {
        let ids = Set(entries.map(\.id))
        if let selectedEntryID, ids.contains(selectedEntryID) { return }
        // Fallback: den neuesten (untersten) Eintrag markieren.
        selectedEntryID = entries.last?.id
    }

    private func deleteSelected() {
        guard let selectedEntry else { return }
        radioPlayer.history.delete(selectedEntry)
        selectedEntryID = nil
        ensureSelection()
    }
}

private struct HistoryRow: View {
    var entry: SongEntry
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeSpan)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(BlackMidiStyle.cyan)
                    .lineLimit(1)

                Text(entry.raw)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BlackMidiStyle.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.station)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlackMidiStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? BlackMidiStyle.surfaceRaised.opacity(0.92) : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(BlackMidiStyle.pink)
                        .frame(width: 2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? BlackMidiStyle.pink.opacity(0.55) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var timeSpan: String {
        let start = Self.timeFormatter.string(from: entry.start)
        guard let end = entry.end else { return "\(start)-" }
        return "\(start)-\(Self.timeFormatter.string(from: end))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct HistoryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(isEnabled ? tint : BlackMidiStyle.dimText)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(BlackMidiStyle.surfaceRaised.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke((isEnabled ? tint : BlackMidiStyle.line).opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.55)
    }
}
