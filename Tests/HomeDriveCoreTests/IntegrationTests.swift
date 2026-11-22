import Foundation
import Testing
@testable import HomeDriveCore

/// End-to-end tests: real scripts, real `find`/`tar`, real pipes — with a fake `ssh`
/// (see `FakeSSH`) that runs the "remote" side on this machine. On macOS this exercises
/// the BSD fallbacks; on Linux CI it exercises the GNU tools the PC actually uses.
@Suite(.serialized) struct IntegrationTests {
    let sandbox: TempDir
    let mac: TempDir      // plays the Mac
    let pc: TempDir       // plays the Linux PC
    let service: RemoteFileService
    let engine: TransferEngine

    init() throws {
        sandbox = try TempDir()
        mac = try TempDir()
        pc = try TempDir()
        let ssh = try FakeSSH.install(in: sandbox)
        let builder = SSHCommandBuilder(settings: ConnectionSettings(host: "fake-pc"), sshExecutable: ssh)
        service = RemoteFileService(builder: builder)
        engine = TransferEngine(builder: builder)
    }

    // MARK: Browsing and file operations

    @Test func connectAndProbe() async throws {
        let info = try await service.connect()
        #expect(!info.home.isEmpty)
        #expect(!info.hostname.isEmpty)
        #expect(!info.os.isEmpty)
    }

    @Test func listsFolders() async throws {
        try pc.file("b.txt", "12345")
        try pc.folder("A folder")
        try pc.file("it's a $(file).txt", "x")
        try pc.file(".hidden", "")
        let entries = try await service.list(pc.path)
        #expect(entries.map(\.name) == ["A folder", ".hidden", "b.txt", "it's a $(file).txt"])
        let b = try #require(entries.first { $0.name == "b.txt" })
        #expect(b.kind == .file)
        #expect(b.size == 5)
        #expect(b.path == pc.path + "/b.txt")
        #expect(abs(b.modified.timeIntervalSinceNow) < 120)
        #expect(entries.first?.kind == .directory)
    }

    @Test func listsAnEmptyFolder() async throws {
        #expect(try await service.list(pc.path).isEmpty)
    }

    @Test func listingAMissingFolderFails() async throws {
        await #expect(throws: HomeDriveError.commandFailed(status: 3, message: "No such folder: \(pc.path)/nope")) {
            _ = try await service.list(pc.path + "/nope")
        }
    }

    @Test func makeRenameAndDelete() async throws {
        try await service.makeDirectory(named: "New Folder", in: pc.path)
        #expect(pc.exists("New Folder"))
        await #expect(throws: HomeDriveError.self) {
            try await service.makeDirectory(named: "New Folder", in: pc.path)
        }

        try await service.rename(pc.path + "/New Folder", to: "Renamed 'one'")
        #expect(try pc.children() == ["Renamed 'one'"])

        try pc.file("other")
        await #expect(throws: HomeDriveError.self) {
            try await service.rename(pc.path + "/other", to: "Renamed 'one'")   // no overwrite
        }

        try await service.delete([pc.path + "/Renamed 'one'", pc.path + "/other"])
        #expect(try pc.children().isEmpty)
    }

    @Test func existingNamesAndDiskUsage() async throws {
        try pc.file("a")
        try pc.file("c d", String(repeating: "x", count: 50_000))
        let found = try await service.existingNames(["a", "b", "c d"], in: pc.path)
        #expect(found == ["a", "c d"])
        let usage = try await service.diskUsage([pc.path + "/c d"])
        #expect(usage >= 40_000)
    }

    // MARK: Transfers

    @Test func uploadsAFile() async throws {
        let src = try mac.file("Report – final.txt", "the content")
        let progress = ProgressLog()
        try await engine.upload(src, toRemoteFolder: pc.path, replaceExisting: false) { progress.record($0) }
        #expect(try pc.read("Report – final.txt") == "the content")
        #expect(try pc.children() == ["Report – final.txt"])   // no staging leftovers
        #expect((progress.all.last ?? 0) > 0)
    }

    @Test func uploadsAFolderTreeIntoANewRemoteFolder() async throws {
        try mac.file("Photos/2026/a.jpg", "A")
        try mac.file("Photos/2026/b c.jpg", "B")
        try mac.file("Photos/notes.md", "N")
        try await engine.upload(mac.url.appendingPathComponent("Photos"),
                                toRemoteFolder: pc.path + "/Backups", replaceExisting: false) { _ in }
        #expect(try pc.read("Backups/Photos/2026/a.jpg") == "A")
        #expect(try pc.read("Backups/Photos/2026/b c.jpg") == "B")
        #expect(try pc.read("Backups/Photos/notes.md") == "N")
        #expect(try pc.children("Backups") == ["Photos"])
        #expect(!(try pc.children("Backups/Photos").contains { $0.hasPrefix("._") }))
    }

    @Test func uploadRefusesToOverwriteUnlessAsked() async throws {
        try pc.file("same.txt", "old")
        let src = try mac.file("same.txt", "new")
        await #expect(throws: HomeDriveError.alreadyExists("same.txt")) {
            try await engine.upload(src, toRemoteFolder: pc.path, replaceExisting: false) { _ in }
        }
        #expect(try pc.read("same.txt") == "old")
        #expect(try pc.children() == ["same.txt"])

        try await engine.upload(src, toRemoteFolder: pc.path, replaceExisting: true) { _ in }
        #expect(try pc.read("same.txt") == "new")
    }

    @Test func uploadsNamesThatLookLikeOptions() async throws {
        let src = try mac.file("-rf", "dash")
        try await engine.upload(src, toRemoteFolder: pc.path, replaceExisting: false) { _ in }
        #expect(try pc.read("-rf") == "dash")
    }

    @Test func downloadsAFile() async throws {
        try pc.file("Documents/tax 2026.pdf", "PDF")
        let progress = ProgressLog()
        try await engine.download(pc.path + "/Documents/tax 2026.pdf",
                                  toLocalFolder: mac.url, replaceExisting: false) { progress.record($0) }
        #expect(try mac.read("tax 2026.pdf") == "PDF")
        #expect(try mac.children() == ["tax 2026.pdf"])
        #expect((progress.all.last ?? 0) > 0)
    }

    @Test func downloadsAFolderTree() async throws {
        try pc.file("Projects/app/src/main.c", "int main(){}")
        try pc.file("Projects/app/README", "hi")
        try await engine.download(pc.path + "/Projects", toLocalFolder: mac.url.appendingPathComponent("In"),
                                  replaceExisting: false) { _ in }
        #expect(try mac.read("In/Projects/app/src/main.c") == "int main(){}")
        #expect(try mac.read("In/Projects/app/README") == "hi")
        #expect(try mac.children("In") == ["Projects"])
    }

    @Test func downloadReplaceSemantics() async throws {
        try pc.file("x.txt", "remote")
        try mac.file("x.txt", "local")
        await #expect(throws: HomeDriveError.alreadyExists("x.txt")) {
            try await engine.download(pc.path + "/x.txt", toLocalFolder: mac.url, replaceExisting: false) { _ in }
        }
        #expect(try mac.read("x.txt") == "local")
        try await engine.download(pc.path + "/x.txt", toLocalFolder: mac.url, replaceExisting: true) { _ in }
        #expect(try mac.read("x.txt") == "remote")
        #expect(try mac.children() == ["x.txt"])
    }

    @Test func downloadingAMissingFileFailsCleanly() async throws {
        await #expect(throws: HomeDriveError.self) {
            try await engine.download(pc.path + "/ghost", toLocalFolder: mac.url, replaceExisting: false) { _ in }
        }
        #expect(try mac.children().isEmpty)
    }

    @Test func largeFileRoundTripKeepsEveryByte() async throws {
        var bytes = [UInt8](repeating: 0, count: 3 * 1024 * 1024 + 17)
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        let data = Data(bytes)
        let src = mac.url.appendingPathComponent("blob.bin")
        try data.write(to: src)

        let progress = ProgressLog()
        try await engine.upload(src, toRemoteFolder: pc.path, replaceExisting: false) { progress.record($0) }
        #expect(try Data(contentsOf: pc.url.appendingPathComponent("blob.bin")) == data)
        #expect((progress.all.last ?? 0) >= Int64(data.count))
        #expect(progress.all == progress.all.sorted())   // monotonic

        let back = try TempDir()
        try await engine.download(pc.path + "/blob.bin", toLocalFolder: back.url, replaceExisting: false) { _ in }
        #expect(try Data(contentsOf: back.url.appendingPathComponent("blob.bin")) == data)
    }

    @Test func cancellingADownloadLeavesNothingBehind() async throws {
        // A "remote" command that never finishes; cancelling must stop both sides and clean up.
        let ssh = sandbox.url.appendingPathComponent("slow-ssh")
        try "#!/bin/sh\nexec sleep 30\n".write(to: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh.path)
        let slow = TransferEngine(builder: SSHCommandBuilder(settings: ConnectionSettings(host: "x"),
                                                             sshExecutable: ssh.path))
        let task = Task {
            try await slow.download("/whatever/big.iso", toLocalFolder: mac.url, replaceExisting: false) { _ in }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try mac.children().isEmpty)
    }

    @Test func connectionFailuresAreReportedAsSuch() async throws {
        let ssh = try FakeSSH.install(in: sandbox, exitCode: 255,
                                      stderr: "ssh: connect to host 10.77.0.1 port 22: Operation timed out")
        let builder = SSHCommandBuilder(settings: ConnectionSettings(host: "x"), sshExecutable: ssh)
        let src = try mac.file("a.txt")
        do {
            try await TransferEngine(builder: builder)
                .upload(src, toRemoteFolder: "/tmp", replaceExisting: false) { _ in }
            Issue.record("expected failure")
        } catch let error as HomeDriveError {
            guard case .connectionFailed = error else { Issue.record("wrong error \(error)"); return }
            #expect(error.localizedDescription.contains("WireGuard"))
        }
        await #expect(throws: HomeDriveError.self) {
            _ = try await RemoteFileService(builder: builder).list("/")
        }
    }
}

@Suite struct LocalFileServiceTests {
    @Test func listsAndSizes() throws {
        let dir = try TempDir()
        try dir.file("z.txt", "12345")
        try dir.file("Sub/inner.txt", "123")
        let entries = try LocalFileService().list(dir.path)
        #expect(entries.map(\.name) == ["Sub", "z.txt"])
        #expect(entries[0].kind == .directory)
        #expect(entries[1].size == 5)
        #expect(LocalFileService().totalSize(of: dir.url) == 8)
        #expect(LocalFileService().totalSize(of: dir.url.appendingPathComponent("z.txt")) == 5)
        #expect(LocalFileService().freeSpace(at: dir.path) != nil)
    }
}
