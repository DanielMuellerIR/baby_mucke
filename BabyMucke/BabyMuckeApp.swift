import SwiftUI

@main
struct BabyMuckeApp: App {
    @StateObject private var stationStore = StationStore()
    @StateObject private var radioPlayer = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stationStore)
                .environmentObject(radioPlayer)
                .preferredColorScheme(.dark)
        }
    }
}
