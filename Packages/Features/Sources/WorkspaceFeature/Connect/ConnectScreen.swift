import Components
import DomainModels
import Networking
import SwiftUI
import Theme

struct ConnectScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var status: ConnectStatus {
        ConnectStatus.make(adbMissing: model.isAdbMissing, devices: model.devices, selected: model.selectedDevice, state: model.state)
    }

    var body: some View {
        NavigationSplitView {
            ConnectSidebar(openLogcat: { openWindow(id: "logcat") })
                .navigationSplitViewColumnWidth(min: 180, ideal: Theme.Size.sidebar, max: 260)
        } detail: {
            DeviceDetail(status: status, showsWireless: $model.showsWireless)
                .navigationTitle(model.selectedDevice?.title ?? String(localized: "No device"))
                .navigationSubtitle(model.selectedDevice.map(ConnectText.deviceDetail) ?? String(localized: "Waiting for a phone"))
                .toolbar { toolbar }
        }
        .sheet(isPresented: $model.showsWireless) { WirelessSheet() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ModePicker(model: model)
            if !model.sessions.isEmpty {
                Button("Back to Mirror") { model.isAddingDevice = false }
            }
            Button { model.showsWireless = true } label: { Label("Wireless", systemImage: "wifi") }
                .help("Connect over Wi-Fi")
                .disabled(model.isAdbMissing)
            Button { model.showsDeviceInfo = true } label: { Label("Device Information", systemImage: "info.circle") }
                .help("Device Information")
                .disabled(model.selectedDevice?.isReady != true)
            if status.isStarting {
                Button("Cancel") { model.cancelConnect() }
                Label { Text("Starting…") } icon: { ProgressView().controlSize(.small) }
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Theme.Space.s2)
            } else {
                Button { model.connect() } label: { Label("Start Mirroring", systemImage: "play.fill") }
                    .prominentAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!status.canStart)
            }
        }
    }
}
