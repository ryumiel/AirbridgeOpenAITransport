//
//  OpenAIStreamingSessionCleanupObserver.swift
//  OpenAI
//

import Foundation

/// A terminal, value-free fact about one streaming request's private cleanup.
public enum OpenAIStreamingSessionCleanupEvent: Sendable, Equatable {
    /// Request construction failed before a private streaming session existed.
    case noSessionCreated

    /// A private streaming session cleared its request and callback graph.
    case postCleanup
}

/// Receives the terminal cleanup fact for each streaming request made by one client.
public struct OpenAIStreamingSessionCleanupObserver: Sendable {
    private let callback: @Sendable (OpenAIStreamingSessionCleanupEvent) -> Void

    public init(_ callback: @escaping @Sendable (OpenAIStreamingSessionCleanupEvent) -> Void) {
        self.callback = callback
    }

    func record(_ event: OpenAIStreamingSessionCleanupEvent) {
        callback(event)
    }
}
