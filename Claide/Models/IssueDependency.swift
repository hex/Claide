// ABOUTME: Edge model for a dependency relationship between two beads issues.
// ABOUTME: Decoded from the `dependencies` array within each issue's JSON.

struct IssueDependency: Codable, Sendable {
    let issueID: String
    let dependsOnID: String
    let type: String
    let createdAt: String
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case type
        case issueID = "issue_id"
        case dependsOnID = "depends_on_id"
        case createdAt = "created_at"
        case createdBy = "created_by"
    }
}
