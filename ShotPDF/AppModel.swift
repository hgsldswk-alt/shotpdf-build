import Foundation
import StoreKit
import SwiftUI

enum Screen: Equatable { case home, batch, layout, preview, split, finished, settings }
enum PickMode: Equatable { case new, append, replace(UUID) }

struct History: Codable {
    var progress = ReviewProgress()
    var recent: PDFResult?
    var milestonePending = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published private(set) var draft: Draft?
    @Published private(set) var defaults = Layout()
    @Published private(set) var preview: PDFResult?
    @Published private(set) var finished: PDFResult?
    @Published private(set) var history = History()
    @Published private(set) var importing = false
    @Published private(set) var rendering = false
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var now = Date()
    @Published private(set) var firstTen = false
    @Published var page = 1
    @Published var problem: String?
    @Published var notice: String?

    let workspace: Workspace
    let purchases = Purchases()
    private let keychain = PurchaseDisk()
    private let clock: () -> Date
    private var cachedRequest: RenderRequest?
    private var renderTask: Task<PDFResult, Error>?
    private var retryRender: (preview: Bool, firstTen: Bool)?
    private var failedSources: [UUID: ImportSource] = [:]
    private var pendingNew: [(Shot, ImportSource)] = []
    private var undoDraft: Draft?
    private var expiryTask: Task<Void, Never>?
    private var reviewCandidate = false
    private var workspaceReady = false

    init(workspace supplied: Workspace? = nil, clock: @escaping () -> Date = Date.init,
         loadEntitlement: (() throws -> Entitlement)? = nil) {
        self.clock = clock
        let files = FileManager.default
        let base = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let name = Launch.isTesting || Launch.hostedTests ? "ShotPDF-Testing" : "ShotPDF"
        workspace = supplied ?? Workspace(root: base.appendingPathComponent(name, isDirectory: true))
        do {
            if supplied == nil && Launch.isTesting && Launch.arguments.contains("-reset") &&
                files.fileExists(atPath: workspace.root.path) {
                try files.removeItem(at: workspace.root)
            }
            try workspace.prepare()
            workspaceReady = true
            draft = try workspace.loadDraft()
            let preferences = workspace.root.appendingPathComponent("layout.json")
            if let data = try? Data(contentsOf: preferences),
               let layout = try? JSONDecoder().decode(Layout.self, from: data), layout.isValid {
                defaults = layout
            }
            if let data = try? Data(contentsOf: workspace.progressURL) {
                history = try JSONDecoder().decode(History.self, from: data)
                if var recent = history.recent,
                   UUID(uuidString: recent.url.deletingLastPathComponent().lastPathComponent) != nil {
                    recent.url = workspace.output
                        .appendingPathComponent(recent.url.deletingLastPathComponent().lastPathComponent)
                        .appendingPathComponent(recent.url.lastPathComponent)
                    if files.fileExists(atPath: recent.url.path) {
                        finished = recent
                        history.recent = recent
                    } else { history.recent = nil }
                } else {
                    history.recent = nil
                }
            }
            workspace.pruneImages(keeping: Set(draft?.shots.map(\.id) ?? []))
            pruneOutput(keeping: finished)
            cleanTransferFiles()
        } catch {
            problem = ShotError.disk(error).localizedDescription
        }
        do {
            if let loadEntitlement {
                entitlement = try loadEntitlement()
            } else if Launch.isTesting || Launch.hostedTests {
                let start = clock()
                let expired = Launch.arguments.contains("-expired")
                entitlement = Entitlement(firstOpen: expired ? start.addingTimeInterval(-31 * 86_400) : start)
            } else {
                entitlement = try keychain.load(clock: clock)
            }
        } catch {
            problem = ShotError.disk(error).localizedDescription
        }
        now = clock()
        if Launch.arguments.contains("-paywall") { screen = .settings }
    }

    var hasPro: Bool { entitlement?.hasPro(at: now) ?? Launch.freePeriod }
    var layout: Layout { draft?.layout ?? defaults }
    var canUndo: Bool { undoDraft != nil }
    var canRetryImport: Bool {
        !pendingNew.isEmpty || draft?.shots.contains(where: { !$0.available && failedSources[$0.id] != nil }) == true
    }
    var canRetryRender: Bool { retryRender != nil }
    var busy: Bool { importing || rendering }
    var hasMissing: Bool { draft?.shots.contains(where: { !$0.available }) == true }
    var overLimit: Bool { !hasPro && (draft?.shots.count ?? 0) > 10 }
    var longCount: Int {
        let layout = layout.effective(pro: hasPro)
        return draft?.shots.filter { PagePlan.isLong($0, layout: layout, pro: hasPro) }.count ?? 0
    }

    func begin() async {
        refreshClock()
        await purchases.start { [weak self] transaction in try self?.accept(transaction) }
    }

    func refreshClock() {
        let before = hasPro
        now = clock()
        if before != hasPro {
            invalidatePreview()
            if screen == .split { screen = .batch }
        }
        expiryTask?.cancel()
        if let entitlement, !entitlement.purchasedPro, entitlement.hasPro(at: now, free: false) {
            let seconds = entitlement.trialEnd.timeIntervalSince(now)
            expiryTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(seconds + 0.1))
                    self?.refreshClock()
                } catch {}
            }
        }
    }

    func accept(_ transaction: StoreKit.Transaction) throws {
        guard transaction.productID == Launch.proID, var value = entitlement else { throw ShotError.store }
        let before = hasPro
        value.purchasedPro = transaction.revocationDate == nil
        try keychain.save(value)
        entitlement = value
        refreshClock()
        if before != hasPro {
            invalidatePreview()
            if screen == .split { screen = .batch }
        }
    }

    @discardableResult
    func updateLayout(_ value: Layout, applyToDraft: Bool) -> Bool {
        guard value.isValid else { return false }
        if applyToDraft, var edit = draft {
            if edit.layout.margin != value.margin || edit.layout.numbers != value.numbers || edit.layout.date != value.date {
                edit.cuts = [:]
            }
            edit.layout = value
            guard commit(edit) else { return false }
        }
        do {
            let url = workspace.root.appendingPathComponent("layout.json")
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            defaults = value
            return true
        } catch { problem = ShotError.disk(error).localizedDescription; return false }
    }

    @discardableResult
    private func commit(_ next: Draft?, undoable: Bool = false) -> Bool {
        guard workspaceReady else { problem = L.t("error.storage"); return false }
        do {
            try workspace.save(next)
            if undoable { undoDraft = draft }
            draft = next
            invalidatePreview()
            return true
        } catch {
            problem = ShotError.disk(error).localizedDescription
            return false
        }
    }

    private func invalidatePreview() {
        if let preview, preview.url != finished?.url {
            try? FileManager.default.removeItem(at: preview.url.deletingLastPathComponent())
        }
        preview = nil
        cachedRequest = nil
    }

    func order(_ order: ShotOrder) {
        guard !rendering, var draft, draft.order != order else { return }
        draft.sort(order)
        commit(draft, undoable: true)
    }

    func move(_ id: UUID, to index: Int) {
        guard !rendering, var draft else { return }
        let old = draft
        draft.move(id, to: index)
        if old != draft { commit(draft, undoable: true) }
    }

    func remove(_ id: UUID) {
        guard !busy, var draft else { return }
        draft.shots.removeAll { $0.id == id }
        draft.cuts[id] = nil
        if commit(draft, undoable: true) { notice = L.t("notice.removed") }
    }

    func removeMissing() {
        guard !busy, var draft else { return }
        let ids = draft.shots.filter { !$0.available }.map(\.id)
        draft.shots.removeAll { !$0.available }
        for id in ids { draft.cuts[id] = nil }
        if commit(draft, undoable: true) { notice = L.t("notice.removed") }
    }

    func clearDraft() {
        guard !busy, draft != nil else { return }
        if commit(nil, undoable: true) { notice = L.t("notice.deleted") }
    }

    func undo() {
        guard !busy, var restore = undoDraft else { return }
        let current = Dictionary(uniqueKeysWithValues: (draft?.shots ?? []).map { ($0.id, $0) })
        restore.shots = restore.shots.map { current[$0.id] ?? $0 }
        if commit(restore) {
            undoDraft = nil
            notice = L.t("notice.undone")
        }
    }

    func updateQuality(_ value: PDFQuality) {
        guard var draft, draft.quality != value else { return }
        draft.quality = value
        commit(draft)
    }

    func updateCuts(_ value: [Int: Int], for id: UUID) -> Bool {
        guard hasPro, var draft else { return false }
        draft.cuts[id] = value.isEmpty ? nil : value
        return commit(draft, undoable: true)
    }

    func ingest(_ sources: [ImportSource], mode: PickMode) async {
        guard !sources.isEmpty, !busy, workspaceReady else { return }
        problem = nil
        notice = nil
        switch mode {
        case .new:
            pendingNew = sources.enumerated().map { (Shot(selected: $0.offset, issue: .unavailable), $0.element) }
            await importQueue(pendingNew, new: true)
        case .append:
            guard var edit = draft else { return }
            let offset = (edit.shots.map(\.selected).max() ?? -1) + 1
            let tasks = sources.enumerated().map { (Shot(selected: offset + $0.offset, issue: .unavailable), $0.element) }
            edit.shots += tasks.map { $0.0 }
            undoDraft = nil
            guard commit(edit) else { return }
            await importQueue(tasks, new: false)
        case .replace(let id):
            guard let shot = draft?.shots.first(where: { $0.id == id && !$0.available }),
                  let replacement = sources.first else { return }
            undoDraft = nil
            await importQueue([(shot, replacement)], new: false)
        }
    }

    func retryImports() async {
        guard !busy else { return }
        problem = nil
        if !pendingNew.isEmpty {
            await importQueue(pendingNew, new: true)
        } else if let draft {
            let queue = draft.shots.compactMap { shot -> (Shot, ImportSource)? in
                guard !shot.available, let source = failedSources[shot.id] else { return nil }
                return (shot, source)
            }
            await importQueue(queue, new: false)
        }
    }

    private func importQueue(_ queue: [(Shot, ImportSource)], new: Bool) async {
        guard !queue.isEmpty else { return }
        importing = true
        defer { importing = false }
        var started = !new
        var pending: [Shot] = []
        let workspace = self.workspace
        let lookup = Dictionary(uniqueKeysWithValues: queue.map { ($0.0.id, $0.1) })
        await withTaskGroup(of: Shot.self) { group in
            var iterator = queue.makeIterator()
            for _ in 0..<3 {
                guard let (shot, source) = iterator.next() else { break }
                group.addTask { await source.load(for: shot, workspace: workspace) }
            }
            while let result = await group.next() {
                if let (shot, source) = iterator.next() {
                    group.addTask { await source.load(for: shot, workspace: workspace) }
                }
                pending.append(result)
                if !started && result.available {
                    var edit = Draft(shots: queue.map { $0.0 }, layout: defaults)
                    apply(pending, to: &edit)
                    if commit(edit) {
                        undoDraft = nil
                        failedSources = lookup
                        pendingNew = []
                        screen = .batch
                        started = true
                        pending = []
                        for shot in edit.shots where shot.available { failedSources[shot.id] = nil }
                    }
                } else if started && pending.count >= 6 {
                    if install(pending, lookup: lookup) { pending = [] }
                }
            }
        }
        if started {
            if !pending.isEmpty { _ = install(pending, lookup: lookup) }
            if problem == nil {
                workspace.pruneImages(keeping: Set((draft?.shots ?? []).map(\.id) + (undoDraft?.shots ?? []).map(\.id)))
            }
        } else if problem == nil {
            problem = (pending.contains { $0.issue == .noSpace } ? ShotError.noSpace : .missing).localizedDescription
        }
    }

    private func apply(_ results: [Shot], to draft: inout Draft) {
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        draft.shots = draft.shots.map { byID[$0.id] ?? $0 }
        draft.sort(draft.order)
    }

    private func install(_ results: [Shot], lookup: [UUID: ImportSource]) -> Bool {
        guard var edit = draft else { return false }
        apply(results, to: &edit)
        guard commit(edit) else { return false }
        for shot in results { failedSources[shot.id] = shot.available ? nil : lookup[shot.id] }
        return true
    }

    func render(openPreview: Bool, firstTen: Bool = false) async {
        guard !busy, let draft else { return }
        refreshClock()
        problem = nil
        notice = nil
        retryRender = (openPreview, firstTen)
        self.firstTen = firstTen
        do {
            let shots = try draft.exportShots(pro: hasPro, firstTen: firstTen)
            if openPreview { screen = .preview }
            let day = screen == .preview ? cachedRequest?.localDay : nil
            let request = RenderRequest(shots: shots, layout: draft.layout.effective(pro: hasPro),
                                        quality: draft.quality, cuts: draft.cuts, pro: hasPro,
                                        localDay: day ?? Calendar.current.startOfDay(for: now))
            rendering = true
            defer { rendering = false; renderTask = nil }
            let result: PDFResult
            if let preview, cachedRequest == request {
                result = preview
            } else {
                invalidatePreview()
                let workspace = self.workspace
                let worker = Task.detached(priority: .userInitiated) {
                    try PDFExport.make(request, workspace: workspace)
                }
                renderTask = worker
                result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                refreshClock()
                guard !worker.isCancelled, !Task.isCancelled, request.pro == hasPro else {
                    try? FileManager.default.removeItem(at: result.url.deletingLastPathComponent())
                    if request.pro != hasPro { throw ShotError.freeLimit }
                    throw CancellationError()
                }
                preview = result
                cachedRequest = request
                page = min(max(1, page), result.pageCount)
            }
            if !openPreview { try finish(result) }
            retryRender = nil
        } catch is CancellationError {
            retryRender = nil
        } catch {
            problem = ShotError.disk(error).localizedDescription
        }
    }

    func cancelRender() { renderTask?.cancel() }

    func retryPDF() async {
        guard let retryRender else { return }
        await render(openPreview: retryRender.preview, firstTen: retryRender.firstTen)
    }

    private func finish(_ result: PDFResult) throws {
        var next = history
        next.progress.recordExport(at: now)
        if result.sourceCount >= 50 && !next.progress.earnedMilestone {
            next.progress.earnedMilestone = true
            next.milestonePending = true
        } else { next.milestonePending = false }
        next.recent = result
        try persist(next)
        finished = result
        pruneOutput(keeping: result)
        screen = .finished
        reviewCandidate = true
    }

    func rename(_ input: String) -> Bool {
        guard let result = finished, let name = PDFExport.name(input) else {
            problem = L.t("error.name")
            return false
        }
        guard name != result.url.lastPathComponent else { return true }
        let directory = result.url.deletingLastPathComponent()
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: result.url, to: url)
            let renamed = PDFResult(url: url, pageCount: result.pageCount, byteCount: result.byteCount,
                                    sourceCount: result.sourceCount, splits: result.splits)
            var next = history
            next.recent = renamed
            do { try persist(next) }
            catch {
                try? FileManager.default.moveItem(at: url, to: result.url)
                throw error
            }
            if preview?.url == result.url { preview = renamed }
            finished = renamed
            problem = nil
            return true
        } catch {
            problem = ShotError.disk(error).localizedDescription
            return false
        }
    }

    func dismissMilestone() {
        guard history.milestonePending else { return }
        var next = history
        next.milestonePending = false
        do { try persist(next) }
        catch { problem = ShotError.disk(error).localizedDescription }
    }

    private func persist(_ next: History) throws {
        try JSONEncoder().encode(next).write(to: workspace.progressURL, options: .atomic)
        history = next
    }

    func takeReviewRequest() -> Bool {
        guard !Launch.isTesting, reviewCandidate, screen == .home, !busy,
              problem == nil, !history.milestonePending else { return false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard history.progress.eligible(version: version) else { return false }
        var next = history
        next.progress.markRequested(version: version)
        do {
            try persist(next)
            reviewCandidate = false
            return true
        } catch { return false }
    }

    private func pruneOutput(keeping result: PDFResult?) {
        let files = FileManager.default
        let keep = result?.url.deletingLastPathComponent().lastPathComponent
        for url in (try? files.contentsOfDirectory(at: workspace.output, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: url.lastPathComponent) != nil && url.lastPathComponent != keep {
                try? files.removeItem(at: url)
            }
        }
    }

    private func cleanTransferFiles() {
        let files = FileManager.default
        for url in (try? files.contentsOfDirectory(at: files.temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] {
            if url.lastPathComponent.hasPrefix("ShotImport-") || url.lastPathComponent.hasPrefix("ShotShare-") {
                try? files.removeItem(at: url)
            }
        }
    }
}
