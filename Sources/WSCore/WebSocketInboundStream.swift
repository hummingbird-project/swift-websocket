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

import NIOConcurrencyHelpers
import NIOCore
import NIOWebSocket

/// Inbound WebSocket data frame AsyncSequence
///
/// This AsyncSequence only returns binary, text and continuation frames. All other frames
/// are dealt with internally
public final class WebSocketInboundStream: AsyncSequence, Sendable {
    public typealias Element = WebSocketDataFrame

    typealias UnderlyingIterator = NIOAsyncChannelInboundStream<WebSocketFrame>.AsyncIterator
    /// Underlying NIOAsyncChannelInboundStream
    let underlyingIterator: UnsafeTransfer<UnderlyingIterator>
    /// Handler for websockets
    let handler: WebSocketHandler
    internal let alreadyIterated: NIOLockedValueBox<Bool>

    init(
        iterator: UnderlyingIterator,
        handler: WebSocketHandler
    ) {
        self.underlyingIterator = .init(iterator)
        self.handler = handler
        self.alreadyIterated = .init(false)
    }

    /// Inbound websocket data AsyncSequence iterator
    public struct AsyncIterator: AsyncIteratorProtocol {
        let handler: WebSocketHandler
        var iterator: UnderlyingIterator
        var closed: Bool

        init(sequence: WebSocketInboundStream, closed: Bool) {
            self.handler = sequence.handler
            self.iterator = sequence.underlyingIterator.wrappedValue
            self.closed = closed
        }

        /// Return next WebSocket frame, while dealing with any other frames
        public mutating func next() async throws -> WebSocketDataFrame? {
            guard !self.closed else { return nil }
            // parse messages coming from inbound
            while let frame = try await self.iterator.next() {
                do {
                    self.handler.logger.trace("Received \(frame.traceDescription)")
                    switch frame.opcode {
                    case .connectionClose:
                        try await self.handler.receivedClose(frame)
                        return nil
                    case .ping:
                        try await self.handler.onPing(frame)
                    case .pong:
                        try await self.handler.onPong(frame)
                    case .text, .binary, .continuation:
                        // apply extensions
                        var frame = frame
                        for ext in self.handler.configuration.extensions.reversed() {
                            frame = try await ext.processReceivedFrame(
                                frame,
                                context: WebSocketExtensionContext(logger: self.handler.logger)
                            )
                        }
                        return .init(from: frame)
                    default:
                        // if we receive a reserved opcode we should fail the connection
                        self.handler.logger.trace("Received reserved opcode", metadata: ["hb.ws.opcode": .stringConvertible(frame.opcode)])
                        throw WebSocketHandler.InternalError.close(.protocolError)
                    }
                } catch {
                    self.handler.logger.trace("Error: \(error)")
                    // catch errors while processing websocket frames so responding close message
                    // can be dealt with
                    let errorCode = WebSocketErrorCode(error)
                    do {
                        try await self.handler.close(code: errorCode)
                        // don't propagate error if channel is already closed
                    } catch ChannelError.ioOnClosedChannel {}
                }
            }

            return nil
        }

        /// Return next WebSocket messsage, while dealing with any other frames
        ///
        /// A WebSocket message can be fragmented across multiple WebSocket frames. This
        /// function collates fragmented frames until it has a full message
        public mutating func nextMessage(maxSize: Int) async throws -> WebSocketMessage? {
            var frameSequence: WebSocketFrameSequence
            // parse first frame
            guard let frame = try await self.next() else { return nil }
            switch frame.opcode {
            case .text, .binary:
                frameSequence = .init(frame: frame)
                if frame.fin {
                    return frameSequence.message
                }
            default:
                try await self.handler.close(code: .protocolError)
                return nil
            }
            // parse continuation frames until we get a frame with a FIN flag
            while let frame = try await self.next() {
                guard frame.opcode == .continuation else {
                    try await self.handler.close(code: .protocolError)
                    return nil
                }
                guard frameSequence.size + frame.data.readableBytes <= maxSize else {
                    try await self.handler.close(code: .messageTooLarge)
                    return nil
                }
                frameSequence.append(frame)
                if frame.fin {
                    return frameSequence.message
                }
            }
            return nil
        }
    }

    /// Creates the Asynchronous Iterator
    public func makeAsyncIterator() -> AsyncIterator {
        // verify if an iterator has already been created. If it has then create an
        // iterator that returns nothing. This could be a precondition failure (currently
        // an assert) as you should not be allowed to do this.
        let done = self.alreadyIterated.withLockedValue {
            assert($0 == false, "Can only create iterator from WebSocketInboundStream once")
            let done = $0
            $0 = true
            return done
        }
        return .init(sequence: self, closed: done)
    }
}

/// Extend WebSocketFrame to provide debug description for trace logs
extension WebSocketFrame {
    var traceDescription: String {
        var flags: [String] = []
        if self.fin {
            flags.append("FIN")
        }
        if self.rsv1 {
            flags.append("RSV1")
        }
        if self.rsv2 {
            flags.append("RSV2")
        }
        if self.rsv3 {
            flags.append("RSV3")
        }
        let unmaskedData = self.unmaskedData
        var desc = "["
        let slice = unmaskedData.getSlice(at: unmaskedData.readerIndex, length: min(24, unmaskedData.readableBytes))
        for byte in slice!.readableBytesView {
            let hexByte = String(byte, radix: 16)
            desc += " \(hexByte.count == 1 ? "0" : "")\(hexByte)"
        }
        if unmaskedData.readableBytes > 24 {
            desc += " ..."
        }
        desc += " ]"

        return "WebSocketFrame(\(self.opcode), flags: \(flags.joined(separator: ",")), data: {length: \(unmaskedData.readableBytes), bytes: \(desc)})"
    }
}
