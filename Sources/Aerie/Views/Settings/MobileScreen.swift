import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Settings → Mobile: the iPhone remote. An on/off switch for the phone
/// backend, how to reach it over Tailscale (command or QR code), and the
/// paired phones with Revoke. No design artboard exists for this screen; it
/// follows the Advanced screen's card + toggle-row vocabulary.
struct MobileScreen: View {
    let controller: MobileController
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(
                    eyebrow: "Mobile",
                    title: "iPhone",
                    subtitle: "PRs · diffs · AI Review · approve · merge",
                    subtitleSize: 12.5
                )
                SectionEyebrow(text: "Access").padding(.top, 28)
                accessCard.padding(.top, 10)
                if controller.enabled {
                    SectionEyebrow(text: "Tailscale").padding(.top, 28)
                    tailscaleCard.padding(.top, 10)
                }
                SectionEyebrow(text: "Paired iPhones").padding(.top, 28)
                devicesCard.padding(.top, 10)
            }
            .settingsPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await controller.reloadDevices()
            await controller.refreshTailscale()
        }
    }

    // MARK: Access

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow iPhone access")
                        .aerieFont(AerieFont.custom(.sans, size: 14))
                        .foregroundStyle(AerieColor.text1)
                    Text("Serves the Aerie web app on 127.0.0.1:\(String(controller.port)). GitHub tokens never leave this Mac.")
                        .aerieFont(AerieFont.small())
                        .foregroundStyle(AerieColor.text3)
                }
                Spacer(minLength: 16)
                Toggle("Allow iPhone access", isOn: Binding(
                    get: { controller.enabled },
                    set: { on in Task { await controller.setEnabled(on) } }))
                    .labelsHidden()
                    .toggleStyle(.aerie)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            if let status = serverStatus {
                Rectangle().fill(AerieColor.glassLine).frame(height: 1)
                HStack(spacing: 8) {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                        .shadow(color: status.color, radius: 4)
                    Text(status.text)
                        .aerieFont(AerieFont.code(11))
                        .foregroundStyle(status.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .glass(.card)
        .overlay(HudCorners())
    }

    private var serverStatus: (text: String, color: Color)? {
        switch controller.server {
        case .off: return nil
        case .starting: return ("starting…", AerieColor.text3)
        case .running(let port): return ("listening on 127.0.0.1:\(port)", AerieColor.arc)
        case .failed(let message): return (message, AerieColor.crimsonHot)
        }
    }

    // MARK: Tailscale

    private var tailscaleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch controller.tailscale {
            case .unknown:
                note("Checking Tailscale…")
            case .notInstalled:
                note("Tailscale isn't installed. The iPhone reaches Aerie through Tailscale, which also provides the HTTPS a passkey needs.")
                Button("Get Tailscale") {
                    NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!)
                }
                .buttonStyle(.hud(.standard, size: .small))
            case .notServing(let host):
                note(host == nil
                     ? "Tailscale isn't connected. Connect it, then publish Aerie on your tailnet:"
                     : "Publish Aerie on your tailnet (adds a :\(MobileController.tailscalePort) mapping and leaves your other ones alone):")
                commandRow(controller.serveCommand)
            case .conflict(let host, let target):
                note("https://\(host):\(MobileController.tailscalePort) already forwards to \(target). Point it at Aerie instead:")
                commandRow(controller.serveCommand)
            case .serving(let url):
                HStack(alignment: .top, spacing: 18) {
                    if let qr = Self.qrImage(url.absoluteString) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 132, height: 132)
                            .padding(8)
                            .background(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        note("On your iPhone, open this in Safari, Share → Add to Home Screen, then tap Link this iPhone:")
                        commandRow(url.absoluteString)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Re-check") { Task { await controller.refreshTailscale() } }
                    .buttonStyle(.hud(.ghost, size: .small))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
        .overlay(HudCorners())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .aerieFont(AerieFont.small())
            .foregroundStyle(AerieColor.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func commandRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .aerieFont(AerieFont.code(11.5))
                .foregroundStyle(AerieColor.amber)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(copied == text ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = text
            }
            .buttonStyle(.hud(.standard, size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
        .overlay(Rectangle().strokeBorder(AerieColor.glassLine, lineWidth: 1))
    }

    static func qrImage(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: Devices

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.devices.isEmpty {
                note("No iPhone paired yet. Pairing asks for your OK here on the Mac, then Face ID on the phone.")
                    .padding(18)
            } else {
                ForEach(Array(controller.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Rectangle().fill(AerieColor.glassLine).frame(height: 1) }
                    deviceRow(device)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card)
        .overlay(HudCorners())
    }

    private func deviceRow(_ device: MobileDevice) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .aerieFont(AerieFont.custom(.sans, size: 14))
                    .foregroundStyle(AerieColor.text1)
                Text("paired \(Self.dateText(device.createdAt)) · last seen \(Self.relative(device.lastSeenAt)) · \(device.rpId)")
                    .aerieFont(AerieFont.code(10.5))
                    .foregroundStyle(AerieColor.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            Button("Revoke") { Task { await controller.revoke(device) } }
                .buttonStyle(.hud(.danger, size: .small))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private static func dateText(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .omitted)
    }

    private static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
