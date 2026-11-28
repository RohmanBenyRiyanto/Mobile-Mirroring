import AppKit
import Components
import DatabaseFeature
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

        Window("Mini Mirror", id: "mini") {
            MiniMirrorView()
                .environmentObject(model)
                .themed(model.appearance)
        }
        .defaultSize(width: 180, height: 400)

        Window("API Log", id: "apilog") {
            TrafficLogView()
                .environmentObject(model)
                .themed(model.appearance)
        }
        .defaultSize(width: 900, height: 520)

        Window("Database", id: "database") {
            DatabaseView(source: model)
                .themed(model.appearance)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView(model: model, appearance: model.appearance)
        }
    }
}
