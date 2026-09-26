import CryptoKit
import XCTest
@testable import PicaX

@MainActor
final class JmSessionTests: XCTestCase {
    func testLoginSessionSurvivesCredentialRoundTripAndAuthenticatesFavorites() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JmSessionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = ComicContentService(session: session)

        let account = try await service.validateLogin(platform: .jmComic, username: "member", password: "example")
        XCTAssertEqual(account.credential.cookies.first { $0.name == "AVS" }?.value, "member-session")

        let restoredAccount = try JSONDecoder().decode(PlatformAccount.self, from: JSONEncoder().encode(account))
        let folders = try await service.loadJmComicFavoriteFolders(account: restoredAccount)
        XCTAssertEqual(folders.map(\.id), ["0", "42"])
    }

    func testEphemeralCookieStoresKeepAccountsIsolated() throws {
        let url = try XCTUnwrap(URL(string: "https://www.cdnhjk.net/"))
        let first = HTTPCookieStorage.makeEphemeral()
        let second = HTTPCookieStorage.makeEphemeral()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "AVS", .value: "first-account", .domain: url.host!, .path: "/"
        ]))
        first.setCookie(cookie)

        XCTAssertEqual(first.cookies(for: url)?.first?.value, "first-account")
        XCTAssertTrue((second.cookies(for: url) ?? []).isEmpty)
    }

    func testProxyPreservesSessionCookieAlongsideExpiryAndOtherHeaders() throws {
        let rawResponse = [
            "HTTP/1.1 200 OK",
            "Content-Length: 0",
            "Set-Cookie: ipcountry=US; Path=/",
            "Set-Cookie: theme=light; Expires=Thu, 25-Mar-2027 13:28:26 GMT; Path=/",
            "Set-Cookie: AVS=member-session; Path=/; HttpOnly",
            "Set-Cookie: __cflb=affinity; Path=/; Secure",
            "Content-Type: application/json", "", ""
        ].joined(separator: "\r\n")
        let decoded = try AppProxyHTTPCodec.readResponse(
            from: CookieResponseChannel(data: Data(rawResponse.utf8)), requestMethod: "GET"
        )
        let url = try XCTUnwrap(URL(string: "https://www.cdnhjk.net/login"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: decoded.statusCode, httpVersion: decoded.version, headerFields: decoded.headers
        ))
        let storage = HTTPCookieStorage.makeEphemeral()
        ComicContentService().saveCookies(from: response, requestURL: url, cookies: storage)

        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(Set((storage.cookies(for: url) ?? []).map(\.name)), ["ipcountry", "theme", "AVS", "__cflb"])
    }
}

private nonisolated final class CookieResponseChannel: AppProxyHTTPChannel {
    private var data: Data
    init(data: Data) { self.data = data }
    func write(_ data: Data) throws {}
    func read() throws -> Data {
        defer { data = Data() }
        return data
    }
    func close() {}
}

private nonisolated final class JmSessionURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            var headers = ["Content-Type": "application/json"]
            let payload: [String: Any]
            if url.path == "/login" {
                payload = ["username": "member", "uid": "42"]
                headers["Set-Cookie"] = "theme=light; Path=/, AVS=member-session; Path=/; HttpOnly"
            } else if url.path == "/favorite",
                      request.value(forHTTPHeaderField: "Cookie")?.contains("AVS=member-session") == true {
                payload = ["folder_list": [["FID": "42", "name": "My favorites"]]]
            } else {
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"code":401,"errorMsg":"請先登入會員"}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let time = try XCTUnwrap(request.value(forHTTPHeaderField: "tokenparam")?.split(separator: ",").first)
            let key = Insecure.MD5.hash(data: Data("\(time)185Hcomic3PAPP7R".utf8))
                .map { String(format: "%02x", $0) }.joined()
            let encrypted = try AESECBService(key: Data(key.utf8)).encrypt(JSONSerialization.data(withJSONObject: payload))
            let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": encrypted.base64EncodedString()])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
