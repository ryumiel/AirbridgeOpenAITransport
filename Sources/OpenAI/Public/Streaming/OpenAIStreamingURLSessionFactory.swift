import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A narrow injection boundary for streaming URL sessions.
///
/// Implementations own session storage policy. The SDK delegate still rejects
/// redirects and receives streaming bytes.
public protocol OpenAIStreamingURLSessionFactory: Sendable {
    func makeURLSession(delegate: URLSessionDelegate) -> URLSession
}

/// The storage-isolated default used by streaming requests.
public struct OpenAISecureStreamingURLSessionFactory: OpenAIStreamingURLSessionFactory, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let isolated = configuration.copy() as! URLSessionConfiguration
        isolated.urlCache = nil
        isolated.httpCookieStorage = nil
        isolated.urlCredentialStorage = nil
        isolated.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration = isolated
    }

    public func makeURLSession(delegate: URLSessionDelegate) -> URLSession {
        let isolated = configuration.copy() as! URLSessionConfiguration
        return URLSession(configuration: isolated, delegate: delegate, delegateQueue: nil)
    }
}
