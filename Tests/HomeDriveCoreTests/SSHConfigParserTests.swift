import Foundation
import Testing
@testable import HomeDriveCore

@Suite struct SSHConfigParserTests {
    @Test func parsesAliases() {
        let text = """
        # my machines
        Host ubuntu-home
            HostName 10.77.0.1
            User diamondeyes
            IdentityFile ~/.ssh/id_ed25519

        Host pc pc-remote
          HostName=pc.example.com
          Port = 2222

        Host *
            ServerAliveInterval 30

        Match host foo
            User nobody
        """
        let hosts = SSHConfigParser.parse(text)
        #expect(hosts.map(\.alias) == ["ubuntu-home", "pc", "pc-remote"])
        #expect(hosts[0] == SSHHostAlias(alias: "ubuntu-home", hostName: "10.77.0.1", user: "diamondeyes"))
        #expect(hosts[1].hostName == "pc.example.com")
        #expect(hosts[1].port == 2222)
        #expect(hosts[2].port == 2222)
        #expect(hosts[0].summary == "diamondeyes@10.77.0.1")
        #expect(hosts[1].summary == "pc.example.com:2222")
    }

    @Test func firstValueWinsLikeSSH() {
        let hosts = SSHConfigParser.parse("Host a\n User one\n User two\n")
        #expect(hosts.first?.user == "one")
    }

    @Test func emptyConfig() {
        #expect(SSHConfigParser.parse("").isEmpty)
    }
}
