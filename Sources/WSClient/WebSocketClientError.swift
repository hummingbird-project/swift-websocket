//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

/// Errors returned by ``WebSocketClient``
public struct WebSocketClientError: Swift.Error, Equatable {
    private enum _Internal: Equatable {
        case invalidURL
        case webSocketUpgradeFailed
        case serverProtocolError
        case serverSentMessageTooLarge
        case serverSentDataInconsistentWithMessage
        case proxyHandshakeFailed
        case proxyHandshakeInvalidResponse
        case proxyHandshakeTimeout
    }

    private let value: _Internal
    private init(_ value: _Internal) {
        self.value = value
    }

    /// Provided URL is invalid
    public static var invalidURL: Self { .init(.invalidURL) }
    /// WebSocket upgrade failed.
    public static var webSocketUpgradeFailed: Self { .init(.webSocketUpgradeFailed) }
    /// Server protocol error.
    public static var serverProtocolError: Self { .init(.serverProtocolError) }
    /// Server sent data inconsistent with frame type eg non-utf8 text
    public static var serverSentDataInconsistentWithMessage: Self { .init(.serverSentDataInconsistentWithMessage) }
    /// Server sent a message that was too large
    public static var serverSentMessageTooLarge: Self { .init(.serverSentMessageTooLarge) }
    /// Proxy connection failed.
    public static var proxyHandshakeFailed: Self { .init(.proxyHandshakeFailed) }
    /// Proxy connection return invalid response.
    public static var proxyHandshakeInvalidResponse: Self { .init(.proxyHandshakeInvalidResponse) }
    /// Proxy connection timed out.
    public static var proxyHandshakeTimeout: Self { .init(.proxyHandshakeTimeout) }
}

extension WebSocketClientError: CustomStringConvertible {
    public var description: String {
        switch self.value {
        case .invalidURL: "Invalid URL"
        case .webSocketUpgradeFailed: "WebSocket upgrade failed"
        case .proxyHandshakeFailed: "Proxy handshake failed"
        case .proxyHandshakeInvalidResponse: "Proxy return an invalid response during the handshake"
        case .proxyHandshakeTimeout: "Proxy handshake timed out"
        case .serverProtocolError: "Server protocol error"
        case .serverSentMessageTooLarge: "Server sent a message that was too large"
        case .serverSentDataInconsistentWithMessage: "Server sent data inconsistent with frame type eg non-utf8 text"
        }
    }
}
