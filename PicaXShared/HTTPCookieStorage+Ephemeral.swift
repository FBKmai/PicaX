import Foundation

extension HTTPCookieStorage {
    nonisolated static func makeEphemeral() -> HTTPCookieStorage {
        // Foundation's inherited init() does not create a working cookie store.
        URLSessionConfiguration.ephemeral.httpCookieStorage!
    }
}
