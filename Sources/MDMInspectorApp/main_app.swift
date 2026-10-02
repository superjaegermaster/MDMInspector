import SwiftUI
import MDMInspectorKit

@main
struct MDMInspectorApp: App {
    @StateObject private var model = InspectorModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    if model.lastLoaded == nil {
                        await model.refresh()
                    }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Evidence") {
                Button("Copy Raw Record") {
                    if let e = model.selectedEvent { model.copyRawRecord(e) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selectedEvent == nil)

                Button("Reveal Raw Record in Timeline") {
                    if let e = model.selectedEvent { model.open(e) }
                }
                .disabled(model.selectedEvent == nil)
            }
        }
    }
}
