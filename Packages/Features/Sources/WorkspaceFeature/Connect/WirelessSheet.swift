import Components
import DomainModels
import Networking
import SwiftUI
import Theme

/// Wi-Fi setup: switch the plugged-in phone over, or pair and connect by address.
struct WirelessSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var connectAddress = ""

    private var canPair: Bool { WirelessInput.isValidAddress(pairAddress) && WirelessInput.isValidPairingCode(pairCode) }
    private var canConnect: Bool { WirelessInput.isValidAddress(connectAddress) }
    private var canSwitch: Bool { model.selectedDevice?.isReady == true && model.selectedSerial?.contains(":") == false }

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                SettingsCard(footer: "On the phone, open Developer options › Wireless debugging.") {
                    SettingsRow("Switch the connected phone", detail: "Uses the USB cable once, then you can unplug it.") {
                        Button("Switch to Wi-Fi") { model.switchToWireless(); dismiss() }.secondaryAction().disabled(!canSwitch)
                    }
                }
                Section {
                    LabeledContent("Address") { TextField("", text: $pairAddress, prompt: Text(verbatim: "192.168.1.24:37145")).textFieldStyle(.roundedBorder).font(Theme.Font.mono) }
                    LabeledContent("Pairing code") { SecureField("", text: $pairCode, prompt: Text("6 digits")).textFieldStyle(.roundedBorder).font(Theme.Font.mono) }
                    HStack {
                        Spacer()
                        Button("Pair") { model.pair(address: pairAddress, code: pairCode); pairCode = "" }.secondaryAction().disabled(!canPair)
                    }
                } header: { stepHeader(1, "Pair") }
                Section {
                    LabeledContent("Address") { TextField("", text: $connectAddress, prompt: Text(verbatim: "192.168.1.24:port")).textFieldStyle(.roundedBorder).font(Theme.Font.mono) }
                } header: { stepHeader(2, "Connect") } footer: { Text("You can unplug USB after connecting.") }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Connect") { model.connectWireless(address: connectAddress); dismiss() }
                    .prominentAction().disabled(!canConnect)
            }
            .padding(Theme.Space.s4)
        }
        .frame(width: 500, height: 520)
    }

    private func stepHeader(_ number: Int, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Space.s2) {
            Text("\(number)").font(Theme.Font.monoCaption).frame(width: 18, height: 18).background(Theme.Palette.control.color, in: Circle())
            Text(title)
        }
    }
}
