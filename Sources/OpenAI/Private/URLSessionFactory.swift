//
//  URLSessionFactory.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 10.03.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol URLSessionFactory: Sendable {
    func makeUrlSession(delegate: URLSessionDataDelegateProtocol) -> URLSessionProtocol
}

struct FoundationURLSessionFactory: URLSessionFactory {
    let factory: any OpenAIStreamingURLSessionFactory

    init(factory: any OpenAIStreamingURLSessionFactory = OpenAISecureStreamingURLSessionFactory()) {
        self.factory = factory
    }

    func makeUrlSession(delegate: URLSessionDataDelegateProtocol) -> any URLSessionProtocol {
        let forwarder = URLSessionDataDelegateForwarder(target: delegate)
        return factory.makeURLSession(delegate: forwarder)
    }
}
