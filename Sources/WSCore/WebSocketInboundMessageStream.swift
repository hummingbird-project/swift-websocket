//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOWebSocket

/// Inbound WebSocket messages AsyncSequence.
public struct WebSocketInboundMessageStream: AsyncSequence, Sendable {
    public typealias Element = WebSocketMessage

    let inboundStream: WebSocketInboundStream
    let maxSize: Int

    public struct AsyncIterator: AsyncIteratorProtocol {
        var frameIterator: WebSocketInboundStream.AsyncIterator
        let maxSize: Int

        public mutating func next() async throws -> Element? {
            try await self.frameIterator.nextMessage(maxSize: self.maxSize)
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        .init(frameIterator: self.inboundStream.makeAsyncIterator(), maxSize: self.maxSize)
    }
}

extension WebSocketInboundStream {
    /// Convert to AsyncSequence of WebSocket messages
    ///
    /// A WebSocket message can be fragmented across multiple WebSocket frames. This
    /// converts the inbound stream of WebSocket data frames into a sequence of WebSocket
    /// messages.
    ///
    /// - Parameter maxSize: The maximum size of message we are allowed to read
    public func messages(maxSize: Int) -> WebSocketInboundMessageStream {
        .init(inboundStream: self, maxSize: maxSize)
    }
}
