import Foundation
import SwiftData

@Model
final class RecentSearch {
    var id: UUID
    var query: String
    var searchedAt: Date

    init(query: String) {
        self.id = UUID()
        self.query = query
        self.searchedAt = Date()
    }
}
