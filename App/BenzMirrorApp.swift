import AppKit
import LogcatFeature
import SwiftUI
import WorkspaceFeature

@main
struct BenzMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppDependencyContainer().model

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    // Keymap files opened from Finder (double-click) arrive through the app delegate.
                    delegate.fileInbox.handler = { urls in
                        for url in urls where url.pathExtension.lowercased() == KeymapFile.fileExtension { model.importKeymap(from: url) }
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        Window("Logcat", id: "logcat") {
            LogcatView(source: model)
        }
    }
}
