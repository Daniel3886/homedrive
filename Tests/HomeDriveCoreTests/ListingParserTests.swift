import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct ListingParserTests {
    private func data(_ records: [String]) -> Data {
        Data(records.map { $0 + "\0" }.joined().utf8)
    }

    @Test func parsesGNUFindOutput() {
        let out = data([
            "ff\t1234\t1700000000.5000000000\t644\treport.pdf",
            "dd\t4096\t1700000100.0000000000\t755\tDocuments",
            "ld\t9\t1700000200.0\t777\tlink-to-dir",
            "lN\t7\t1700000300.0\t777\tbroken-link",
            "ff\t1\t1700000400.0\t600\tname\twith\ttabs",
            "ff\t2\t1700000500.0\t600\tline\nbreak",
        ])
        let entries = ListingParser.parse(out, parent: "/home/me")
        #expect(entries.count == 6)

        #expect(entries[0].name == "report.pdf")
        #expect(entries[0].path == "/home/me/report.pdf")
        #expect(entries[0].kind == .file)
        #expect(entries[0].size == 1234)
        #expect(entries[0].modified == Date(timeIntervalSince1970: 1700000000.5))
        #expect(entries[0].permissions == "644")

        #expect(entries[1].kind == .directory)
        #expect(entries[1].isFolderLike)

        #expect(entries[2].kind == .symlink)
        #expect(entries[2].linkTarget == .directory)
        #expect(entries[2].isFolderLike)

        #expect(entries[3].kind == .symlink)
        #expect(entries[3].linkTarget == nil)
        #expect(!entries[3].isFolderLike)

        #expect(entries[4].name == "name\twith\ttabs")
        #expect(entries[5].name == "line\nbreak")
    }

    @Test func parsesBSDStatOutput() {
        let out = data([
            "Regular File\t10\t1700000000\t644\t/Users/me/tmp/a.txt",
            "Directory\t64\t1700000001\t755\t/Users/me/tmp/sub dir",
            "Symbolic Link\t5\t1700000002\t755\t/Users/me/tmp/ln",
        ])
        let entries = ListingParser.parse(out, parent: "/Users/me/tmp")
        #expect(entries.map(\.name) == ["a.txt", "sub dir", "ln"])
        #expect(entries.map(\.kind) == [.file, .directory, .symlink])
        #expect(entries[1].path == "/Users/me/tmp/sub dir")
    }

    @Test func skipsGarbage() {
        let out = data(["", "not a record", "ff\tx\ty\t644\t..", "ff\t1\t2\t644\tok"])
        let entries = ListingParser.parse(out, parent: "/")
        #expect(entries.map(\.name) == ["ok"])
        #expect(entries[0].size == 1)
    }

    @Test func finderOrderPutsFoldersFirstAndSortsNaturally() {
        func e(_ n: String, _ k: FileEntry.Kind) -> FileEntry {
            FileEntry(path: "/" + n, name: n, kind: k, size: 0, modified: .distantPast)
        }
        let sorted = [e("file10", .file), e("b", .directory), e("file2", .file), e("A", .directory)]
            .sorted(by: FileEntry.finderOrder)
        #expect(sorted.map(\.name) == ["A", "b", "file2", "file10"])
    }

    @Test func fileExtension() {
        let f = FileEntry(path: "/x/Photo.JPG", name: "Photo.JPG", kind: .file, size: 0, modified: .distantPast)
        #expect(f.fileExtension == "jpg")
        let hidden = FileEntry(path: "/x/.bashrc", name: ".bashrc", kind: .file, size: 0, modified: .distantPast)
        #expect(hidden.fileExtension == "")
        #expect(hidden.isHidden)
    }
}
