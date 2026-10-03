import AppKit
import SwiftUI
import MDMInspectorKit

/// Quits the process when the last window closes.
///
/// A SwiftUI app otherwise stays running with no window, which reads as a hang:
/// the Dock icon lingers, Activity Monitor still lists it, and the memory it
/// used reading logs stays resident. This is a single-window tool, so there is
/// nothing worth keeping alive once the window is gone.
///
/// `applicationShouldTerminateAfterLastWindowClosed` is the documented AppKit
/// hook for it; the SwiftUI `defaultAppTerminationBehavior` modifier is not
/// available against this Scene builder.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// If a load is still running, let it finish rather than yanking the app out
    /// from under it, so an in-flight read is never left half-applied.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}

@main
struct MDMInspectorApp: App {
    @StateObject private var model = InspectorModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
