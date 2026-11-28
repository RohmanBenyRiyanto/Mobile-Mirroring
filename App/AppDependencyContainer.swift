import DomainModels
import Persistence
import SystemServices
import WorkspaceFeature

@MainActor
struct AppDependencyContainer {
    let model: AppModel

    init() {
        model = AppModel(keymapRoot: ProfileStore<Keymap>.defaultRoot(appName: AppInfo.name),
                         cursorCapture: SystemCursorCapture())
    }
}
