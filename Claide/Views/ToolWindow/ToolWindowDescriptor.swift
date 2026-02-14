// ABOUTME: Defines the identity, edge placement, and metadata for dockable tool windows.
// ABOUTME: ToolWindowEdge, ToolWindowID, and ToolWindowDescriptor form the type-safe data model.

import Foundation
import CoreTransferable

/// Edge of the window where a tool panel can dock.
enum ToolWindowEdge: String, Codable, CaseIterable, Hashable {
    case left, right, bottom

    var isVertical: Bool { self == .left || self == .right }
}

/// Unique identifier for a tool window. Each registered panel has one.
struct ToolWindowID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let tasks = ToolWindowID(rawValue: "tasks")
    static let files = ToolWindowID(rawValue: "files")
}

extension ToolWindowID: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .text)
    }
}

/// Describes a registered tool window: its identity, display metadata, and default placement.
struct ToolWindowDescriptor {
    let id: ToolWindowID
    let title: String
    let icon: String
    let defaultEdge: ToolWindowEdge

    static let all: [ToolWindowDescriptor] = [
        ToolWindowDescriptor(id: .tasks, title: "Tasks", icon: "checklist", defaultEdge: .right),
        ToolWindowDescriptor(id: .files, title: "Files", icon: "doc.text", defaultEdge: .right),
    ]
}
