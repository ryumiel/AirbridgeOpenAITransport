//
//  StreamingClientTests.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 27.06.2025.
//

import Testing
import Foundation
@testable import OpenAI

struct StreamingClientTests {
    
    private let configuration = OpenAI.Configuration(token: "")
    private let mockSessionFactory = MockStreamingSessionFactory()
    private let mockMiddleware = MockMiddleware()
    private let client: StreamingClient
    
    private let originalURL = URL(string: "original")!
    private let interceptedURL = URL(string: "intercepted")!
    
    private var mockSession: URLSessionMock {
        mockSessionFactory.urlSessionFactory.urlSession
    }
    
    init() {
        self.client = StreamingClient(
            configuration: configuration,
            streamingSessionFactory: mockSessionFactory,
            middlewares: [mockMiddleware],
            cancellablesFactory: MockCancellablesFactory(),
            executionSerializer: NoDispatchExecutionSerializer()
        )
    }

    @Test func interceptRequest() async throws {
        mockSession.dataTask = try DataTaskMock.successfulJson(with: ChatResult.mock)
        mockMiddleware.interceptRequestReturnValue = .init(url: interceptedURL)
        _ = client.performStreamingRequest(
            request: JSONRequest<ChatResult>(url: originalURL),
            onResult: { (result: Result<ChatResult, Error>) in },
            completion: { _ in }
        )
        #expect(mockSession.dataTaskCalls[0].request.url == interceptedURL)
    }
    
    @Test func interceptSpeechRequest() async throws {
        mockSession.dataTask = try DataTaskMock.successfulJson(with: AudioSpeechResult(audio: .init()))
        mockMiddleware.interceptRequestReturnValue = .init(url: interceptedURL)
        _ = client.performSpeechStreamingRequest(
            request: JSONRequest<AudioSpeechResult>(url: originalURL),
            onResult: { (result: Result<AudioSpeechResult, Error>) in },
            completion: { _ in }
        )
        
        #expect(mockSession.dataTaskCalls[0].request.url == interceptedURL)
    }
    
    @Test func interceptResponsesRequest() async throws {
        mockSession.dataTask = try DataTaskMock.successfulJson(with: ResponseStreamEvent.audio(.done(.init(_type: .response_audio_done, sequenceNumber: 0))))
        mockMiddleware.interceptRequestReturnValue = .init(url: interceptedURL)
        _ = client.performResponsesStreamingRequest(
            request: JSONRequest<ResponseStreamEvent>(url: originalURL),
            onResult: { (result: Result<ResponseStreamEvent, Error>) in },
            completion: { _ in }
        )
        
        #expect(mockSession.dataTaskCalls[0].request.url == interceptedURL)
    }

    @Test func requestBuildFailureReportsNoSessionCreatedAfterCompletion() async throws {
        let events = ClientCleanupEventRecorder()
        let client = StreamingClient(
            configuration: configuration,
            streamingSessionFactory: mockSessionFactory,
            middlewares: [mockMiddleware],
            cancellablesFactory: MockCancellablesFactory(),
            executionSerializer: NoDispatchExecutionSerializer(),
            cleanupObserver: .init { event in events.record(.cleanup(event)) }
        )

        _ = client.performStreamingRequest(
            request: ThrowingStreamingRequest(),
            onResult: { (_: Result<ChatResult, Error>) in },
            completion: { _ in events.record(.completion) }
        )

        #expect(events.values == [.completion, .cleanup(.noSessionCreated)])
    }
}

private struct ThrowingStreamingRequest: URLRequestBuildable {
    struct BuildError: Error {}

    func build(
        token: String?,
        organizationIdentifier: String?,
        timeoutInterval: TimeInterval,
        customHeaders: [String: String]
    ) throws -> URLRequest {
        throw BuildError()
    }
}

private final class ClientCleanupEventRecorder: @unchecked Sendable {
    enum Value: Equatable {
        case completion
        case cleanup(OpenAIStreamingSessionCleanupEvent)
    }

    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}
