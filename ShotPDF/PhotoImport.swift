import CoreTransferable
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let files = FileManager.default
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ImageFiles.sourceByteLimit else { throw ShotError.tooLarge }
            let copy = files.temporaryDirectory.appendingPathComponent("ShotImport-" + UUID().uuidString)
            try files.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

enum ImportSource: Sendable {
    case photo(PhotosPickerItem)
    case example(Int)

    func load(for shot: Shot, workspace: Workspace) async -> Shot {
        do {
            switch self {
            case .example(let index):
                try Task.checkCancellation()
                let url = try SeedShots.make(index)
                defer { try? FileManager.default.removeItem(at: url) }
                return try ImageFiles.install(url, for: shot, workspace: workspace,
                                              photoDate: SeedShots.date(index))
            case .photo(let item):
                guard let file = try await item.loadTransferable(type: PickedFile.self) else { throw ShotError.missing }
                defer { try? FileManager.default.removeItem(at: file.url) }
                try Task.checkCancellation()
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                var date: Date? = nil
                if (status == .authorized || status == .limited), let id = item.itemIdentifier {
                    date = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.creationDate
                }
                return try ImageFiles.install(file.url, for: shot, workspace: workspace, photoDate: date)
            }
        } catch {
            var result = shot
            switch ShotError.disk(error) {
            case .unreadable, .tooLarge: result.issue = .unreadable
            case .noSpace: result.issue = .noSpace
            case .storage:
                result.issue = (error as NSError).domain == NSCocoaErrorDomain ? .storage : .unavailable
            default: result.issue = .unavailable
            }
            return result
        }
    }
}
