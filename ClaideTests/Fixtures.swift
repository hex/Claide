// ABOUTME: Test fixture data for beads JSON, changes.md, and JSONL transcript parsing.
// ABOUTME: Contains sample data captured from real projects and sessions.

import Foundation

enum Fixtures {
    static let beadsJSON = """
    [
      {
        "id": "proj-qwh",
        "title": "Editor window import UI",
        "description": "Editor window with import button and progress bar",
        "status": "open",
        "priority": 0,
        "issue_type": "feature",
        "created_at": "2026-01-31T14:52:09.546661+02:00",
        "updated_at": "2026-01-31T14:52:17.615274+02:00",
        "dependencies": [
          {
            "issue_id": "proj-qwh",
            "depends_on_id": "proj-6q6",
            "type": "parent-child",
            "created_at": "2026-01-31T14:52:17.615752+02:00",
            "created_by": "hex"
          },
          {
            "issue_id": "proj-qwh",
            "depends_on_id": "proj-8as",
            "type": "blocks",
            "created_at": "2026-01-31T14:52:46.558726+02:00",
            "created_by": "hex"
          }
        ],
        "dependency_count": 2,
        "dependent_count": 1
      },
      {
        "id": "proj-2di",
        "title": "Font resolution pipeline",
        "description": "Four-tier font resolution system",
        "status": "in_progress",
        "priority": 1,
        "issue_type": "feature",
        "owner": "hex@users.noreply.github.com",
        "created_at": "2026-01-31T14:52:09.546068+02:00",
        "created_by": "hex",
        "updated_at": "2026-01-31T14:52:17.505275+02:00",
        "dependencies": [
          {
            "issue_id": "proj-2di",
            "depends_on_id": "proj-6q6",
            "type": "parent-child",
            "created_at": "2026-01-31T14:52:17.505742+02:00",
            "created_by": "hex"
          }
        ],
        "dependency_count": 1,
        "dependent_count": 0
      },
      {
        "id": "proj-6q6",
        "title": "Phase 1: Core Import",
        "description": "Import a file and produce a working hierarchy",
        "status": "open",
        "priority": 0,
        "issue_type": "epic",
        "owner": "hex@users.noreply.github.com",
        "created_at": "2026-01-31T14:51:02.267004+02:00",
        "created_by": "hex",
        "updated_at": "2026-01-31T14:51:02.267004+02:00",
        "dependency_count": 0,
        "dependent_count": 5
      },
      {
        "id": "proj-8as",
        "title": "Settings panel",
        "status": "closed",
        "priority": 0,
        "issue_type": "feature",
        "created_at": "2026-01-31T14:52:09.547000+02:00",
        "updated_at": "2026-01-31T14:52:46.559000+02:00",
        "dependency_count": 0,
        "dependent_count": 1
      }
    ]
    """.data(using: .utf8)!

    static let changesMarkdown = """
    # Changes Log

    - [2026-01-31 23:33:01] Write: /Users/hex/project/src/main.swift
    - [2026-01-31 23:34:15] Edit: /Users/hex/project/src/utils.swift
    - [2026-01-31 23:36:24] Write: /Users/hex/project/README.md
    """

    /// JSONL transcript lines with tool_use entries for file operations
    static let transcriptJSONL: Data = {
        let lines = [
            // Write entry
            """
            {"type":"assistant","timestamp":"2026-02-06T10:30:01.000Z","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/Users/hex/project/src/main.swift","content":"import Foundation"}}]}}
            """,
            // Edit entry
            """
            {"type":"assistant","timestamp":"2026-02-06T10:31:15.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/hex/project/src/utils.swift","old_string":"foo","new_string":"bar"}}]}}
            """,
            // Read entry
            """
            {"type":"assistant","timestamp":"2026-02-06T10:32:00.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/Users/hex/project/README.md"}}]}}
            """,
            // Text-only entry (no tool_use)
            """
            {"type":"assistant","timestamp":"2026-02-06T10:33:00.000Z","message":{"content":[{"type":"text","text":"Here is the plan."}]}}
            """,
            // Bash tool (no file_path)
            """
            {"type":"assistant","timestamp":"2026-02-06T10:34:00.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}
            """,
            // User message (not assistant)
            """
            {"type":"user","timestamp":"2026-02-06T10:35:00.000Z","message":{"content":[{"type":"text","text":"Fix the bug"}]}}
            """,
            // MultiEdit entry
            """
            {"type":"assistant","timestamp":"2026-02-06T10:36:00.000Z","message":{"content":[{"type":"tool_use","name":"MultiEdit","input":{"file_path":"/Users/hex/project/src/views.swift","edits":[]}}]}}
            """,
            // tool_result (should be skipped)
            """
            {"type":"assistant","timestamp":"2026-02-06T10:37:00.000Z","message":{"content":[{"type":"tool_result","content":"OK"}]}}
            """
        ]
        return lines.joined(separator: "\n").data(using: .utf8)!
    }()

    /// Sample `git status --porcelain` output
    static let gitStatusPorcelain = """
     M src/main.swift
    M  src/staged.swift
    A  src/new.swift
    ?? untracked.txt
     D src/deleted.swift
    MM src/both.swift
    """
}
