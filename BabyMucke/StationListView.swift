import SwiftUI
import UniformTypeIdentifiers

struct StationListView: View {
    @EnvironmentObject private var stationStore: StationStore
    @EnvironmentObject private var radioPlayer: RadioPlayer

    @State private var editMode = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: StationsJSONDocument?
    @State private var pendingImportURL: URL?
    @State private var showingImportConfirmation = false
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
        // codereview-ok: fileImporter/fileExporter haengen bewusst am dauerhaft gemounteten Haupt-View statt im editMode-Block — dort wuerden sie beim Verlassen des Bearbeiten-Modus abgebaut, waehrend der System-Dialog noch offen ist (2026-07-08)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showingImportConfirmation = true
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
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
        .alert("Senderliste importieren", isPresented: $showingImportConfirmation) {
            Button("Ersetzen", role: .destructive) {
                if let url = pendingImportURL {
                    executeImport(url)
                }
                pendingImportURL = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Möchtest du die Senderliste importieren? Die aktuelle Senderliste wird dabei ersetzt.")
        }
        // codereview-ok: "Senderliste" ist ein LocalizedStringKey und in Localizable.xcstrings uebersetzt — kein hardcodierter Text (2026-07-08)
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
                        exportDocument = StationsJSONDocument(stations: stationStore.stations)
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

    private func executeImport(_ url: URL) {
        do {
            try stationStore.importStations(fromFile: url)
            StationListSynchronizer.synchronize(store: stationStore, player: radioPlayer)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func saveDraft(_ draft: StationDraft) {
        let station = draft.station()
        stationStore.upsert(station)
        StationListSynchronizer.synchronize(store: stationStore, player: radioPlayer)
    }

    private func deleteDraft(_ draft: StationDraft) {
        guard let id = draft.originalID,
              let station = stationStore.stations.first(where: { $0.id == id })
        else { return }

        stationStore.delete(station)
        StationListSynchronizer.synchronize(store: stationStore, player: radioPlayer)
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
            .selectionChrome(isSelected: isCurrent, accent: BlackMidiStyle.cyan)
            .opacity(station.enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private var isCurrent: Bool {
        radioPlayer.currentStation?.id == station.id
    }
}

// codereview-ok: StationDraft spiegelt Station bewusst als Bearbeitungs-Puffer — ein direktes @Binding<Station> wuerde live in den Store schreiben und "Abbrechen" um seine Verwerfen-Funktion bringen; originalID trennt Neu von Bearbeiten (2026-07-08)
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

    var isURLValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed), let scheme = u.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }

    var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isURLValid
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
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)

                    TextField("Stream-URL", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("Aktiv", isOn: $draft.enabled)
                } header: {
                    Text("Sender")
                } footer: {
                    if !draft.isURLValid && !draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Bitte eine gültige HTTP- oder HTTPS-URL eingeben.")
                            .font(.caption)
                            .foregroundStyle(BlackMidiStyle.red)
                    }
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
        data = (try? StationStore.stationsEncoder.encode(stations)) ?? Data("[]".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
