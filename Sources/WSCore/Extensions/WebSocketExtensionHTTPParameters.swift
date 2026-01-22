//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HTTPTypes

/// Parsed parameters from `Sec-WebSocket-Extensions` header
public struct WebSocketExtensionHTTPParameters: Sendable, Equatable {
    /// A single parameter
    public enum Parameter: Sendable, Equatable {
        // Parameter with a value
        case value(String)
        // Parameter with no value
        case null

        // Convert to optional
        public var optional: String? {
            switch self {
            case .value(let string):
                return .some(string)
            case .null:
                return .none
            }
        }

        // Convert to integer
        public var integer: Int? {
            switch self {
            case .value(let string):
                return Int(string)
            case .null:
                return .none
            }
        }
    }

    public let parameters: [String: Parameter]
    public let name: String

    /// initialise WebSocket extension parameters from string
    init?(from header: some StringProtocol) {
        let split = header.split(separator: ";", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }[...]
        if let name = split.first {
            self.name = name
        } else {
            return nil
        }
        var index = split.index(after: split.startIndex)
        var parameters: [String: Parameter] = [:]
        while index != split.endIndex {
            let keyValue = split[index].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let key = keyValue.first {
                if keyValue.count > 1 {
                    parameters[key] = .value(keyValue[1])
                } else {
                    parameters[key] = .null
                }
            }
            index = split.index(after: index)
        }
        self.parameters = parameters
    }

    /// Parse all `Sec-WebSocket-Extensions` header values
    /// - Parameters:
    ///   - headers: headers coming from other
    /// - Returns: Array of extensions
    public static func parseHeaders(_ headers: HTTPFields) -> [WebSocketExtensionHTTPParameters] {
        let extHeaders = headers[values: .secWebSocketExtensions]
        return extHeaders.compactMap { .init(from: $0) }
    }
}

extension WebSocketExtensionHTTPParameters {
    /// Initialiser used by tests
    package init(_ name: String, parameters: [String: Parameter]) {
        self.name = name
        self.parameters = parameters
    }
}
