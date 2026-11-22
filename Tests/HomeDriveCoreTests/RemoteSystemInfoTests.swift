import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct RemoteSystemInfoTests {
    @Test func parsesProbeOutput() {
        let text = """
        home\t/home/diamondeyes
        host\tubuntu-pc
        os\tLinux 6.8.0-49-generic
        trash\t1
        place\t/home/diamondeyes/Desktop
        place\t/home/diamondeyes/Documents
        place\t/home/diamondeyes/Desktop
        disk\t1000\t250
        garbage line

        """
        let info = RemoteSystemInfo.parse(text)
        #expect(info.home == "/home/diamondeyes")
        #expect(info.hostname == "ubuntu-pc")
        #expect(info.os == "Linux 6.8.0-49-generic")
        #expect(info.supportsTrash)
        #expect(info.places == ["/home/diamondeyes/Desktop", "/home/diamondeyes/Documents"])
        #expect(info.diskTotalBytes == Int64(1_024_000))
        #expect(info.diskFreeBytes == Int64(256_000))
    }

    @Test func missingFieldsStayEmpty() {
        let info = RemoteSystemInfo.parse("home\t/root\n")
        #expect(info.home == "/root")
        #expect(!info.supportsTrash)
        #expect(info.places.isEmpty)
        #expect(info.diskFreeBytes == nil)
    }
}
