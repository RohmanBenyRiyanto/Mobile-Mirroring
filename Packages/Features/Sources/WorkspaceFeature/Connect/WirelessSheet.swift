import Components
import AppKit
import DomainModels
import Networking
import SwiftUI
import Theme

struct WirelessSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var connectAddress = ""
    @State private var macNetworks = IPv4Interface.ofThisMac()

    private var canPair: Bool { WirelessInput.isValidAddress(pairAddress) && WirelessInput.isValidPairingCode(pairCode) }
    private var canConnect: Bool { WirelessInput.isValidAddress(connectAddress) }
    private var mismatch: (phone: String, mac: String)? {
        WirelessInput.networkMismatch(address: connectAddress, mac: macNetworks) ?? WirelessInput.networkMismatch(address: pairAddress, mac: macNetworks)
    }
    private var isWirelessPhone: Bool { model.selectedSerial?.contains(":") == true }
    private var canSwitch: Bool { model.selectedDevice?.isReady == true && model.selectedSerial?.contains(":") == false }

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                SettingsCard(footer: "On the phone, open Developer options › Wireless debugging.") {
                    SettingsRow("Switch the connected phone", detail: "Uses the USB cable once, then you can unplug it.") {
                        Button("Switch to Wi-Fi") { model.switchToWireless(); dismiss() }.secondaryAction().disabled(!canSwitch)
                    }
                    if isWirelessPhone {
                        SettingsRow("Switch back to USB", detail: "The phone leaves Wi-Fi debugging and waits for the cable.") {
                            Button("Switch to USB") { model.switchToUSB(); dismiss() }.secondaryAction()
                        }
                    }
                }
                if let mismatch {
                    Section {
                        PlainRow {
                            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                Label("Phone and Mac are not on the same network", systemImage: "wifi.exclamationmark").font(Theme.Font.emphasized)
                                Text("Join the phone to the Wi-Fi this Mac uses, then try again. Guest networks often block this.").foregroundStyle(.secondary)
                                LabeledContent("Mac") { Text(verbatim: mismatch.mac).font(Theme.Font.mono) }
                                LabeledContent("Phone") { Text(verbatim: mismatch.phone).font(Theme.Font.mono) }
                                HStack {
                                    Button("Try Again") { macNetworks = IPv4Interface.ofThisMac() }
                                    Button("Open Wi-Fi Settings…") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") { NSWorkspace.shared.open(url) }
                                    }
                                }
                                .secondaryAction()
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Address") { TextField("", text: $pairAddress, prompt: Text(verbatim: "192.168.1.24:37145")).textFieldStyle(.roundedBorder).font(Theme.Font.mono) }
                    LabeledContent("Pairing code") { CodeBoxes(code: $pairCode) }
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

/// Six digit boxes over one hidden text field, so typing, pasting and deleting all behave like a normal field.
private struct CodeBoxes: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: Binding(get: { code }, set: { code = String($0.filter(\.isASCII).filter(\.isNumber).prefix(6)) }))
                .focused($isFocused).textFieldStyle(.plain).opacity(0.01).accessibilityLabel("Pairing code")
            HStack(spacing: Theme.Space.s1) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(code)
                    Text(verbatim: index < digits.count ? String(digits[index]) : "")
                        .font(Theme.Font.mono).frame(width: 26, height: 32)
                        .background(Theme.Palette.control.color, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).strokeBorder(isFocused && index == min(digits.count, 5) ? Theme.Palette.accentText.color : .clear, lineWidth: 1.5))
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: 6 * 26 + 5 * Theme.Space.s1, height: 32)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
