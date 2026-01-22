//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//
import HTTPTypes

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
        if let nonNegotiableExtensionBuilder = self as? any _WebSocketNonNegotiableExtensionBuilderProtocol {
            return nonNegotiableExtensionBuilder.build()
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
        if let nonNegotiableExtensionBuilder = self as? any _WebSocketNonNegotiableExtensionBuilderProtocol {
            return nonNegotiableExtensionBuilder.build()
        }
        return nil
    }
}

/// Protocol for w WebSocket extension that is applied without any negotiation with the other side
protocol _WebSocketNonNegotiableExtensionBuilderProtocol: WebSocketExtensionBuilder {
    associatedtype Extension: WebSocketExtension
    func build() -> Extension
}

/// A WebSocket extension that is applied without any negotiation with the other side
public struct WebSocketNonNegotiableExtensionBuilder<Extension: WebSocketExtension>: _WebSocketNonNegotiableExtensionBuilderProtocol {
    public static var name: String { String(describing: type(of: Extension.self)) }

    let _build: @Sendable () -> Extension

    init(_ build: @escaping @Sendable () -> Extension) {
        self._build = build
    }

    public func build() -> Extension {
        self._build()
    }
}

extension WebSocketNonNegotiableExtensionBuilder {
    /// construct client request header
    public func clientRequestHeader() -> String { "" }
    /// construct server response header based of client request
    public func serverReponseHeader(to: WebSocketExtensionHTTPParameters) -> String? { nil }
    /// construct server version of extension based of client request
    public func serverExtension(from: WebSocketExtensionHTTPParameters) throws -> (any WebSocketExtension)? { self.build() }
    /// construct client version of extension based of server response
    public func clientExtension(from: WebSocketExtensionHTTPParameters) throws -> (any WebSocketExtension)? { self.build() }
}

extension [any WebSocketExtensionBuilder] {
    ///  Build client extensions from response from WebSocket server
    /// - Parameter responseHeaders: Server response headers
    /// - Returns: Array of client extensions to enable
    public func buildClientExtensions(from responseHeaders: HTTPFields) throws -> [any WebSocketExtension] {
        let serverExtensions = WebSocketExtensionHTTPParameters.parseHeaders(responseHeaders)
        return try self.compactMap {
            try $0.clientExtension(from: serverExtensions)
        }
    }

    ///  Do the client/server WebSocket negotiation based off headers received from the client.
    /// - Parameter requestHeaders: Client request headers
    /// - Returns: Headers to pass back to client and array of server extensions to enable
    public func serverExtensionNegotiation(requestHeaders: HTTPFields) throws -> (HTTPFields, [any WebSocketExtension]) {
        var responseHeaders: HTTPFields = .init()
        let clientHeaders = WebSocketExtensionHTTPParameters.parseHeaders(requestHeaders)
        let extensionResponseHeaders = self.compactMap { $0.serverResponseHeader(to: clientHeaders) }
        responseHeaders.append(contentsOf: extensionResponseHeaders.map { .init(name: .secWebSocketExtensions, value: $0) })
        let extensions = try self.compactMap {
            try $0.serverExtension(from: clientHeaders)
        }
        return (responseHeaders, extensions)
    }
}

/// Build WebSocket extension builder
public struct WebSocketExtensionFactory: Sendable {
    public let build: @Sendable () -> any WebSocketExtensionBuilder

    public init(_ build: @escaping @Sendable () -> any WebSocketExtensionBuilder) {
        self.build = build
    }

    /// Extension to be applied without negotiation with the other side.
    ///
    /// Most extensions involve some form of negotiation between the client and the server
    /// to decide on whether they should be applied and with what parameters. This extension
    /// builder is for the situation where no negotiation is needed or that negotiation has
    /// already occurred.
    ///
    /// - Parameter build: closure creating extension
    /// - Returns: WebSocketExtensionFactory
    public static func nonNegotiatedExtension(_ build: @escaping @Sendable () -> some WebSocketExtension) -> Self {
        .init {
            WebSocketNonNegotiableExtensionBuilder(build)
        }
    }
}
