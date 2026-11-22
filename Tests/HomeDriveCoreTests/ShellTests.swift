import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct ShellTests {
    @Test func leavesSafeWordsAlone() {
        #expect(Shell.quote("abc-1.txt") == "abc-1.txt")
        #expect(Shell.quote("/home/me/docs") == "/home/me/docs")
    }

    @Test func quotesEverythingElse() {
        #expect(Shell.quote("") == "''")
        #expect(Shell.quote("a b") == "'a b'")
        #expect(Shell.quote("it's") == #"'it'\''s'"#)
        #expect(Shell.quote("$(rm -rf ~)") == "'$(rm -rf ~)'")
    }

    static let nastyNames = [
        "plain", "with space", "it's", #"double"quote"#, "$(whoami)", "`id`", "semi;colon",
        "back\\slash", "tab\there", "new\nline", "-leading-dash", "*glob?[x]", "ünïcødé 📁", "",
    ]

    /// The real proof: hand each argument to an actual /bin/sh and check it comes back unchanged.
    @Test(arguments: nastyNames)
    func roundTripsThroughARealShell(_ value: String) async throws {
        let line = Shell.script(#"printf '%s\0' "$@""#, arguments: [value, "second"])
        let result = try await ProcessRunner().run("/bin/sh", ["-c", line], stdin: nil)
        #expect(result.status == 0)
        let parts = result.stdout.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        #expect(parts == [value, "second", ""])
    }
}
