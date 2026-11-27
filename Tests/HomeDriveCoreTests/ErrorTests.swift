import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct ErrorTests {
    @Test(arguments: [
        ("ssh: connect to host 10.77.0.1 port 22: Operation timed out", "WireGuard"),
        ("ssh: Could not resolve hostname foo.example.com: nodename nor servname provided", "resolved"),
        ("ssh: connect to host x port 22: Connection refused", "sshd"),
        ("me@x: Permission denied (publickey).", "key"),
        ("Host key verification failed.", "known_hosts"),
    ])
    func friendlyHints(raw: String, expected: String) {
        let message = HomeDriveError.connectionFailed(raw).errorDescription ?? ""
        #expect(message.contains(expected))
        #expect(message.contains(raw))
    }

    @Test func unknownErrorsPassThrough() {
        #expect(HomeDriveError.friendlySSHHint("weird") == "weird")
        #expect(HomeDriveError.commandFailed(status: 1, message: "").errorDescription == "The operation failed.")
    }
}
