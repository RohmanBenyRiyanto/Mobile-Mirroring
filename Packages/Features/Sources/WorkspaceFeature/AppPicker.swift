import Components
import DomainModels
import SwiftUI

extension AppModel {
    public var appPickerItems: [PickerItem] {
        installedApps.map { PickerItem(id: $0.package, title: $0.name, subtitle: $0.package, badge: $0.isRecent ? "Recent" : nil) }
    }
}

public struct AppPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var package: String?

    public init(package: Binding<String?>) { _package = package }

    public var body: some View {
        SearchPicker(selection: $package, items: model.appPickerItems, isLoading: model.isLoadingApps,
                     selectionTitle: { InstalledApps.displayName(for: $0) },
                     footer: (title: "Use app in front", action: { model.useFrontAppForSeparateDisplay() }),
                     onOpen: { await model.loadInstalledApps() })
            .disabled(model.targetSerial == nil)
    }
}
