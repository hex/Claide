// ABOUTME: Test fixture data for beads JSON parsing and layout tests.
// ABOUTME: Contains sample bd list --json output captured from a real project.

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
}
