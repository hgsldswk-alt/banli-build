import CoreImage.CIFilterBuiltins
import StoreKit
import SwiftUI
import UIKit


struct ImportCodeRow: View {
    @Environment(AppModel.self) private var model
    var onImported: (() -> Void)? = nil
    @State private var message: String?
    @State private var pendingImport: ScheduleData?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("同事发了排班口令？").font(.subheadline.weight(.semibold))
                Text("复制整段话后点「粘贴」，一键导入").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { strings in
                let text = strings.first ?? ""
                Task { @MainActor in handle(text) }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .tint(Color.accentColor)
        }
        .padding(.vertical, 4)
        .alert("班组口令", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("导入会替换班次和循环，清除单日调班及班次闹钟；备注和通用提醒设置会保留。",
                            isPresented: Binding(get: { pendingImport != nil },
                                                 set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("导入排班") {
                if let imported = pendingImport { apply(imported) }
                pendingImport = nil
            }
        }
    }

    @MainActor
    private func handle(_ text: String) {
        guard let imported = ShareCode.decode(text) else {
            message = String(localized: "没认出排班口令。请让同事在「班历 > 设置 > 把排班发给同事」里发给你，复制整段话再点粘贴。")
            return
        }
        if onImported == nil { pendingImport = imported }
        else { apply(imported) }
    }

    @MainActor
    private func apply(_ imported: ScheduleData) {
        model.importShared(imported)
        if let onImported {
            onImported()
        } else {
            message = String(localized: "已导入「\(imported.displayTemplateName)」排班，和同事的班次完全对齐。")
        }
    }
}


struct ShareCodeRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let message = ShareCode.message(for: model.data)
        ShareLink(item: message) {
            Label("把排班发给同事（班组口令）", systemImage: "paperplane.fill")
        }
        Button {
            UIPasteboard.general.string = message
            model.alertMessage = String(localized: "口令已复制。去微信班组群里粘贴发送，同事复制后在班历里点「粘贴」就能导入。")
        } label: {
            Label("复制口令", systemImage: "doc.on.doc")
        }
    }
}


struct ICSExportRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let url = ICSExport.file(for: model.data, from: Date()) {
            ShareLink(item: url) {
                Label("导出到 iPhone 日历", systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("settings.exportICS")
        }
    }
}


enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}


enum ReviewGate {
    private static let launchesKey = "review.launches"
    private static let firstKey = "review.firstLaunch"
    private static let askedKey = "review.askedVersion"

    static var firstLaunch: Date? {
        SharedStore.defaults.object(forKey: firstKey) as? Date
    }

    static func recordLaunch() {
        guard !AppModel.isDemo else { return }
        let d = SharedStore.defaults
        d.set(d.integer(forKey: launchesKey) + 1, forKey: launchesKey)
        if d.object(forKey: firstKey) == nil { d.set(Date(), forKey: firstKey) }
    }

    static func shouldAsk(now: Date = Date()) -> Bool {
        guard !AppModel.isDemo else { return false }
        let d = SharedStore.defaults
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard d.string(forKey: askedKey) != version,
              d.integer(forKey: launchesKey) >= 5,
              let first = firstLaunch,
              now.timeIntervalSince(first) >= 3 * 86400 else { return false }
        d.set(version, forKey: askedKey)
        return true
    }
}
