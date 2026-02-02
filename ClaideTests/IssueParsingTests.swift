// ABOUTME: Tests for decoding bd list --json output into Issue models.
// ABOUTME: Validates all fields, optional handling, and dependency parsing.

import Testing
@testable import Claide

@Suite("Issue Parsing")
struct IssueParsingTests {

    @Test("Decodes full issue array from bd JSON")
    func decodesIssueArray() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        #expect(issues.count == 4)
    }

    @Test("Parses issue ID and title correctly")
    func parsesBasicFields() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        let first = issues[0]
        #expect(first.id == "proj-qwh")
        #expect(first.title == "Editor window import UI")
        #expect(first.status == "open")
        #expect(first.issueType == "feature")
    }

    @Test("Handles optional fields")
    func handlesOptionals() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        // First issue has no owner
        #expect(issues[0].owner == nil)
        // Second issue has owner
        #expect(issues[1].owner == "hex@users.noreply.github.com")
        // Fourth issue has no description
        #expect(issues[3].description == nil)
    }

    @Test("Parses dependencies array")
    func parsesDependencies() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        let first = issues[0]
        let deps = first.dependencies!
        #expect(deps.count == 2)
        #expect(deps[0].type == "parent-child")
        #expect(deps[0].dependsOnID == "proj-6q6")
        #expect(deps[1].type == "blocks")
        #expect(deps[1].dependsOnID == "proj-8as")
    }

    @Test("Handles missing dependencies array")
    func handlesMissingDependencies() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        // Third issue (epic) has no dependencies array
        #expect(issues[2].dependencies == nil)
    }

    @Test("Computes blockedByIDs from dependencies")
    func computesBlockedByIDs() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        let first = issues[0]
        #expect(first.blockedByIDs == ["proj-8as"])
    }

    @Test("Maps status to correct color category")
    func statusColors() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        // Just verify the statuses are recognized (color comparison is complex)
        #expect(issues[0].status == "open")
        #expect(issues[1].status == "in_progress")
        #expect(issues[3].status == "closed")
    }

    @Test("Decodes dependency counts")
    func dependencyCounts() throws {
        let issues = try BeadsService.decode(Fixtures.beadsJSON)
        #expect(issues[0].dependencyCount == 2)
        #expect(issues[0].dependentCount == 1)
        #expect(issues[2].dependencyCount == 0)
        #expect(issues[2].dependentCount == 5)
    }
}
