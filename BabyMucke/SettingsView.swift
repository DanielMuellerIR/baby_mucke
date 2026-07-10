import SwiftUI

// Die gespeicherte Auswahl bleibt als stabiler String in UserDefaults. So kann
// die App spaeter weitere Darstellungen ergaenzen, ohne alte Werte umzudeuten.
enum AppearanceMode: String, CaseIterable, Identifiable {
    static let storageKey = "appearanceMode"

    case automatic
    case light
    case dark

    var id: String { rawValue }

    static func storedValue(_ rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .automatic
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Automatisch"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceMode.storageKey) private var storedAppearance = AppearanceMode.automatic.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Erscheinungsbild", selection: appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label {
                                Text(mode.title)
                            } icon: {
                                Image(systemName: mode.systemImage)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Automatisch folgt der Systemeinstellung des iPhones.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(BlackMidiStyle.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .tint(BlackMidiStyle.cyan)
    }

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode.storedValue(storedAppearance) },
            set: { storedAppearance = $0.rawValue }
        )
    }
}
