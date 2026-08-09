//
//  StreamingSessionTests.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 11.03.2025.
//

import Foundation
import XCTest
@testable import OpenAI

final class StreamingSessionTests: XCTestCase {
    private let streamInterpreter = MockDataStreamInterpreter()
    
    private var onReceivedContentCallCount = 0
    
    private lazy var streamingSession = StreamingSession(
        urlSessionFactory: MockURLSessionFactory(),
        urlRequest: .init(url: .init(string: "/")!),
        interpreter: streamInterpreter,
        sslDelegate: nil,
        middlewares: [],
        executionSerializer: NoDispatchExecutionSerializer(),
        onReceiveContent: { _, _ in
            self.onReceivedContentCallCount += 1
        },
        onProcessingError: { _, _ in },
        onComplete: { _,_ in }
    )

    @MainActor
    func testDataProcessedCallback() async throws {
        _ = streamingSession
        streamInterpreter.processData(.init())
        XCTAssertEqual(onReceivedContentCallCount, 1)
    }

    func testRejectsRedirects() throws {
        let session = URLSession(configuration: .ephemeral)
        let originalURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/v1/chat/completions"))
        let redirectURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8081/v1/chat/completions"))
        let task = session.dataTask(with: originalURL)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: originalURL,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectURL.absoluteString]
        ))
        let result = URLRequestBox(URLRequest(url: redirectURL))

        streamingSession.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectURL)
        ) { request in
            result.value = request
        }

        XCTAssertNil(result.value)
        session.invalidateAndCancel()
    }

    func testServerSentEventsRejectCleanEOFWithoutDoneMarker() {
        let interpreter = ServerSentEventsStreamInterpreter<ChatStreamResult>(
            parsingOptions: [],
            strictChatCompletions: false
        )
        let completionError = ErrorBox()
        let session = StreamingSession(
            urlSessionFactory: MockURLSessionFactory(),
            urlRequest: .init(url: .init(string: "/")!),
            interpreter: interpreter,
            sslDelegate: nil,
            middlewares: [],
            executionSerializer: NoDispatchExecutionSerializer(),
            requiresSemanticCompletion: true,
            onReceiveContent: { _, _ in },
            onProcessingError: { _, _ in },
            onComplete: { _, error in completionError.set(error) }
        )

        session.urlSession(
            URLSessionMock(),
            dataTask: DataTaskMock(),
            didReceive: MockServerSentEvent.chatCompletionChunk()
        )
        session.urlSession(URLSessionMock(), task: DataTaskMock(), didCompleteWithError: nil)

        guard let error = completionError.get() as? StreamingError,
              case .missingCompletionMarker = error else {
            return XCTFail("Expected missing completion marker error")
        }
    }
}

private final class URLRequestBox: @unchecked Sendable {
    var value: URLRequest?

    init(_ value: URLRequest?) {
        self.value = value
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Error?

    func set(_ value: Error?) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

class MockDataStreamInterpreter: StreamInterpreter, @unchecked Sendable {
    typealias ResultType = Data
    
    private var onEventDispatched: ((Data) -> Void)?
    private var onError: ((any Error) -> Void)?
    
    func setCallbackClosures(onEventDispatched: @escaping (Data) -> Void, onError: @escaping (any Error) -> Void) {
        self.onEventDispatched = onEventDispatched
        self.onError = onError
    }
    
    func processData(_ data: Data) {
        onEventDispatched?(data)
    }
}
