import SwiftUI

@main
struct DiskMapApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("DiskMap") {
            ContentView(model: model)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
