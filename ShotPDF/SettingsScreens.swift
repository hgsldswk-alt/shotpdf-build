import SwiftUI
import UIKit

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    let back: () -> Void
    let layout: () -> Void
    let preset: () -> Void
    let purchases: () -> Void
    let help: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                ScreenHeader(title: L.t("settings.title"), id: "settings", back: back) { EmptyView() }
                if !Launch.freePeriod { premium }
                Text(L.t("settings.presets")).font(.headline)
                VStack(spacing: 0) {
                    RowButton(title: L.t("settings.default"), symbol: "square.grid.2x2", id: "settings.layout",
                              value: L.f("settings.grid", model.defaults.grid.rawValue), action: layout)
                    Divider().overlay(Theme.line)
                    RowButton(title: L.t("preset.copy"), symbol: "square.on.square", id: "settings.copy", tone: .amber) {
                        do {
                            UIPasteboard.general.string = try Preset.encode(model.defaults)
                            model.notice = L.t("notice.copied")
                        } catch { model.problem = L.t("error.preset") }
                    }
                    Divider().overlay(Theme.line)
                    RowButton(title: L.t("preset.import"), symbol: "viewfinder", id: "settings.preset", tone: .green, action: preset)
                }.panel()
                VStack(spacing: 0) {
                    if !Launch.freePeriod {
                        RowButton(title: L.t("purchase.restore"), symbol: "arrow.counterclockwise", id: "settings.restore") {
                            Task {
                                await model.purchases.restore(accept: model.accept)
                                model.notice = model.purchases.notice
                                model.problem = model.purchases.problem
                            }
                        }
                        Divider().overlay(Theme.line)
                    }
                    RowButton(title: L.t("settings.clear"), symbol: "trash", id: "settings.clear", tone: .amber) {
                        model.clearDraft()
                    }.disabled(model.draft == nil || model.busy)
                    Divider().overlay(Theme.line)
                    RowButton(title: L.t("settings.help"), symbol: "info.circle", id: "settings.help", tone: .green, action: help)
                }.panel()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 21)
        }
    }

    private var premium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("purchase.title")).font(.headline)
                Spacer()
                StatusPill(title: PurchaseCopy.status(model), tone: model.hasPro ? .green : .amber)
            }
            Text(L.t("purchase.features")).font(.caption).foregroundStyle(Theme.muted)
            if model.entitlement?.purchasedPro != true {
                PrimaryButton(title: L.t("purchase.view"), symbol: "lock.open", id: "settings.purchase",
                              kind: .secondary, action: purchases)
            }
        }
        .padding(14).panel()
    }
}

@MainActor
private enum PurchaseCopy {
    static func status(_ model: AppModel) -> String {
        if let entitlement = model.entitlement {
            if entitlement.purchasedPro { return L.t("purchase.active") }
            if model.hasPro { return L.f("purchase.days", entitlement.remainingDays(at: model.now)) }
        }
        return L.t("purchase.expired")
    }
}

struct PurchaseSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var purchases: Purchases

    var body: some View {
        SheetFrame(title: L.t("purchase.title"), id: "purchase") {
            VStack(alignment: .leading, spacing: 12) {
                IconBox(symbol: "lock.open", tone: .green)
                Text(PurchaseCopy.status(model)).font(.title2.bold())
                    .accessibilityIdentifier(model.hasPro ? "purchase.available" : "purchase.expired")
                Text(L.t("purchase.features"))
                Text(L.t("purchase.rule")).font(.subheadline).foregroundStyle(Theme.muted)
                Text(L.t("purchase.oneTime")).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(17).panel(Theme.blueWash)
            if model.entitlement?.purchasedPro != true {
                PrimaryButton(title: purchases.product.map { L.f("purchase.buyPrice", $0.displayPrice) } ?? L.t("purchase.buy"),
                              symbol: "lock.open", id: "purchase.buy") {
                    Task { await purchases.buy(accept: model.accept) }
                }.disabled(purchases.busy)
            }
            PrimaryButton(title: L.t("purchase.restore"), symbol: "arrow.counterclockwise", id: "purchase.restore", kind: .secondary) {
                Task { await purchases.restore(accept: model.accept) }
            }.disabled(purchases.busy)
            if purchases.busy { ProgressView() }
            if let problem = purchases.problem { Callout(text: problem) }
            if let notice = purchases.notice { Callout(text: notice, tone: .green) }
        }
        .task { await purchases.loadProduct() }
    }
}

struct PresetSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var editing: Bool

    private var decoded: Layout? { try? Preset.decode(text) }

    var body: some View {
        SheetFrame(title: L.t("preset.import"), id: "preset") {
            Text(L.t("preset.hint")).font(.subheadline).foregroundStyle(Theme.muted)
            TextField(L.t("preset.placeholder"), text: $text, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4)
                .padding(12).panel(shadow: false).focused($editing).accessibilityIdentifier("preset.code")
            if Launch.isTesting, let sample = ProcessInfo.processInfo.environment["SHOTPDF_TEST_PASTE"] {
                PrimaryButton(title: L.t("preset.paste"), symbol: "clipboard", id: "preset.paste", kind: .secondary) {
                    text = sample
                }
            } else {
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { text = value; editing = false }
                }
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .accessibilityIdentifier("preset.paste")
            }
            if let value = decoded {
                VStack(alignment: .leading, spacing: 8) {
                    IconRow(title: L.f("settings.grid", value.grid.rawValue), symbol: "square.grid.2x2")
                    Text(L.f("layout.mm", value.margin))
                    Text(L.t(value.numbers ? "preset.numbersOn" : "preset.numbersOff"))
                    Text(L.t(value.date ? "preset.dateOn" : "preset.dateOff"))
                    Text(L.t(value.splitLong ? "preset.splitOn" : "preset.splitOff"))
                }
                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).panel().accessibilityIdentifier("preset.preview")
                if !model.hasPro && value.usesPro { Callout(text: L.t("preset.locked")) }
            } else if !text.isEmpty {
                Callout(text: L.t("error.preset")).accessibilityIdentifier("preset.invalid")
            }
            PrimaryButton(title: L.t("action.apply"), symbol: "checkmark", id: "preset.apply") {
                guard let value = decoded else { return }
                guard model.updateLayout(value, applyToDraft: false) else { return }
                model.notice = L.t("notice.applied")
                dismiss()
            }.disabled(decoded == nil)
        }
    }
}

struct MarginSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let applyToDraft: Bool
    @State private var text = ""
    private var value: Layout { applyToDraft ? model.layout : model.defaults }
    private var number: Int? { Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var body: some View {
        SheetFrame(title: L.t("layout.margin"), id: "margin") {
            VStack(spacing: 0) {
                choice("margin.narrow", mm: 6)
                Divider().overlay(Theme.line)
                choice("margin.standard", mm: 10)
                Divider().overlay(Theme.line)
                choice("margin.wide", mm: 16)
            }.panel()
            Text(L.t("margin.custom")).font(.subheadline.weight(.semibold))
            TextField(L.t("margin.range"), text: $text).keyboardType(.numberPad)
                .padding(12).panel(shadow: false).accessibilityIdentifier("margin.custom")
            PrimaryButton(title: L.t("action.apply"), symbol: "checkmark", id: "margin.apply") {
                if let number { apply(number) }
            }.disabled(number.map { !(5...25).contains($0) } ?? true)
        }.onAppear { text = String(value.margin) }
    }

    private func choice(_ key: String, mm: Int) -> some View {
        RowButton(title: L.t(key), symbol: "viewfinder", id: key, value: L.f("layout.mm", mm)) { apply(mm) }
    }

    private func apply(_ mm: Int) {
        guard model.hasPro else { dismiss(); return }
        var layout = value
        layout.margin = mm
        if model.updateLayout(layout, applyToDraft: applyToDraft) { dismiss() }
    }
}

struct RenameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var filename: String

    var body: some View {
        SheetFrame(title: L.t("finished.rename"), id: "rename") {
            TextField(L.t("rename.placeholder"), text: $filename)
                .padding(12).panel(shadow: false).accessibilityIdentifier("rename.name")
            if let problem = model.problem { Callout(text: problem) }
            PrimaryButton(title: L.t("action.apply"), symbol: "checkmark", id: "rename.apply") {
                if model.rename(filename) { dismiss() }
            }.disabled(PDFExport.name(filename) == nil)
        }
    }
}

struct HelpSheet: View {
    var body: some View {
        SheetFrame(title: L.t("settings.help"), id: "help") {
            Callout(text: L.t("help.steps"), tone: .blue)
            Callout(text: L.t("help.privacy"), tone: .green, icon: "checkmark.shield")
            Callout(text: L.t("help.files"), tone: .blue, icon: "folder")
        }
    }
}

struct ExamplePicker: View {
    let single: Bool
    let complete: ([Int]) -> Void
    @State private var chosen: [Int] = []

    var body: some View {
        SheetFrame(title: L.t("seed.title"), id: "examples") {
            if !single {
                PrimaryButton(title: L.t("seed.all"), symbol: "checkmark.rectangle", id: "examples.all", kind: .secondary) {
                    chosen = Array(1...24)
                }
            }
            PrimaryButton(title: L.t("seed.add"), symbol: "plus", id: "examples.add") { complete(chosen) }
                .disabled(chosen.isEmpty)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 8) {
                ForEach(1...24, id: \.self) { index in
                    Button {
                        if single { chosen = [index] }
                        else if chosen.contains(index) { chosen.removeAll { $0 == index } }
                        else { chosen.append(index) }
                    } label: {
                        Label("\(index)", systemImage: index == 24 ? "doc.text" : "photo")
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.accent).panel(chosen.contains(index) ? Theme.blueWash : .white, shadow: false)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("examples.item.\(index)")
                    .accessibilityAddTraits(chosen.contains(index) ? .isSelected : [])
                }
            }
        }
    }
}

struct SheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let id: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: title, id: id) {
                    Button { dismiss() } label: {
                        Text(L.t("action.close")).font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(id + ".close")
                }
                content
            }
            .foregroundStyle(Theme.ink).padding(20)
        }
        .background(Theme.background.ignoresSafeArea()).tint(Theme.accent)
    }
}
