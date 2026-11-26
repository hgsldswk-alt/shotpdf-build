import Photos
import PhotosUI
import StoreKit
import SwiftUI

@main
struct ShotPDFApp: App {
    var body: some Scene {
        WindowGroup { ShotRoot().preferredColorScheme(.light) }
    }
}

enum SheetRoute: Identifiable {
    case preset, margin, purchases, help, rename, examples, activity(Activity)

    var id: String {
        switch self {
        case .preset: "preset"
        case .margin: "margin"
        case .purchases: "purchases"
        case .help: "help"
        case .rename: "rename"
        case .examples: "examples"
        case .activity(let activity): activity.id.uuidString
        }
    }
}

@MainActor
struct ShotRoot: View {
    @StateObject private var model = AppModel()
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var phase
    @State private var sheet: SheetRoute?
    @State private var picker = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var mode: PickMode = .new
    @State private var layoutOrigin: Screen = .home
    @State private var settingsOrigin: Screen = .home
    @State private var allPhotos = false
    @State private var split: SplitRecord?
    @State private var reviewTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.problem { issueBanner(problem) }
            if let notice = model.notice { noticeBanner(notice) }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea()).tint(Theme.accent)
        .environmentObject(model)
        .sheet(item: $sheet, onDismiss: scheduleReview, content: sheetContent)
        .photosPicker(isPresented: $picker, selection: $photos,
                      maxSelectionCount: selectionLimit, selectionBehavior: .ordered,
                      matching: allPhotos ? .images : .screenshots,
                      preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: photos) { _, chosen in
            guard !chosen.isEmpty else { return }
            let importMode = mode
            photos = []
            Task { await model.ingest(chosen.map(ImportSource.photo), mode: importMode) }
        }
        .onChange(of: model.screen) { _, _ in scheduleReview() }
        .onChange(of: model.busy) { _, _ in scheduleReview() }
        .onChange(of: model.problem) { _, _ in scheduleReview() }
        .onChange(of: phase) { _, value in
            if value == .active { model.refreshClock(); scheduleReview() }
        }
        .task {
            if Launch.arguments.contains("-paywall") { sheet = .purchases }
            await model.begin()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .home:
            HomeScreen(pick: { pick(.new) }, pickOthers: { pick(.new, all: true) }, layout: { openLayout(.home) },
                       preset: { sheet = .preset }, settings: { openSettings(.home) })
        case .batch:
            BatchScreen(back: { model.screen = .home }, append: { pick(.append) },
                        appendOther: { pick(.append, all: true) }, replace: { pick(.replace($0), all: true) },
                        layout: { openLayout(.batch) }, upgrade: { sheet = .purchases })
        case .layout:
            LayoutScreen(applyToDraft: layoutOrigin == .batch, back: { model.screen = layoutOrigin },
                         showMargin: { sheet = .margin }, upgrade: { sheet = .purchases })
        case .preview:
            PreviewScreen(back: { model.cancelRender(); model.screen = .batch },
                          adjust: { split = $0; model.screen = .split })
        case .split:
            if let split, model.hasPro {
                SplitScreen(record: split, back: { model.screen = .preview })
            }
        case .finished:
            FinishedScreen(edit: {
                model.dismissMilestone()
                model.screen = model.draft?.shots.isEmpty == false ? .batch : .home
            }, home: {
                model.dismissMilestone()
                model.screen = .home
            }, next: { pick(.new) }, rename: { sheet = .rename }, share: { sheet = .activity($0) })
        case .settings:
            SettingsScreen(back: { model.screen = settingsOrigin }, layout: { openLayout(.settings) },
                           preset: { sheet = .preset }, purchases: { sheet = .purchases }, help: { sheet = .help })
        }
    }

    @ViewBuilder private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .preset: PresetSheet().environmentObject(model)
        case .margin: MarginSheet(applyToDraft: layoutOrigin == .batch).environmentObject(model)
        case .purchases: PurchaseSheet(purchases: model.purchases).environmentObject(model)
        case .help: HelpSheet()
        case .rename: RenameSheet(filename: model.finished?.url.deletingPathExtension().lastPathComponent ?? "")
            .environmentObject(model)
        case .examples:
            ExamplePicker(single: selectionLimit == 1) { examples in
                let importMode = mode
                sheet = nil
                Task { await model.ingest(examples.map(ImportSource.example), mode: importMode) }
            }
        case .activity(let activity): ActivitySheet(activity: activity).presentationDetents([.large])
        }
    }

    private var selectionLimit: Int? {
        if case .replace = mode { return 1 }
        return nil
    }

    private func pick(_ value: PickMode, all: Bool = false) {
        guard !model.busy else { return }
        mode = value
        allPhotos = all
        if Launch.arguments.contains("-seed") { sheet = .examples }
        else { picker = true }
    }

    private func openLayout(_ from: Screen) { layoutOrigin = from; model.screen = .layout }
    private func openSettings(_ from: Screen) { settingsOrigin = from; model.screen = .settings }

    private func scheduleReview() {
        reviewTask?.cancel()
        guard phase == .active, model.screen == .home, sheet == nil, !picker, !model.busy else { return }
        reviewTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard phase == .active, sheet == nil, !picker, model.takeReviewRequest() else { return }
            requestReview()
        }
    }

    private func issueBanner(_ text: String) -> some View {
        HStack {
            Callout(text: text, icon: "exclamationmark.circle").accessibilityIdentifier("flow.problem")
            Button { model.problem = nil } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityLabel(L.t("action.close")).accessibilityIdentifier("flow.dismissProblem")
        }
        .padding(.horizontal, 20)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack {
            Callout(text: text, tone: .green, icon: "checkmark.circle").accessibilityIdentifier("flow.notice")
            if model.canUndo {
                Button { model.undo() } label: {
                    Text(L.t("action.undo")).font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("flow.undo")
            }
            Button { model.notice = nil } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityLabel(L.t("action.close")).accessibilityIdentifier("flow.dismissNotice")
        }
        .padding(.horizontal, 20)
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var model: AppModel
    let pick: () -> Void
    let pickOthers: () -> Void
    let layout: () -> Void
    let preset: () -> Void
    let settings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: L.t("home.title"), id: "home") {
                    Button(action: settings) {
                        Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                            .foregroundStyle(Theme.accent).panel(radius: 14, shadow: false)
                    }
                    .buttonStyle(.plain).accessibilityLabel(L.t("settings.title")).accessibilityIdentifier("home.settings")
                }
                HeroCard {
                    PrimaryButton(title: L.t("home.pick"), symbol: "photo.on.rectangle", id: "home.pick", action: pick)
                        .disabled(model.busy)
                }
                if model.draft?.shots.isEmpty == false {
                    RowButton(title: L.t("home.resume"), symbol: "arrow.clockwise", id: "home.resume", tone: .green) {
                        model.screen = .batch
                    }.panel()
                }
                HStack(alignment: .top, spacing: 11) {
                    IconTile(title: L.t("layout.title"), symbol: "square.grid.2x2", id: "home.layout", action: layout)
                    IconTile(title: L.t("preset.import"), symbol: "viewfinder", id: "home.preset", tone: .amber, action: preset)
                }
                if model.finished != nil {
                    RowButton(title: L.t("home.recent"), symbol: "doc.text", id: "home.recent") { model.screen = .finished }
                        .panel()
                }
                if model.canRetryImport {
                    PrimaryButton(title: L.t("import.retry"), symbol: "arrow.clockwise", id: "home.retry", kind: .secondary) {
                        Task { await model.retryImports() }
                    }.disabled(model.busy)
                }
                HStack {
                    Label(L.t("home.private"), systemImage: "checkmark.shield").font(.caption).foregroundStyle(Theme.muted)
                    Spacer(minLength: 6)
                    Button(action: pickOthers) {
                        Label(L.t("home.other"), systemImage: "photo").font(.caption.weight(.medium))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("home.other").disabled(model.busy)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 22)
        }
    }
}
