import SwiftUI

struct BatchScreen: View {
    @EnvironmentObject private var model: AppModel
    let back: () -> Void
    let append: () -> Void
    let appendOther: () -> Void
    let replace: (UUID) -> Void
    let layout: () -> Void
    let upgrade: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: L.t("batch.title"), id: "batch", back: back) {
                        Button(action: append) {
                            Label(L.t("batch.add"), systemImage: "plus").font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("batch.add").disabled(model.busy)
                        Menu {
                            Button(action: appendOther) { Label(L.t("home.other"), systemImage: "photo") }
                                .accessibilityIdentifier("batch.addOther")
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 34, height: 44)
                        }
                        .accessibilityLabel(L.t("batch.more")).accessibilityIdentifier("batch.more").disabled(model.busy)
                    }
                    if let draft = model.draft {
                        summary(draft)
                        warnings
                        if !draft.shots.isEmpty {
                            Text(L.t("batch.drag")).font(.caption).foregroundStyle(Theme.muted)
                            LazyVStack(spacing: 0) {
                                ForEach(Array(draft.shots.enumerated()), id: \.element.id) { index, shot in
                                    ShotRow(shot: shot, index: index, count: draft.shots.count,
                                            replace: { replace(shot.id) })
                                    if index != draft.shots.count - 1 { Divider().overlay(Theme.line) }
                                }
                            }
                            .panel()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            footer
        }
    }

    private func summary(_ draft: Draft) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(draft.shots.count, format: .number)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .accessibilityIdentifier("batch.count")
                    Text(L.t("batch.selected")).font(.caption.weight(.semibold))
                }
                if model.longCount > 0 {
                    Text(L.f("batch.longCount", model.longCount)).font(.caption).foregroundStyle(Theme.muted)
                }
                if model.importing {
                    ProgressView(L.t("import.loading")).font(.caption).accessibilityIdentifier("batch.loading")
                }
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(ShotOrder.allCases.filter { $0 != .manual }, id: \.self) { order in
                    Button {
                        model.order(order)
                    } label: {
                        if order == draft.order { Label(order.title, systemImage: "checkmark") }
                        else { Text(order.title) }
                    }
                    .accessibilityIdentifier("sort." + order.rawValue)
                }
            } label: {
                Label(draft.order.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(Theme.blueWash, in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityIdentifier("batch.sort").disabled(model.rendering)
        }
        .padding(14).panel()
    }

    @ViewBuilder private var warnings: some View {
        if model.hasMissing && !model.importing {
            Callout(text: L.t("error.missing"))
            HStack(spacing: 8) {
                if model.canRetryImport {
                    PrimaryButton(title: L.t("import.retry"), symbol: "arrow.clockwise", id: "batch.retryImages", kind: .secondary) {
                        Task { await model.retryImports() }
                    }.disabled(model.busy)
                }
                PrimaryButton(title: L.t("import.exclude"), symbol: "minus.circle", id: "batch.exclude", kind: .secondary) {
                    model.removeMissing()
                }.disabled(model.busy)
            }
        }
        if model.overLimit {
            Callout(text: L.t("error.freeLimit"))
            PrimaryButton(title: L.t("purchase.view"), symbol: "lock.open", id: "batch.upgrade", kind: .secondary, action: upgrade)
        } else if !model.hasPro && model.longCount > 0 {
            Callout(text: L.t("batch.longFree"))
        }
        if [.four, .six].contains(model.layout.grid) {
            Callout(text: L.t("layout.small"))
            PrimaryButton(title: L.t("layout.useOne"), symbol: "rectangle.portrait", id: "batch.useOne", kind: .secondary) {
                var value = model.layout
                value.grid = .one
                model.updateLayout(value, applyToDraft: true)
            }.disabled(model.busy)
        }
        if model.canUndo {
            Button { model.undo() } label: {
                Text(L.t("action.undo")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("batch.undo").disabled(model.busy)
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            if model.rendering {
                HStack {
                    ProgressView(L.t("pdf.rendering")).accessibilityIdentifier("batch.rendering")
                    Spacer()
                    Button { model.cancelRender() } label: {
                        Text(L.t("action.cancel")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("batch.cancelRender")
                }
            } else if model.canRetryRender && model.problem != nil {
                PrimaryButton(title: L.t("action.retry"), symbol: "arrow.clockwise", id: "batch.retryPDF", kind: .secondary) {
                    Task { await model.retryPDF() }
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(title: L.t("layout.title"), symbol: "square.grid.2x2", id: "batch.layout", kind: .secondary, action: layout)
                    .disabled(model.busy)
                PrimaryButton(title: model.overLimit ? L.t("batch.previewTen") : L.t("preview.short"),
                              symbol: "eye", id: "batch.preview", kind: .secondary) {
                    Task { await model.render(openPreview: true, firstTen: model.overLimit) }
                }.disabled(model.busy || model.draft?.shots.isEmpty != false)
            }
            PrimaryButton(title: model.overLimit ? L.t("batch.firstTen") : L.t("pdf.export"),
                          symbol: "arrow.down.to.line", id: model.overLimit ? "batch.firstTen" : "batch.export") {
                Task { await model.render(openPreview: false, firstTen: model.overLimit) }
            }.disabled(model.busy || model.draft?.shots.isEmpty != false)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.background)
    }
}

private struct ShotRow: View {
    @EnvironmentObject private var model: AppModel
    let shot: Shot
    let index: Int
    let count: Int
    let replace: () -> Void
    @State private var targeted = false

    private var title: String { L.f("batch.image", shot.selected + 1) }
    private var number: String { String(format: "%02d", index + 1) }
    private var date: String { shot.taken.map(L.timestamp) ?? L.t("batch.noDate") }
    private var isLong: Bool { PagePlan.isLong(shot, layout: model.layout.effective(pro: model.hasPro), pro: model.hasPro) }

    var body: some View {
        HStack(spacing: 10) {
            Text(number).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted).frame(minWidth: 22)
                .accessibilityHidden(true)
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("shot.title.\(index)")
                    if isLong { StatusPill(title: L.t("batch.long"), tone: .amber) }
                }
                Text(detail).font(.caption2).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Menu {
                if !shot.available {
                    Button(action: replace) { Label(L.t("import.replace"), systemImage: "photo") }
                        .accessibilityIdentifier("shot.replace.\(index)")
                }
                Button { model.move(shot.id, to: 0) } label: {
                    Label(L.t("sort.first"), systemImage: "arrow.up.to.line")
                }
                    .accessibilityIdentifier("shot.first.\(index)").disabled(index == 0)
                Button { model.move(shot.id, to: index - 1) } label: {
                    Label(L.t("sort.up"), systemImage: "arrow.up")
                }
                    .accessibilityIdentifier("shot.up.\(index)").disabled(index == 0)
                Button { model.move(shot.id, to: index + 1) } label: {
                    Label(L.t("sort.down"), systemImage: "arrow.down")
                }
                    .accessibilityIdentifier("shot.down.\(index)").disabled(index + 1 >= count)
                Button { model.move(shot.id, to: count - 1) } label: {
                    Label(L.t("sort.last"), systemImage: "arrow.down.to.line")
                }
                    .accessibilityIdentifier("shot.last.\(index)").disabled(index + 1 >= count)
                Button(role: .destructive) { model.remove(shot.id) } label: {
                    Label(L.t("action.remove"), systemImage: "minus.circle")
                }
                    .accessibilityIdentifier("shot.remove.\(index)").disabled(model.busy)
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(L.t("batch.more")).accessibilityIdentifier("shot.menu.\(index)")
            .disabled(model.rendering)
            if !model.rendering {
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .draggable(shot.id.uuidString)
                    .accessibilityIdentifier("shot.drag.\(index)")
                    .accessibilityLabel(L.t("batch.dragHandle"))
                    .accessibilityAction(named: Text(L.t("sort.up"))) { model.move(shot.id, to: index - 1) }
                    .accessibilityAction(named: Text(L.t("sort.down"))) { model.move(shot.id, to: index + 1) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 61).background(targeted ? Theme.blueWash : .clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            guard !model.rendering, let text = values.first, let id = UUID(uuidString: text),
                  model.draft?.shots.contains(where: { $0.id == id }) == true else { return false }
            model.move(id, to: index)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var detail: String {
        if shot.available { return date }
        if model.importing { return L.t("import.loading") }
        return shot.issue?.title ?? L.t("import.unavailable")
    }

    @ViewBuilder private var thumbnail: some View {
        if shot.available, let image = UIImage(contentsOfFile: model.workspace.thumb(shot.id).path) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 11)).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            IconBox(symbol: model.importing ? "photo" : "exclamationmark", tone: .amber)
        }
    }
}

struct LayoutScreen: View {
    @EnvironmentObject private var model: AppModel
    let applyToDraft: Bool
    let back: () -> Void
    let showMargin: () -> Void
    let upgrade: () -> Void

    private var value: Layout { applyToDraft ? model.layout : model.defaults }
    private var effective: Layout { value.effective(pro: model.hasPro) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: L.t("layout.title"), id: "layout", back: back) {
                    StatusPill(title: L.t("layout.a4"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("layout.count")).font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Grid.allCases, id: \.self) { grid in gridButton(grid) }
                    }
                }
                VStack(spacing: 0) {
                    layoutToggle(key: "layout.numbers", symbol: "number", tone: .amber, path: \.numbers)
                    Divider().overlay(Theme.line)
                    layoutToggle(key: "layout.date", symbol: "calendar", subtitle: L.t("layout.dateDetail"), path: \.date)
                    Divider().overlay(Theme.line)
                    RowButton(title: L.t("layout.margin"), symbol: "viewfinder", id: "layout.margin", tone: .green,
                              value: model.hasPro ? L.f("layout.mm", effective.margin) : L.t("purchase.locked"),
                              action: model.hasPro ? showMargin : upgrade)
                    Divider().overlay(Theme.line)
                    layoutToggle(key: "layout.split", symbol: "scissors", path: \.splitLong)
                }.panel()
                Text(L.t("layout.tip")).font(.caption).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        }
    }

    private func gridButton(_ grid: Grid) -> some View {
        Button {
            var next = value
            next.grid = grid
            if model.updateLayout(next, applyToDraft: applyToDraft) { back() }
        } label: {
            VStack(spacing: 7) {
                GridPaper(grid: grid, selected: grid == value.grid)
                Text(L.f("layout.images", grid.rawValue)).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 109)
            .foregroundStyle(grid == value.grid ? Theme.accent : Theme.ink)
            .panel(grid == value.grid ? Theme.blueWash : .white, radius: 16, shadow: false)
            .overlay {
                if grid == value.grid {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, lineWidth: 2).allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("layout.grid.\(grid.rawValue)")
        .accessibilityAddTraits(grid == value.grid ? .isSelected : [])
    }

    @ViewBuilder private func layoutToggle(key: String, symbol: String, tone: Tone = .blue,
                                           subtitle: String? = nil, path: WritableKeyPath<Layout, Bool>) -> some View {
        if model.hasPro {
            Toggle(isOn: Binding(get: { value[keyPath: path] }, set: { enabled in
                var next = value
                next[keyPath: path] = enabled
                model.updateLayout(next, applyToDraft: applyToDraft)
            })) {
                IconRow(title: L.t(key), symbol: symbol, tone: tone, subtitle: subtitle)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).accessibilityIdentifier(key)
        } else {
            RowButton(title: L.t(key), symbol: symbol, id: key, tone: tone, value: L.t("purchase.locked"), action: upgrade)
        }
    }
}

struct GridPaper: View {
    let grid: Grid
    let selected: Bool
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<grid.rows, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<grid.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(selected ? Theme.accent : Theme.accent.opacity(0.24))
                    }
                }
            }
        }
        .padding(5).frame(width: 40, height: 56).panel(radius: 4, shadow: false).accessibilityHidden(true)
    }
}
