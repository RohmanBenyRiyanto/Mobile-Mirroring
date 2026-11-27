import DomainModels
import Persistence
import SystemServices
import WorkspaceFeature

/// Builds the app's long-lived objects and wires their dependencies, so the features never reach for globals.
@MainActor
struct AppDependencyContainer {
    let model: AppModel

    init() {
        model = AppModel(keymapRoot: ProfileStore<Keymap>.defaultRoot(appName: AppInfo.name),
                         cursorCapture: SystemCursorCapture())
    }
}
