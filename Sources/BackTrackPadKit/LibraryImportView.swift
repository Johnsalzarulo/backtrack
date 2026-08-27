import BackTrackCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryImportView: View {
    @ObservedObject var coordinator: PadCoordinator
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 24) {
            Text("BackTrack")
                .font(.largeTitle.bold().monospaced())
            Text("Import your Mac BackTrack folder (Songs, Setlists, Samples) to perform on iPad.")
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(coordinator.libraryImported ? "Update library" : "Import library") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
            .font(.headline.monospaced())

            if let error = coordinator.importError {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let folder = urls.first else { return }
            guard folder.startAccessingSecurityScopedResource() else {
                coordinator.importError = "Could not access the selected folder."
                return
            }
            defer { folder.stopAccessingSecurityScopedResource() }
            if coordinator.libraryImported {
                coordinator.updateLibrary(from: folder)
            } else {
                coordinator.importLibrary(from: folder)
            }
        }
    }
}
