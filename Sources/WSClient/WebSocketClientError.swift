//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2024 the Hummingbird authors
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
    }

    private let value: _Internal
    private init(_ value: _Internal) {
        self.value = value
    }

    /// Provided URL is invalid
    public static var invalidURL: Self { .init(.invalidURL) }
    /// WebSocket upgrade failed.
    public static var webSocketUpgradeFailed: Self { .init(.webSocketUpgradeFailed) }
}

extension WebSocketClientError: CustomStringConvertible {
    public var description: String {
        switch self.value {
        case .invalidURL: "Invalid URL"
        case .webSocketUpgradeFailed: "WebSocket upgrade failed"
        }
    }
}
