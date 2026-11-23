import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct RemotePathTests {
    @Test func join() {
        #expect(RemotePath.join("/home/me", "a b") == "/home/me/a b")
        #expect(RemotePath.join("/", "etc") == "/etc")
        #expect(RemotePath.join("/home/me/", "x") == "/home/me/x")
    }

    @Test func normalize() {
        #expect(RemotePath.normalize("/home//me/./docs/") == "/home/me/docs")
        #expect(RemotePath.normalize("/home/me/../you") == "/home/you")
        #expect(RemotePath.normalize("/..") == "/")
        #expect(RemotePath.normalize("a/../..") == "..")
    }

    @Test func parentAndName() {
        #expect(RemotePath.parent("/home/me/docs") == "/home/me")
        #expect(RemotePath.parent("/home") == "/")
        #expect(RemotePath.parent("/") == "/")
        #expect(RemotePath.name("/home/me/a.txt") == "a.txt")
        #expect(RemotePath.name("/") == "/")
    }

    @Test func breadcrumbs() {
        let crumbs = RemotePath.breadcrumbs("/home/me")
        #expect(crumbs.map(\.name) == ["/", "home", "me"])
        #expect(crumbs.map(\.path) == ["/", "/home", "/home/me"])
    }

    @Test func breadcrumbsFromHome() {
        let crumbs = RemotePath.breadcrumbs("/home/me/Documents/Taxes", home: "/home/me")
        #expect(crumbs.map(\.name) == ["~", "Documents", "Taxes"])
        #expect(crumbs.map(\.path) == ["/home/me", "/home/me/Documents", "/home/me/Documents/Taxes"])
        #expect(RemotePath.breadcrumbs("/etc/ssh", home: "/home/me").map(\.name) == ["/", "etc", "ssh"])
        #expect(RemotePath.breadcrumbs("/home/meow", home: "/home/me").map(\.name) == ["/", "home", "meow"])
        #expect(RemotePath.breadcrumbs("/x", home: nil).map(\.name) == ["/", "x"])
    }

    @Test func expandTilde() {
        #expect(RemotePath.expandTilde("~/Documents", home: "/home/me") == "/home/me/Documents")
        #expect(RemotePath.expandTilde("~", home: "/home/me") == "/home/me")
        #expect(RemotePath.expandTilde("/srv/media", home: "/home/me") == "/srv/media")
        #expect(RemotePath.expandTilde("~other/x", home: "/home/me") == "~other/x")
    }

    @Test func abbreviate() {
        #expect(RemotePath.abbreviate("/home/me/Documents", home: "/home/me") == "~/Documents")
        #expect(RemotePath.abbreviate("/home/me", home: "/home/me") == "~")
        #expect(RemotePath.abbreviate("/home/meow", home: "/home/me") == "/home/meow")
        #expect(RemotePath.abbreviate("/etc", home: nil) == "/etc")
    }

    @Test func validNames() {
        #expect(RemotePath.isValidName("Report 2026.pdf"))
        #expect(!RemotePath.isValidName(""))
        #expect(!RemotePath.isValidName("."))
        #expect(!RemotePath.isValidName(".."))
        #expect(!RemotePath.isValidName("a/b"))
    }
}
