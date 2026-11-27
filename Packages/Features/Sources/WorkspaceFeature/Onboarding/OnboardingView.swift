import Components
import Networking
import SwiftUI
import Theme

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var flow = OnboardingFlow()

    private var phone: OnboardingFlow.Phone { OnboardingFlow.phone(in: model.devices) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text("Welcome").font(Theme.Font.caption).foregroundStyle(.secondary)
                Text("Step \(flow.step.rawValue + 1) of \(OnboardingFlow.Step.allCases.count)").font(Theme.Font.caption).foregroundStyle(.secondary)
                heading
                NumberedSteps(steps)
                sample
            }
            .padding(Theme.Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer.padding(Theme.Space.s4)
        }
        .frame(width: 520, height: 620)
        .animated(value: flow)
        .animated(value: phone)
    }

    // MARK: Content

    private var isReady: Bool { if case .ready = phone { return true } else { return false } }

    @ViewBuilder private var heading: some View {
        switch flow.step {
        case .developerOptions: titles("Turn on Developer options", "Android keeps these settings hidden until you ask for them.")
        case .usbDebugging: titles("Turn on USB debugging", "This lets your Mac see and control the phone.")
        case .allowMac:
            switch phone {
            case let .ready(name, _): titles(LocalizedStringKey("\(name) is ready"), "You can start mirroring now.")
            case .unauthorized: titles("The Mac is not allowed yet", "The request on the phone was closed or declined.")
            case .waiting: titles("Allow this Mac", "The phone asks once for each new computer.")
            }
        }
    }

    private func titles(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(title).font(Theme.Font.title)
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var steps: [LocalizedStringKey] {
        switch flow.step {
        case .developerOptions: return ["Open Settings, then About phone.", "Tap Build number seven times.", "Enter your screen lock if the phone asks."]
        case .usbDebugging: return ["Open Settings › System › Developer options.", "Turn on USB debugging.", "Plug the phone into this Mac."]
        case .allowMac:
            switch phone {
            case .ready: return ["USB debugging is on.", "This Mac is allowed."]
            case .unauthorized: return ["Unplug the cable and plug it in again.", "Tap Allow when the phone asks."]
            case .waiting: return ["Unlock the phone.", "Tick “Always allow from this computer”.", "Tap Allow."]
            }
        }
    }

    @ViewBuilder private var sample: some View {
        switch phone {
        case let .ready(name, serial) where flow.isLast:
            card("This Mac sees") { row(name, serial) }
        case .unauthorized where flow.isLast:
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                card("This Mac sees") { row("Still unauthorized", nil) }
                Text("If no request appears, open Developer options and choose Revoke USB debugging authorizations.").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        default:
            card("On the phone") {
                switch flow.step {
                case .developerOptions: row("Build number", "tap × 7")
                case .usbDebugging: row("USB debugging", nil)
                case .allowMac: row("Allow USB debugging?", nil)
                }
            }
        }
    }

    private func card(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(title).font(Theme.Font.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.Space.s2) { content() }
                .padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Palette.card.color, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private func row(_ title: LocalizedStringKey, _ detail: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let detail { Text(verbatim: detail).font(Theme.Font.mono).foregroundStyle(.secondary) }
        }
    }

    private func row(_ title: String, _ detail: String?) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            if let detail { Text(verbatim: detail).font(Theme.Font.mono).foregroundStyle(.secondary) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if !(flow.isLast && isReady) { Button("Skip Setup") { finish() }.buttonStyle(.link) }
            if flow.isLast && !isReady && phone == .waiting {
                ProgressView().controlSize(.small)
                Text("Waiting for the phone…").foregroundStyle(.secondary)
            }
            Spacer()
            if !flow.isFirst { Button("Back") { flow.back() }.secondaryAction() }
            if !flow.isLast {
                Button("Continue") { flow.next() }.prominentAction().keyboardShortcut(.defaultAction)
            } else if isReady {
                Button("Start Mirroring") { finish(); model.connect() }.prominentAction().keyboardShortcut(.defaultAction)
            } else if phone == .unauthorized {
                Button("Try Again") { model.refreshDevicesNow() }.prominentAction()
            } else {
                Button("Done") { finish() }.prominentAction()
            }
        }
    }

    private func finish() {
        model.finishOnboarding()
        dismiss()
    }
}
