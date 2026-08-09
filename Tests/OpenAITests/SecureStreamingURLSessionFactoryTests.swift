import Foundation
import XCTest
@testable import OpenAI

final class SecureStreamingURLSessionFactoryTests: XCTestCase {
    func testCreatesStorageIsolatedSession() {
        let factory = OpenAISecureStreamingURLSessionFactory(configuration: .default)
        let session = factory.makeURLSession(delegate: NSObjectDelegate())

        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        session.invalidateAndCancel()
    }
}

private final class NSObjectDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {}
