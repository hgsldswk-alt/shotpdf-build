import PDFKit
import SwiftUI

struct PreviewScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var document: PDFDocument?
    let back: () -> Void
    let adjust: (SplitRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: L.t("preview.title"), id: "preview", subtitle: subtitle, back: back) {
                        if let result = model.preview {
                            StatusPill(title: "\(model.page) / \(result.pageCount)", tone: .amber)
                        }
                    }
                    if let result = model.preview, let document {
                        PDFCanvas(document: document, page: $model.page)
                            .frame(height: 359).padding(12)
                            .panel(Theme.stage, shadow: false)
                            .accessibilityIdentifier("preview.document")
                        thumbnails(document: document, result: result)
                        splitButtons(result)
                        quality(result)
                    } else if model.rendering || model.preview != nil {
                        ProgressView(L.t("pdf.rendering")).frame(maxWidth: .infinity, minHeight: 160)
                            .accessibilityIdentifier("preview.rendering")
                    } else {
                        PrimaryButton(title: L.t("action.retry"), symbol: "arrow.clockwise", id: "preview.retry", kind: .secondary) {
                            Task { await model.render(openPreview: true, firstTen: model.firstTen) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 15)
            }
            VStack {
                if model.rendering {
                    PrimaryButton(title: L.t("action.cancel"), symbol: "xmark", id: "preview.cancel", kind: .secondary) {
                        model.cancelRender()
                    }
                } else {
                    PrimaryButton(title: L.t("pdf.export"), symbol: "arrow.down.to.line", id: "preview.export") {
                        Task { await model.render(openPreview: false, firstTen: model.firstTen) }
                    }.disabled(model.preview == nil)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .task(id: model.preview?.url) {
            document = model.preview.flatMap { PDFDocument(url: $0.url) }
            if model.preview != nil && document == nil { model.problem = L.t("error.pdf") }
        }
    }

    private var subtitle: String? {
        model.preview.map { L.f("preview.details", $0.sourceCount, $0.pageCount) }
    }

    private func thumbnails(document: PDFDocument, result: PDFResult) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(1...result.pageCount, id: \.self) { page in
                        Button { model.page = page } label: {
                            VStack(spacing: 3) {
                                PageThumbnail(document: document, page: page)
                                Text(page, format: .number).font(.caption2.monospacedDigit())
                            }
                            .frame(width: 70, height: 54)
                            .foregroundStyle(Theme.accent)
                            .panel(page == model.page ? Theme.blueWash : .white, radius: 10, shadow: false)
                        }
                        .buttonStyle(.plain).id(page)
                        .accessibilityLabel(L.f("preview.page", page)).accessibilityIdentifier("preview.page.\(page)")
                        .accessibilityAddTraits(page == model.page ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden).frame(height: 55)
            .onChange(of: model.page) { _, page in proxy.scrollTo(page, anchor: .center) }
        }
    }

    @ViewBuilder private func splitButtons(_ result: PDFResult) -> some View {
        if model.hasPro, let record = result.splits.first {
            if result.splits.count == 1 {
                PrimaryButton(title: L.f("preview.adjustPages", record.firstPage, record.lastPage),
                              symbol: "scissors", id: "preview.split", kind: .secondary) { adjust(record) }
            } else {
                Menu {
                    ForEach(result.splits) { entry in
                        Button(L.f("preview.pageRange", entry.firstPage, entry.lastPage)) { adjust(entry) }
                            .accessibilityIdentifier("preview.split.\(entry.firstPage)")
                    }
                } label: {
                    Label(L.t("split.title"), systemImage: "scissors").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Theme.accent).background(Theme.blueWash, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("preview.split")
            }
            if result.splits.contains(where: { $0.cuts.contains(where: { $0.overlap > 0 }) }) {
                Callout(text: L.t("split.check"))
            }
        }
    }

    private func quality(_ result: PDFResult) -> some View {
        HStack {
            Label(result.size, systemImage: "doc").font(.caption.weight(.semibold))
                .accessibilityIdentifier("preview.size")
            Spacer()
            Menu {
                ForEach(PDFQuality.allCases, id: \.self) { quality in
                    Button {
                        model.updateQuality(quality)
                        Task { await model.render(openPreview: true, firstTen: model.firstTen) }
                    } label: {
                        if model.draft?.quality == quality { Label(quality.title, systemImage: "checkmark") }
                        else { Text(quality.title) }
                    }
                    .accessibilityIdentifier("quality." + quality.rawValue)
                }
            } label: {
                Label((model.draft?.quality ?? .clear).title, systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
            }.accessibilityIdentifier("preview.quality")
        }
        .foregroundStyle(Theme.accent).padding(.horizontal, 7)
    }
}

private struct PageThumbnail: View {
    let document: PDFDocument
    let page: Int
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "doc.text") }
        }
        .frame(width: 23, height: 28).accessibilityHidden(true)
        .task(id: document.documentURL) {
            image = document.page(at: page - 1)?.thumbnail(of: CGSize(width: 50, height: 69), for: .mediaBox)
        }
    }
}

private struct PDFCanvas: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = UIColor(Theme.stage)
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.displaysPageBreaks = false
        view.autoScales = true
        view.maxScaleFactor = 6
        context.coordinator.connect(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.page = $page
        if view.document !== document {
            view.document = document
            view.autoScales = true
        }
        if let target = document.page(at: page - 1), view.currentPage !== target { view.go(to: target) }
    }

    @MainActor final class Coordinator: NSObject {
        var page: Binding<Int>
        init(page: Binding<Int>) { self.page = page }

        func connect(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)),
                                                   name: .PDFViewPageChanged, object: view)
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let current = view.currentPage, let document = view.document else { return }
            let index = document.index(for: current)
            guard index < document.pageCount else { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard view?.currentPage === current, let self, self.page.wrappedValue != index + 1 else { return }
                self.page.wrappedValue = index + 1
            }
        }
    }
}

private struct SplitInput: @unchecked Sendable {
    let raster: CGImage
    let ink: RowInk
}

struct SplitScreen: View {
    @EnvironmentObject private var model: AppModel
    let record: SplitRecord
    let back: () -> Void
    @State private var position = 0
    @State private var edits: [Int: Int] = [:]
    @State private var undo: [Int: Int]?
    @State private var input: SplitInput?
    @State private var loadFailed = false

    private var cuts: [PageCut] {
        guard let input else { return record.cuts }
        let layout = model.layout.effective(pro: true)
        let area = PagePlan.body(layout: layout, pro: true)
        let scale = CGFloat(record.shot.width) / area.width
        return LongPlan.make(height: record.shot.height, capacity: Int(area.height * scale),
                             overlap: Int(8 * PagePlan.pointsPerMM * scale), ink: input.ink,
                             overrides: edits).cuts
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ScreenHeader(title: L.t("split.title"), id: "split", back: back) { EmptyView() }
                    Callout(text: L.t("split.hint"))
                    if let input, let cut = cuts[safe: position] {
                        if cuts.count > 1 { cutPicker }
                        SplitCanvas(raster: input.raster, sourceHeight: record.shot.height,
                                    cut: cut, page: record.firstPage + position, update: update)
                        Text(L.t("split.drag")).font(.caption).foregroundStyle(Theme.muted)
                    } else if loadFailed {
                        Callout(text: L.t("error.unreadable"))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 270)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                if let undo {
                    PrimaryButton(title: L.t("action.undo"), symbol: "arrow.uturn.backward", id: "split.undo", kind: .secondary) {
                        edits = undo
                        self.undo = nil
                        position = min(position, max(0, cuts.count - 1))
                    }
                }
                PrimaryButton(title: L.t("split.auto"), symbol: "arrow.uturn.backward", id: "split.reset", kind: .secondary) {
                    undo = edits
                    edits = [:]
                    position = min(position, max(0, cuts.count - 1))
                }.disabled(edits.isEmpty)
                PrimaryButton(title: L.t("action.apply"), symbol: "checkmark", id: "split.apply") {
                    guard model.updateCuts(edits, for: record.id) else { return }
                    model.page = record.firstPage + position
                    model.screen = .preview
                    Task { await model.render(openPreview: true, firstTen: model.firstTen) }
                }.disabled(input == nil)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .task {
            edits = model.draft?.cuts[record.id] ?? [:]
            position = min(record.cuts.count - 1, max(0, model.page - record.firstPage))
            let url = model.workspace.source(record.id)
            let shot = record.shot
            do {
                input = try await Task.detached(priority: .userInitiated) {
                    let raster = try ImageFiles.renderImage(url, width: shot.width, height: shot.height, targetWidth: 450)
                    return try SplitInput(raster: raster, ink: RowInk(image: raster))
                }.value
            } catch { loadFailed = true }
        }
    }

    private var cutPicker: some View {
        Menu {
            ForEach(cuts) { cut in
                Button(L.f("split.break", cut.id + 1)) { position = cut.id }
                    .accessibilityIdentifier("split.break.\(cut.id)")
            }
        } label: {
            Label(L.f("split.break", position + 1), systemImage: "chevron.down")
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.accessibilityIdentifier("split.breaks")
    }

    private func update(_ value: Int) {
        undo = edits
        edits[position] = value
        position = min(position, max(0, cuts.count - 1))
    }
}

private struct SplitCanvas: View {
    let raster: CGImage
    let sourceHeight: Int
    let cut: PageCut
    let page: Int
    let update: (Int) -> Void
    @GestureState private var translation: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                StatusPill(title: L.f("preview.page", page), tone: .amber)
                Spacer()
                StatusPill(title: L.f("preview.page", page + 1), tone: .amber)
            }
            GeometryReader { proxy in
                let scale = proxy.size.width / CGFloat(raster.width)
                let factor = CGFloat(raster.height) / CGFloat(sourceHeight)
                let natural = proxy.size.height / 2
                let line = min(proxy.size.height - 23, max(23, natural + translation))
                ZStack(alignment: .topLeading) {
                    Color.white
                    Image(uiImage: UIImage(cgImage: raster)).resizable()
                        .frame(width: proxy.size.width, height: CGFloat(raster.height) * scale)
                        .offset(y: natural - CGFloat(cut.position) * factor * scale)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    HStack {
                        Text(L.t("split.here")).font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                    }
                    .foregroundStyle(Theme.amberInk).padding(.horizontal, 10).frame(height: 44)
                    .background(Theme.amberWash.opacity(0.96))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.amber).frame(height: 2)
                    }
                    .contentShape(Rectangle()).offset(y: line - 22)
                    .highPriorityGesture(DragGesture(minimumDistance: 0).updating($translation) { value, state, _ in
                        state = value.translation.height
                    }.onEnded { value in
                        apply(Int(value.translation.height / (factor * scale)))
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.t("split.here")).accessibilityIdentifier("split.handle")
                    .accessibilityValue("\(cut.position * 100 / sourceHeight)%")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: apply(max(1, sourceHeight / 100))
                        case .decrement: apply(-max(1, sourceHeight / 100))
                        @unknown default: break
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            }
            .frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(13).panel(Theme.stage, shadow: false)
    }

    private func apply(_ delta: Int) {
        let value = min(cut.maximum, max(cut.minimum, cut.position + delta))
        if value != cut.position { update(value) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
