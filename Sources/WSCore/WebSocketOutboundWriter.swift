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

/// Outbound websocket writer
public struct WebSocketOutboundWriter: Sendable {
    /// WebSocket frame that can be written
    public enum OutboundFrame: Sendable {
        /// Text frame
        case text(String)
        /// Binary data frame
        case binary(ByteBuffer)
        /// Unsolicited pong frame
        case pong
        /// A custom frame not supported by the above
        case custom(WebSocketFrame)
    }

    let handler: WebSocketHandler

    /// Write WebSocket frame
    public func write(_ frame: OutboundFrame) async throws {
        try Task.checkCancellation()
        switch frame {
        case .binary(let buffer):
            // send binary data
            try await self.handler.write(frame: .init(fin: true, opcode: .binary, data: buffer))
        case .text(let string):
            // send text based data
            let buffer = ByteBuffer(string: string)
            try await self.handler.write(frame: .init(fin: true, opcode: .text, data: buffer))
        case .pong:
            // send unexplained pong as a heartbeat
            try await self.handler.write(frame: .init(fin: true, opcode: .pong, data: .init()))
        case .custom(let frame):
            // send custom WebSocketFrame
            try await self.handler.write(frame: frame)
        }
    }

    /// Send close control frame.
    ///
    /// In most cases calling this is unnecessary as the WebSocket handling code will do
    /// this for you automatically, but if you want to send a custom close code or reason
    /// use this function.
    ///
    /// After calling this function you should not send anymore data
    /// - Parameters:
    ///   - closeCode: Close code
    ///   - reason: Close reason string
    public func close(_ closeCode: WebSocketErrorCode, reason: String?) async throws {
        try await self.handler.close(code: closeCode, reason: reason)
    }

    /// Write WebSocket message as a series as frames
    public struct MessageWriter {
        let opcode: WebSocketOpcode
        let handler: WebSocketHandler
        var prevFrame: WebSocketFrame?

        /// Write string to WebSocket frame
        public mutating func callAsFunction(_ text: String) async throws {
            let buffer = ByteBuffer(string: text)
            try await self.write(buffer, opcode: self.opcode)
        }

        /// Write buffer to WebSocket frame
        public mutating func callAsFunction(_ buffer: ByteBuffer) async throws {
            try await self.write(buffer, opcode: self.opcode)
        }

        mutating func write(_ data: ByteBuffer, opcode: WebSocketOpcode) async throws {
            if let prevFrame {
                try await self.handler.write(frame: prevFrame)
                self.prevFrame = .init(fin: false, opcode: .continuation, data: data)
            } else {
                self.prevFrame = .init(fin: false, opcode: opcode, data: data)
            }
        }

        func finish() async throws {
            if var prevFrame {
                prevFrame.fin = true
                try await self.handler.write(frame: prevFrame)
            }
        }
    }

    /// Write a single WebSocket text message as a series of fragmented frames
    /// - Parameter write: Function writing frames
    public func withTextMessageWriter<Value>(_ write: (inout MessageWriter) async throws -> Value) async throws -> Value {
        var writer = MessageWriter(opcode: .text, handler: self.handler)
        let value: Value
        do {
            value = try await write(&writer)
        } catch {
            try await writer.finish()
            throw error
        }
        try await writer.finish()
        return value
    }

    /// Write a single WebSocket binary message as a series of fragmented frames
    /// - Parameter write: Function writing frames
    public func withBinaryMessageWriter<Value>(_ write: (inout MessageWriter) async throws -> Value) async throws -> Value {
        var writer = MessageWriter(opcode: .binary, handler: self.handler)
        let value: Value
        do {
            value = try await write(&writer)
        } catch {
            try await writer.finish()
            throw error
        }
        try await writer.finish()
        return value
    }
}
