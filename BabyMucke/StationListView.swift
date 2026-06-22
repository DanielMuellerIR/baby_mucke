import SwiftUI
import UniformTypeIdentifiers

struct StationListView: View {
    @EnvironmentObject private var stationStore: StationStore
    @EnvironmentObject private var radioPlayer: RadioPlayer

    @State private var editMode = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var editingDraft: StationDraft?
    @State private var alertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 3) {
                    if stationsForDisplay.isEmpty {
                        Text("Keine Sender")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BlackMidiStyle.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        ForEach(stationsForDisplay) { station in
                            StationRow(station: station, editMode: editMode) {
                                handleStationTap(station)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .background(BlackMidiStyle.panelFill)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: StationsJSONDocument(stations: stationStore.stations),
            contentType: .json,
            defaultFilename: "stations.json"
        ) { result in
            if case .failure(let error) = result {
                alertMessage = error.localizedDescription
            }
        }
        .sheet(item: $editingDraft) { draft in
            StationEditSheet(
                draft: draft,
                onSave: saveDraft,
                onDelete: draft.isNew ? nil : deleteDraft
            )
        }
        .alert("Senderliste", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // Im Normalmodus dieselbe Reihenfolge wie im Bearbeiten-Modus: die
    // gespeicherte Senderreihenfolge. Im Normalmodus nur die aktiven Sender,
    // im Bearbeiten-Modus alle (auch deaktivierte). Kein Umsortieren nach
    // Favorit/zuletzt gespielt -> die Liste bleibt stabil und springt beim
    // Antippen nicht mehr um.
    private var stationsForDisplay: [Station] {
        editMode ? stationStore.stations : stationStore.enabledStations
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("SENDER")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(BlackMidiStyle.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    editMode.toggle()
                } label: {
                    Image(systemName: editMode ? "checkmark" : "pencil")
                        .accessibilityLabel(editMode ? Text("Bearbeiten beenden") : Text("Sender bearbeiten"))
                }
                .buttonStyle(CompactIconButtonStyle(
                    tint: BlackMidiStyle.text,
                    filled: editMode
                ))
                .help(editMode ? "Bearbeiten beenden" : "Sender bearbeiten")
            }
            // Feste Zeilenhoehe (= Hoehe des Bearbeiten-Buttons), damit der
            // SENDER-Header exakt so hoch ist wie der VERLAUF-Header und die
            // Trennlinie darunter auf gleicher Hoehe sitzt.
            .frame(height: 30)

            if editMode {
                HStack(spacing: 6) {
                    Button {
                        editingDraft = StationDraft()
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Sender anlegen")
                    }
                    .buttonStyle(CompactIconButtonStyle(tint: BlackMidiStyle.text))
                    .help("Sender anlegen")

                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .accessibilityLabel("Sender importieren")
                    }
                    .buttonStyle(CompactIconButtonStyle(tint: BlackMidiStyle.text))
                    .help("Sender importieren")

                    Button {
                        showingExporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Sender exportieren")
                    }
                    .buttonStyle(CompactIconButtonStyle(tint: BlackMidiStyle.text))
                    .disabled(stationStore.stations.isEmpty)
                    .help("Sender exportieren")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BlackMidiStyle.line)
                .frame(height: 1)
        }
    }

    private func handleStationTap(_ station: Station) {
        if editMode {
            editingDraft = StationDraft(station: station)
            return
        }

        // Tippen auf einen Sender startet ihn sofort. Nur ein erneutes Tippen auf
        // den bereits laufenden/ladenden Sender bleibt wirkungslos (kein Neustart).
        let isActive = radioPlayer.currentStation?.id == station.id
            && (radioPlayer.isPlaying || radioPlayer.isLoading)
        guard !isActive else { return }
        stationStore.markPlayed(station)
        radioPlayer.play(station)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            try stationStore.importStations(fromFile: url)
            selectDefaultStationAfterListChange()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveDraft(_ draft: StationDraft) {
        let station = draft.station()
        stationStore.upsert(station)
        radioPlayer.refreshCurrentStation(station)
    }

    private func deleteDraft(_ draft: StationDraft) {
        guard let id = draft.originalID,
              let station = stationStore.stations.first(where: { $0.id == id })
        else { return }

        let deletesCurrentStation = radioPlayer.currentStation?.id == station.id
        stationStore.delete(station)
        if deletesCurrentStation {
            radioPlayer.stop()
            selectDefaultStationAfterListChange()
        }
    }

    private func selectDefaultStationAfterListChange() {
        let station = stationStore.lastPlayed
            ?? stationStore.favorite
            ?? stationStore.stationsForPlaybackList.first
        if let station {
            radioPlayer.select(station)
        }
    }
}

private struct StationRow: View {
    @EnvironmentObject private var radioPlayer: RadioPlayer

    var station: Station
    var editMode: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(station.enabled ? BlackMidiStyle.text : BlackMidiStyle.dimText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if editMode {
                    Text(station.url)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(BlackMidiStyle.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isCurrent, !radioPlayer.nowPlayingTitle.isEmpty {
                    Text(radioPlayer.nowPlayingTitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BlackMidiStyle.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? BlackMidiStyle.surfaceRaised.opacity(0.92) : Color.clear)
            .overlay(alignment: .leading) {
                if isCurrent {
                    Rectangle()
                        .fill(BlackMidiStyle.cyan)
                        .frame(width: 2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrent ? BlackMidiStyle.cyan.opacity(0.6) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(station.enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private var isCurrent: Bool {
        radioPlayer.currentStation?.id == station.id
    }
}

private struct StationDraft: Identifiable {
    var id: UUID
    var originalID: UUID?
    var name: String
    var url: String
    var enabled: Bool
    var favorite: Bool

    var isNew: Bool { originalID == nil }

    init() {
        let id = UUID()
        self.id = id
        originalID = nil
        name = ""
        url = ""
        enabled = true
        favorite = false
    }

    init(station: Station) {
        id = station.id
        originalID = station.id
        name = station.name
        url = station.url
        enabled = station.enabled
        favorite = station.favorite
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func station() -> Station {
        Station(id: id, name: name, url: url, enabled: enabled, favorite: favorite)
    }
}

private struct StationEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StationDraft

    var onSave: (StationDraft) -> Void
    var onDelete: ((StationDraft) -> Void)?

    init(draft: StationDraft, onSave: @escaping (StationDraft) -> Void, onDelete: ((StationDraft) -> Void)?) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sender") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)

                    TextField("Stream-URL", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("Aktiv", isOn: $draft.enabled)
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete(draft)
                            dismiss()
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? Text("Sender anlegen") : Text("Sender bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(BlackMidiStyle.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
        }
        .tint(BlackMidiStyle.cyan)
    }
}

private struct StationsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(stations: [Station]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? enc.encode(stations)) ?? Data("[]".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
