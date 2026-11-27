import AppKit
import Components
import LogcatFeature
import SettingsFeature
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
                .themed(model.appearance)
                .onAppear {
                    delegate.model = model
                    // Finder-opened keymap files arrive through the app delegate.
                    delegate.fileInbox.handler = { urls in
                        for url in urls where url.pathExtension.lowercased() == KeymapFile.fileExtension { model.importKeymap(from: url) }
                    }
                }
        }
        .defaultSize(width: 760, height: 512)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        Window("Logcat", id: "logcat") {
            LogcatView(source: model)
                .themed(model.appearance)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView(model: model, appearance: model.appearance)
        }
    }
}
