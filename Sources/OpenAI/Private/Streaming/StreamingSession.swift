//
//  StreamingSession.swift
//
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StreamingSession<Interpreter: StreamInterpreter>: NSObject, Identifiable, URLSessionDataDelegateProtocol, @unchecked Sendable {
    typealias ResultType = Interpreter.ResultType
    
    private let urlSessionFactory: URLSessionFactory
    private var urlRequest: URLRequest?
    private var interpreter: Interpreter?
    private var sslDelegate: SSLDelegateProtocol?
    private var middlewares: [OpenAIMiddleware]?
    private let executionSerializer: ExecutionSerializer
    private let requiresSemanticCompletion: Bool
    private var onReceiveContent: (@Sendable (StreamingSession, ResultType) -> Void)?
    private var onProcessingError: (@Sendable (StreamingSession, Error) -> Void)?
    private var onComplete: (@Sendable (StreamingSession, Error?) -> Void)?
    private let cleanupObserver: OpenAIStreamingSessionCleanupObserver?
    private var isComplete = false
    private var isCleanedUp = false

    init(
        urlSessionFactory: URLSessionFactory = FoundationURLSessionFactory(),
        urlRequest: URLRequest,
        interpreter: Interpreter,
        sslDelegate: SSLDelegateProtocol?,
        middlewares: [OpenAIMiddleware],
        executionSerializer: ExecutionSerializer = GCDQueueAsyncExecutionSerializer(queue: .userInitiated),
        cleanupObserver: OpenAIStreamingSessionCleanupObserver? = nil,
        requiresSemanticCompletion: Bool = false,
        onReceiveContent: @escaping @Sendable (StreamingSession, ResultType) -> Void,
        onProcessingError: @escaping @Sendable (StreamingSession, Error) -> Void,
        onComplete: @escaping @Sendable (StreamingSession, Error?) -> Void
    ) {
        self.urlSessionFactory = urlSessionFactory
        self.urlRequest = urlRequest
        self.interpreter = interpreter
        self.sslDelegate = sslDelegate
        self.middlewares = middlewares
        self.executionSerializer = executionSerializer
        self.requiresSemanticCompletion = requiresSemanticCompletion
        self.onReceiveContent = onReceiveContent
        self.onProcessingError = onProcessingError
        self.onComplete = onComplete
        self.cleanupObserver = cleanupObserver
        super.init()
        subscribeToParser()
    }
    
    func makeSession() -> PerformableSession & InvalidatableSession {
        let urlSession = urlSessionFactory.makeUrlSession(delegate: self)
        guard let urlRequest else {
            fatalError("Streaming session has already completed cleanup")
        }
        return DataTaskPerformingURLSession(urlRequest: urlRequest, urlSession: urlSession)
    }
    
    func urlSession(_ session: any URLSessionProtocol, task: any URLSessionTaskProtocol, didCompleteWithError error: (any Error)?) {
        executionSerializer.dispatch {
            if let error {
                self.completeOnce(error)
            } else if self.requiresSemanticCompletion {
                self.completeOnce(OpenAIError.missingCompletionMarker)
            } else {
                self.completeOnce(nil)
            }
        }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        executionSerializer.dispatch {
            self.cleanupOnce()
        }
    }
    
    func urlSession(_ session: any URLSessionProtocol, dataTask: any URLSessionDataTaskProtocol, didReceive data: Data) {
        executionSerializer.dispatch {
            guard !self.isComplete else { return }
            let data = (self.middlewares ?? []).reduce(data) { current, middleware in
                middleware.interceptStreamingData(request: dataTask.originalRequest, current)
            }
            
            self.interpreter?.processData(data)
        }
    }

    func urlSession(
        _ session: URLSessionProtocol,
        dataTask: URLSessionDataTaskProtocol,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        executionSerializer.dispatch {
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let error = OpenAIError.statusError(response: httpResponse, statusCode: httpResponse.statusCode)
                self.onProcessingError?(self, error)
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let sslDelegate else { return completionHandler(.performDefaultHandling, nil) }
        sslDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    private func subscribeToParser() {
        interpreter?.setCallbackClosures { [weak self] content in
            guard let self else { return }
            self.onReceiveContent?(self, content)
        } onError: { [weak self] error in
            guard let self else { return }
            self.onProcessingError?(self, error)
            self.completeOnce(error)
        }
        interpreter?.setCompletionCallback { [weak self] in
            guard let self else { return }
            self.completeOnce(nil)
        }
    }

    private func completeOnce(_ error: Error?) {
        guard !isComplete else { return }
        isComplete = true
        onComplete?(self, error)
    }

    private func cleanupOnce() {
        guard !isCleanedUp else { return }
        isCleanedUp = true

        let cleanupObserver = cleanupObserver
        urlRequest = nil
        interpreter = nil
        sslDelegate = nil
        middlewares = nil
        onReceiveContent = nil
        onProcessingError = nil
        onComplete = nil

        executionSerializer.dispatch {
            cleanupObserver?.record(.postCleanup)
        }
    }
}
