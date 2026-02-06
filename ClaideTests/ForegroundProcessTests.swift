// ABOUTME: Tests for foreground process detection used by the tab bar process icon.
// ABOUTME: Verifies child process discovery via libproc APIs.

import Testing
import Foundation
@testable import Claide

@Suite("Foreground Process Detection")
struct ForegroundProcessTests {

    @Test("Resolves executable path for a known PID")
    func resolvesCurrentProcess() {
        let pid = getpid()
        let path = TerminalViewModel.executablePath(for: pid)
        #expect(path != nil)
    }

    @Test("Returns nil for invalid PID")
    func invalidPidReturnsNil() {
        let path = TerminalViewModel.executablePath(for: -1)
        #expect(path == nil)
    }

    @Test("Resolves spawned child executable path by PID")
    func resolvesChildByPid() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        defer { process.terminate() }

        try await Task.sleep(for: .milliseconds(100))

        let childPath = TerminalViewModel.executablePath(for: process.processIdentifier)
        #expect(childPath != nil)
        #expect(childPath?.hasSuffix("/sleep") == true)
    }

    @Test("Returns nil when parent has no children")
    func noChildrenReturnsNil() {
        let path = TerminalViewModel.foregroundChildExecutable(of: 99999)
        #expect(path == nil)
    }
}
