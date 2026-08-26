import Foundation
import SwiftData

@Model
final class ScanFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortIndex: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \ScanDocument.folder)
    var documents: [ScanDocument] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}
