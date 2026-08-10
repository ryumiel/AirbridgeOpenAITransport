//
//  URLSessionDelegateProtocol.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 11.03.2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol URLSessionDelegateProtocol: Sendable { // Sendable to make a better match with URLSessionDelegate, it's sendable too
    func urlSession(_ session: URLSessionProtocol, task: URLSessionTaskProtocol, didCompleteWithError error: Error?)

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?)
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    )
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    )
}

extension URLSessionDelegateProtocol {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {}

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

protocol URLSessionDataDelegateProtocol: URLSessionDelegateProtocol {
    func urlSession(_ session: URLSessionProtocol, dataTask: URLSessionDataTaskProtocol, didReceive data: Data)
    
    func urlSession(
        _ session: URLSessionProtocol,
        dataTask: URLSessionDataTaskProtocol,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    )
}
