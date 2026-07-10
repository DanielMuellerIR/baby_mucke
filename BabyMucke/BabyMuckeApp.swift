import SwiftUI

@main
struct BabyMuckeApp: App {
    @StateObject private var stationStore = StationStore()
    @StateObject private var radioPlayer = RadioPlayer()
    @AppStorage(AppearanceMode.storageKey) private var storedAppearance = AppearanceMode.automatic.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stationStore)
                .environmentObject(radioPlayer)
                .preferredColorScheme(AppearanceMode.storedValue(storedAppearance).preferredColorScheme)
        }
    }
}
