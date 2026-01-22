//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2024-2026 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Errors returned by ``WebSocketClient``
public struct WebSocketClientError: Swift.Error, Equatable {
    private enum _Internal: Equatable {
        case invalidURL
        case webSocketUpgradeFailed
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
        }
    }
}
