import Foundation

enum StrictChatCompletionsValidationError: Error, Sendable {
    case invalidShape
    case unsupportedField
}

enum StrictChatCompletionsValidator {
    private static let rootKeys: Set<String> = ["id", "object", "created", "model", "choices"]
    private static let nonStreamingChoiceKeys: Set<String> = ["index", "message", "finish_reason"]
    private static let messageKeys: Set<String> = ["role", "content"]
    private static let streamingChoiceKeys: Set<String> = ["index", "delta", "finish_reason"]
    private static let deltaKeys: Set<String> = ["role", "content"]

    static func validateNonStreaming(_ data: Data) throws {
        let root = try object(from: data)
        try requireOnly(root, keys: rootKeys)
        guard let choices = root["choices"] as? [[String: Any]] else {
            throw StrictChatCompletionsValidationError.invalidShape
        }
        for choice in choices {
            try requireOnly(choice, keys: nonStreamingChoiceKeys)
            guard let message = choice["message"] as? [String: Any] else {
                throw StrictChatCompletionsValidationError.invalidShape
            }
            try requireOnly(message, keys: messageKeys)
        }
    }

    static func validateStreaming(_ data: Data) throws {
        let root = try object(from: data)
        try requireOnly(root, keys: rootKeys)
        guard let choices = root["choices"] as? [[String: Any]] else {
            throw StrictChatCompletionsValidationError.invalidShape
        }
        for choice in choices {
            try requireOnly(choice, keys: streamingChoiceKeys)
            guard let delta = choice["delta"] as? [String: Any] else {
                throw StrictChatCompletionsValidationError.invalidShape
            }
            try requireOnly(delta, keys: deltaKeys)
        }
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StrictChatCompletionsValidationError.invalidShape
        }
        return object
    }

    private static func requireOnly(_ object: [String: Any], keys: Set<String>) throws {
        guard Set(object.keys).isSubset(of: keys) else {
            throw StrictChatCompletionsValidationError.unsupportedField
        }
    }
}
