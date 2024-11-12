//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOWebSocket

/// Basic context implementation of ``WebSocketContext``.
public struct WebSocketExtensionContext: Sendable {
    public let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }
}

/// Protocol for WebSocket extension
public protocol WebSocketExtension: Sendable {
    /// Extension name
    var name: String { get }
    /// Process frame received from websocket
    func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame
    /// Process frame about to be sent to websocket
    func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame
    /// shutdown extension
    func shutdown() async
}

/// Protocol for WebSocket extension builder
public protocol WebSocketExtensionBuilder: Sendable {
    /// name of WebSocket extension name
    static var name: String { get }
    /// construct client request header
    func clientRequestHeader() -> String
    /// construct server response header based of client request
    func serverReponseHeader(to: WebSocketExtensionHTTPParameters) -> String?
    /// construct server version of extension based of client request
    func serverExtension(from: WebSocketExtensionHTTPParameters) throws -> (any WebSocketExtension)?
    /// construct client version of extension based of server response
    func clientExtension(from: WebSocketExtensionHTTPParameters) throws -> (any WebSocketExtension)?
}

extension WebSocketExtensionBuilder {
    /// construct server response header based of all client requests
    public func serverResponseHeader(to requests: [WebSocketExtensionHTTPParameters]) -> String? {
        for request in requests {
            guard request.name == Self.name else { continue }
            if let response = serverReponseHeader(to: request) {
                return response
            }
        }
        return nil
    }

    /// construct all server extensions based of all client requests
    public func serverExtension(from requests: [WebSocketExtensionHTTPParameters]) throws -> (any WebSocketExtension)? {
        for request in requests {
            guard request.name == Self.name else { continue }
            if let ext = try serverExtension(from: request) {
                return ext
            }
        }
        return nil
    }

    /// construct all client extensions based of all server responses
    public func clientExtension(from requests: [WebSocketExtensionHTTPParameters]) throws -> (any WebSocketExtension)? {
        for request in requests {
            guard request.name == Self.name else { continue }
            if let ext = try clientExtension(from: request) {
                return ext
            }
        }
        return nil
    }
}

/// Build WebSocket extension builder
public struct WebSocketExtensionFactory: Sendable {
    public let build: @Sendable () -> any WebSocketExtensionBuilder

    public init(_ build: @escaping @Sendable () -> any WebSocketExtensionBuilder) {
        self.build = build
    }
}

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
