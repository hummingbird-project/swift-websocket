//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023-2025 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import WSCore

/// Configuration for a client connecting to a WebSocket
public struct WebSocketClientConfiguration: Sendable {
    /// Max websocket frame size that can be sent/received
    public var maxFrameSize: Int
    /// Additional headers to be sent with the initial HTTP request
    public var additionalHeaders: HTTPFields
    /// WebSocket extensions
    public var extensions: [any WebSocketExtensionBuilder]
    /// Close timeout
    public var closeTimeout: Duration
    /// Automatic ping setup
    public var autoPing: AutoPingSetup
    /// Should text be validated to be UTF8
    public var validateUTF8: Bool
    /// Hostname used during TLS handshake
    public var sniHostname: String?

    /// Initialize WebSocketClient configuration
    ///   - Paramters
    ///     - maxFrameSize: Max websocket frame size that can be sent/received
    ///     - additionalHeaders: Additional headers to be sent with the initial HTTP request
    ///     - extensions: WebSocket extensions
    ///     - autoPing: Automatic Ping configuration
    ///     - validateUTF8: Should text be checked to see if it is valid UTF8
    @_disfavoredOverload
    public init(
        maxFrameSize: Int = (1 << 14),
        additionalHeaders: HTTPFields = .init(),
        extensions: [WebSocketExtensionFactory] = [],
        closeTimeout: Duration = .seconds(15),
        autoPing: AutoPingSetup = .disabled,
        validateUTF8: Bool = false
    ) {
        self.maxFrameSize = maxFrameSize
        self.additionalHeaders = additionalHeaders
        self.extensions = extensions.map { $0.build() }
        self.closeTimeout = closeTimeout
        self.autoPing = autoPing
        self.validateUTF8 = validateUTF8
        self.sniHostname = nil
    }

    /// Initialize WebSocketClient configuration
    ///   - Paramters
    ///     - maxFrameSize: Max websocket frame size that can be sent/received
    ///     - additionalHeaders: Additional headers to be sent with the initial HTTP request
    ///     - extensions: WebSocket extensions
    ///     - autoPing: Automatic Ping configuration
    ///     - validateUTF8: Should text be checked to see if it is valid UTF8
    ///     - sniHostname: Hostname used during TLS handshake
    public init(
        maxFrameSize: Int = (1 << 14),
        additionalHeaders: HTTPFields = .init(),
        extensions: [WebSocketExtensionFactory] = [],
        closeTimeout: Duration = .seconds(15),
        autoPing: AutoPingSetup = .disabled,
        validateUTF8: Bool = false,
        sniHostname: String? = nil
    ) {
        self.maxFrameSize = maxFrameSize
        self.additionalHeaders = additionalHeaders
        self.extensions = extensions.map { $0.build() }
        self.closeTimeout = closeTimeout
        self.autoPing = autoPing
        self.validateUTF8 = validateUTF8
        self.sniHostname = sniHostname
    }
}
