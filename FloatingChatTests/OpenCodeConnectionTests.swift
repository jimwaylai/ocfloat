import Testing
import Foundation
@testable import FloatingChat

struct ServiceDiscoveryTests {
    private func file(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ocf-service-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test func readsRunningService() throws {
        let url = try file(#"{"id":"x","version":"2.1.4","url":"http://127.0.0.1:49388","pid":42,"password":"pw"}"#)
        let info = ServiceDiscovery.read(at: url, isAlive: { $0 == 42 })
        #expect(info == ServiceInfo(url: URL(string: "http://127.0.0.1:49388")!, password: "pw", pid: 42))
    }

    @Test func staleFileMeansNotRunning() throws {
        let url = try file(#"{"url":"http://127.0.0.1:1","pid":42,"password":"pw"}"#)
        #expect(ServiceDiscovery.read(at: url, isAlive: { _ in false }) == nil)
    }

    @Test func missingOrInvalidFileMeansNotRunning() throws {
        #expect(ServiceDiscovery.read(at: URL(fileURLWithPath: "/nonexistent/service.json")) == nil)
        #expect(ServiceDiscovery.read(at: try file("{}")) == nil)
    }
}

struct ExecutableLocatorTests {
    @Test func searchOrder() {
        let candidates = ExecutableLocator.candidates(configured: "~/bin/oc", pathEnvironment: "/usr/bin:/opt/homebrew/bin", home: "/Users/me")
        #expect(candidates == [
            NSString("~/bin/oc").expandingTildeInPath,
            "/usr/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "/Users/me/.opencode/bin/opencode",
        ])
    }

    @Test func firstExecutableWins() {
        let found = ExecutableLocator.locate(configured: nil, pathEnvironment: "/usr/bin", home: "/Users/me") {
            $0 == "/Users/me/.opencode/bin/opencode"
        }
        #expect(found == "/Users/me/.opencode/bin/opencode")
        #expect(ExecutableLocator.locate(configured: nil, pathEnvironment: nil, home: "/h") { _ in false } == nil)
    }
}

struct OpenCodeEndpointTests {
    let endpoint = OpenCodeEndpoint(baseURL: URL(string: "http://127.0.0.1:49388")!, password: "secret")

    @Test func basicAuthWithOpencodeUser() {
        let request = endpoint.request("GET", "/api/info")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("opencode:secret".utf8).base64EncodedString())
    }

    @Test func locationUsesDeepObjectKey() throws {
        let request = endpoint.request("GET", "/api/model", query: [URLQueryItem(name: "types", value: "chat")], location: "/Users/me/a+b dir")
        let items = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "location[directory]", value: "/Users/me/a+b dir")))
        #expect(request.url!.path() == "/api/model")
        #expect(request.url!.absoluteString.contains("%2B"))
    }

    @Test func jsonBodySetsContentType() {
        let request = endpoint.request("POST", "/api/session", body: Data("{}".utf8))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}

struct SSEParserTests {
    @Test func emitsDataAndIgnoresHeartbeats() {
        var parser = SSEParser()
        let stream = "data: {\"a\":1}\n\n: heartbeat\n\ndata: {\"b\":2}\r\n\r\n"
        #expect(parser.push(Array(stream.utf8)) == [#"{"a":1}"#, #"{"b":2}"#])
    }

    @Test func handlesChunksSplitMidLine() {
        var parser = SSEParser()
        #expect(parser.push(Array("da".utf8)).isEmpty)
        #expect(parser.push(Array("ta: 你好\n".utf8)).isEmpty)
        #expect(parser.push(Array("\n".utf8)) == ["你好"])
    }

    @Test func joinsMultipleDataLines() {
        var parser = SSEParser()
        #expect(parser.push(Array("data: a\ndata:b\nid: 1\n\n".utf8)) == ["a\nb"])
    }
}

struct OpenCodeEventTests {
    @Test func extractsSessionID() throws {
        let json = #"{"id":"evt_1","type":"session.text.delta","data":{"sessionID":"ses_1","assistantMessageID":"msg_1","ordinal":0,"delta":"Hi"}}"#
        let event = try OpenCodeEvent(json: Data(json.utf8))
        #expect(event.type == "session.text.delta")
        #expect(event.sessionID == "ses_1")

        struct Delta: Decodable { let delta: String }
        #expect(try event.decodeData(Delta.self).delta == "Hi")
    }

    @Test func eventsWithoutSession() throws {
        let event = try OpenCodeEvent(json: Data(#"{"id":"evt_0","type":"server.connected","data":{}}"#.utf8))
        #expect(event.sessionID == nil)
    }
}
