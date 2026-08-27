import BackTrackPadKit
import SwiftUI

@main
struct BackTrackPadApp: App {
    @StateObject private var coordinator = PadCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if coordinator.libraryImported {
                    PerformView(coordinator: coordinator)
                } else {
                    LibraryImportView(coordinator: coordinator)
                }
            }
            .environmentObject(coordinator.state)
        }
    }
}
