import SwiftUI
import UIKit

struct Activity: Identifiable {
    let id = UUID()
    let url: URL
    var caption: String?
}

struct ActivitySheet: UIViewControllerRepresentable {
    let activity: Activity

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [activity.url]
        if let caption = activity.caption { items.append(caption) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FinishedScreen: View {
    @EnvironmentObject private var model: AppModel
    let edit: () -> Void
    let home: () -> Void
    let next: () -> Void
    let rename: () -> Void
    let share: (Activity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: L.t("finished.title"), id: "finished", back: home) {
                        Button(action: edit) {
                            Text(L.t("finished.edit")).font(.caption.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("finished.edit")
                    }
                    if let result = model.finished {
                        details(result)
                        PrimaryButton(title: L.t("finished.sharePDF"), symbol: "square.and.arrow.up", id: "finished.sharePDF") {
                            share(Activity(url: result.url))
                        }
                        cardSection(CardContent(images: result.sourceCount, pages: result.pageCount))
                        if model.history.milestonePending {
                            cardSection(CardContent(images: result.sourceCount, pages: result.pageCount, milestone: true))
                        }
                    }
                    if model.canRetryImport {
                        PrimaryButton(title: L.t("import.retry"), symbol: "arrow.clockwise", id: "finished.retry", kind: .secondary) {
                            Task { await model.retryImports() }
                        }.disabled(model.busy)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            VStack(spacing: 4) {
                if model.importing { ProgressView(L.t("import.loading")).font(.caption) }
                PrimaryButton(title: L.t("finished.next"), symbol: "plus", id: "finished.next", kind: .white, action: next)
                    .disabled(model.busy)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func details(_ result: PDFResult) -> some View {
        HStack(spacing: 8) {
            IconBox(symbol: "checkmark", tone: .green)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.url.lastPathComponent).font(.subheadline.weight(.semibold))
                    .lineLimit(2).accessibilityIdentifier("finished.file")
                HStack(spacing: 6) {
                    Text(L.f("finished.details", result.pageCount, result.size)).font(.caption)
                        .foregroundStyle(Theme.muted).accessibilityIdentifier("finished.size")
                    StatusPill(title: L.t("finished.ready"), tone: .green)
                }
            }
            Spacer(minLength: 0)
            Button(action: rename) {
                Image(systemName: "pencil").foregroundStyle(Theme.accent).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(L.t("finished.rename")).accessibilityIdentifier("finished.rename")
        }
        .padding(12).panel()
    }

    private func cardSection(_ content: CardContent) -> some View {
        let id = content.milestone ? "milestone" : "card"
        return VStack(alignment: .leading, spacing: 9) {
            Text(L.t(content.milestone ? "share.achievement" : "share.title"))
                .font(.headline).accessibilityIdentifier("finished." + id)
            ShareArtwork(content: content)
                .frame(minHeight: content.milestone ? 240 : 218)
                .fixedSize(horizontal: false, vertical: true)
            if !content.milestone {
                Text(L.t("share.privacy")).font(.caption).foregroundStyle(Theme.muted)
            }
            PrimaryButton(title: L.t("share.action"), symbol: "photo", id: "finished." + id + ".share", kind: .secondary) {
                do { share(Activity(url: try content.write(), caption: CardContent.tags)) }
                catch { model.problem = ShotError.disk(error).localizedDescription }
            }
            if !content.milestone {
                Button {
                    UIPasteboard.general.string = CardContent.tags
                    model.notice = L.t("notice.copied")
                } label: {
                    Text(L.t("share.copyTags")).font(.caption.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("finished.copyTags")
            }
        }
    }
}
