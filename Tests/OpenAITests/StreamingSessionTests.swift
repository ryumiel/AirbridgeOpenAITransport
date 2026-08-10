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

        guard let error = completionError.get() as? OpenAIError,
              case .missingCompletionMarker = error else {
            return XCTFail("Expected missing completion marker error")
        }
    }

    func testPostCleanupWaitsForTerminalInvalidationAndClearsCallbackGraph() {
        let serializer = DeferredExecutionSerializer()
        let events = CleanupEventRecorder()
        let observer = OpenAIStreamingSessionCleanupObserver { event in
            events.record(event)
        }
        let completionRecorder = CompletionRecorder()
        weak var releasedCallbackGraph: CallbackGraph?
        let session: StreamingSession<MockDataStreamInterpreter>

        do {
            let callbackGraph = CallbackGraph(completionRecorder: completionRecorder)
            releasedCallbackGraph = callbackGraph
            session = StreamingSession(
                urlSessionFactory: MockURLSessionFactory(),
                urlRequest: .init(url: .init(string: "/")!),
                interpreter: MockDataStreamInterpreter(),
                sslDelegate: nil,
                middlewares: [],
                executionSerializer: serializer,
                cleanupObserver: observer,
                onReceiveContent: { _, _ in },
                onProcessingError: { _, _ in },
                onComplete: { _, _ in callbackGraph.recordCompletion() }
            )
        }

        let urlSession = URLSession(configuration: .ephemeral)
        session.urlSession(URLSessionMock(), task: DataTaskMock(), didCompleteWithError: nil)
        URLSessionDataDelegateForwarder(target: session).urlSession(
            urlSession,
            didBecomeInvalidWithError: nil
        )

        serializer.runNext()
        XCTAssertEqual(completionRecorder.count, 1)
        XCTAssertEqual(events.values, [])
        XCTAssertNotNil(releasedCallbackGraph)

        serializer.runNext()
        XCTAssertEqual(completionRecorder.count, 1)
        XCTAssertEqual(events.values, [])
        XCTAssertNil(releasedCallbackGraph)

        serializer.runNext()
        XCTAssertEqual(completionRecorder.count, 1)
        XCTAssertEqual(events.values, [.postCleanup])
    }

    func testPostCleanupIsReportedExactlyOnceForRepeatedTerminalInvalidation() {
        let events = CleanupEventRecorder()
        let session = StreamingSession(
            urlSessionFactory: MockURLSessionFactory(),
            urlRequest: .init(url: .init(string: "/")!),
            interpreter: MockDataStreamInterpreter(),
            sslDelegate: nil,
            middlewares: [],
            executionSerializer: NoDispatchExecutionSerializer(),
            cleanupObserver: .init { event in events.record(event) },
            onReceiveContent: { _, _ in },
            onProcessingError: { _, _ in },
            onComplete: { _, _ in }
        )

        let urlSession = URLSession(configuration: .ephemeral)
        let forwarder = URLSessionDataDelegateForwarder(target: session)
        forwarder.urlSession(urlSession, didBecomeInvalidWithError: nil)
        forwarder.urlSession(urlSession, didBecomeInvalidWithError: nil)

        XCTAssertEqual(events.values, [.postCleanup])
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

private final class CallbackGraph: @unchecked Sendable {
    private let completionRecorder: CompletionRecorder

    init(completionRecorder: CompletionRecorder) {
        self.completionRecorder = completionRecorder
    }

    func recordCompletion() {
        completionRecorder.record()
    }
}

private final class CompletionRecorder: @unchecked Sendable {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private final class CleanupEventRecorder: @unchecked Sendable {
    private(set) var values: [OpenAIStreamingSessionCleanupEvent] = []

    func record(_ event: OpenAIStreamingSessionCleanupEvent) {
        values.append(event)
    }
}

private final class DeferredExecutionSerializer: ExecutionSerializer, @unchecked Sendable {
    private var operations: [() -> Void] = []

    func dispatch(_ closure: @escaping () -> Void) {
        operations.append(closure)
    }

    func runNext() {
        operations.removeFirst()()
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
