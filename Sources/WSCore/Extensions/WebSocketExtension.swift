//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HTTPTypes
import Logging
import NIOCore
import NIOWebSocket

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
    /// Reserved bits extension uses
    var reservedBits: WebSocketFrame.ReservedBits { get }
    /// shutdown extension
    func shutdown() async
}

extension WebSocketExtension {
    /// Reserved bits extension uses (default is none)
    public var reservedBits: WebSocketFrame.ReservedBits { .init() }
}
