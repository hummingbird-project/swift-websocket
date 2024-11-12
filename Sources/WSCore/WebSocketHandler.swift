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

import Logging
import NIOCore
import NIOWebSocket
import ServiceLifecycle

/// WebSocket type
public enum WebSocketType: Sendable {
    case client
    case server
}

/// Automatic ping setup
public struct AutoPingSetup: Sendable {
    enum Internal {
        case disabled
        case enabled(timePeriod: Duration)
    }

    internal let value: Internal
    internal init(_ value: Internal) {
        self.value = value
    }

    /// disable auto ping
    public static var disabled: Self { .init(.disabled) }
    /// send ping with fixed period
    public static func enabled(timePeriod: Duration) -> Self { .init(.enabled(timePeriod: timePeriod)) }
}

/// Close frame that caused WebSocket close
public struct WebSocketCloseFrame: Sendable {
    // status code indicating a reason for closure
    public let closeCode: WebSocketErrorCode
    // close reason
    public let reason: String?
}

/// Handler processing raw WebSocket packets. Used by WebSocket transports
///
/// Manages ping, pong and close messages. Collates data and text messages into final frame
/// and passes them onto the ``WebSocketDataHandler`` data handler setup by the user.
///
/// SPI WSInternal is used to make the WebSocket Handler available to both client and server
/// implementations
@_spi(WSInternal) public actor WebSocketHandler {
    enum InternalError: Error {
        case close(WebSocketErrorCode)
    }

    enum CloseState {
        case open
        case closing
        case closed(WebSocketCloseFrame?)
    }

    @_spi(WSInternal) public struct Configuration: Sendable {
        let extensions: [any WebSocketExtension]
        let autoPing: AutoPingSetup

        @_spi(WSInternal) public init(extensions: [any WebSocketExtension], autoPing: AutoPingSetup) {
            self.extensions = extensions
            self.autoPing = autoPing
        }
    }

    let channel: Channel
    var outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>
    let type: WebSocketType
    let configuration: Configuration
    let logger: Logger
    var stateMachine: WebSocketStateMachine

    private init(
        channel: Channel,
        outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>,
        type: WebSocketType,
        configuration: Configuration,
        context: some WebSocketContext
    ) {
        self.channel = channel
        self.outbound = outbound
        self.type = type
        self.configuration = configuration
        self.logger = context.logger
        self.stateMachine = .init(autoPingSetup: configuration.autoPing)
    }

    @_spi(WSInternal) public static func handle<Context: WebSocketContext>(
        type: WebSocketType,
        configuration: Configuration,
        asyncChannel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>,
        context: Context,
        handler: @escaping WebSocketDataHandler<Context>
    ) async throws -> WebSocketCloseFrame? {
        defer {
            context.logger.debug("Closed WebSocket")
        }
        do {
            let rt = try await asyncChannel.executeThenClose { inbound, outbound in
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: WebSocketCloseFrame.self) { group in
                        let webSocketHandler = Self(channel: asyncChannel.channel, outbound: outbound, type: type, configuration: configuration, context: context)
                        if case .enabled = configuration.autoPing.value {
                            /// Add task sending ping frames every so often and verifying a pong frame was sent back
                            group.addTask {
                                try await webSocketHandler.runAutoPingLoop()
                                return .init(closeCode: .goingAway, reason: "Ping timeout")
                            }
                        }
                        let rt = try await webSocketHandler.handle(type: type, inbound: inbound, outbound: outbound, handler: handler, context: context)
                        group.cancelAll()
                        return rt
                    }
                } onCancel: {
                    Task {
                        try await asyncChannel.channel.close(mode: .input)
                    }
                }
            }
            return rt
        } catch let error as NIOAsyncWriterError {
            // ignore already finished errors
            if error == NIOAsyncWriterError.alreadyFinished() { return nil }
            throw error
        }
    }

    func handle<Context: WebSocketContext>(
        type: WebSocketType,
        inbound: NIOAsyncChannelInboundStream<WebSocketFrame>,
        outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>,
        handler: @escaping WebSocketDataHandler<Context>,
        context: Context
    ) async throws -> WebSocketCloseFrame? {
        try await withGracefulShutdownHandler {
            let webSocketOutbound = WebSocketOutboundWriter(handler: self)
            var inboundIterator = inbound.makeAsyncIterator()
            let webSocketInbound = WebSocketInboundStream(
                iterator: inboundIterator,
                handler: self
            )
            let closeCode: WebSocketErrorCode
            var clientError: Error?
            do {
                // handle websocket data and text
                try await handler(webSocketInbound, webSocketOutbound, context)
                closeCode = .normalClosure
            } catch InternalError.close(let code) {
                closeCode = code
            } catch {
                clientError = error
                closeCode = .unexpectedServerError
            }
            do {
                try await self.close(code: closeCode)
                if case .closing = self.stateMachine.state {
                    // Close handshake. Wait for responding close or until inbound ends
                    while let frame = try await inboundIterator.next() {
                        if case .connectionClose = frame.opcode {
                            try await self.receivedClose(frame)
                            break
                        }
                    }
                }
                // don't propagate error if channel is already closed
            } catch ChannelError.ioOnClosedChannel {}
            if type == .client, let clientError {
                throw clientError
            }
        } onGracefulShutdown: {
            Task {
                try? await self.close(code: .normalClosure)
            }
        }
        return switch self.stateMachine.state {
        case .closed(let code): code
        default: nil
        }
    }

    func runAutoPingLoop() async throws {
        let period = self.stateMachine.pingTimePeriod
        try await Task.sleep(for: period)
        while true {
            switch self.stateMachine.sendPing() {
            case .sendPing(let buffer):
                try await self.write(frame: .init(fin: true, opcode: .ping, data: buffer))

            case .wait(let time):
                try await Task.sleep(for: time)

            case .closeConnection(let errorCode):
                try await self.sendClose(code: errorCode, reason: "Ping timeout")
                try await self.channel.close(mode: .input)
                return

            case .stop:
                return
            }
        }
    }

    /// Send WebSocket frame
    func write(frame: WebSocketFrame) async throws {
        var frame = frame
        do {
            for ext in self.configuration.extensions {
                frame = try await ext.processFrameToSend(
                    frame,
                    context: WebSocketExtensionContext(logger: self.logger)
                )
            }
        } catch {
            self.logger.debug("Closing as we failed to generate valid frame data")
            throw WebSocketHandler.InternalError.close(.unexpectedServerError)
        }
        // Set mask key if client
        if self.type == .client {
            frame.maskKey = self.makeMaskKey()
        }
        try await self.outbound.write(frame)

        self.logger.trace("Sent \(frame.traceDescription)")
    }

    func finish() {
        self.outbound.finish()
    }

    /// Respond to ping
    func onPing(_ frame: WebSocketFrame) async throws {
        // a ping frame without the FIN flag is illegal
        guard frame.fin else {
            self.channel.close(promise: nil)
            return
        }
        switch self.stateMachine.receivedPing(frameData: frame.unmaskedData) {
        case .pong(let frameData):
            try await self.write(frame: .init(fin: true, opcode: .pong, data: frameData))

        case .protocolError:
            try await self.close(code: .protocolError)

        case .doNothing:
            break
        }
    }

    /// Respond to pong
    func onPong(_ frame: WebSocketFrame) async throws {
        // a pong frame without the FIN flag is illegal
        guard frame.fin else {
            self.channel.close(promise: nil)
            return
        }
        self.stateMachine.receivedPong(frameData: frame.unmaskedData)
    }

    /// Send close
    func close(code: WebSocketErrorCode = .normalClosure, reason: String? = nil) async throws {
        switch self.stateMachine.close() {
        case .sendClose:
            try await self.sendClose(code: code, reason: reason)
            // Only server should initiate a connection close. Clients should wait for the
            // server to close the connection when it receives the WebSocket close packet
            // See https://www.rfc-editor.org/rfc/rfc6455#section-7.1.1
            if self.type == .server {
                self.outbound.finish()
            }
        case .doNothing:
            break
        }
    }

    func receivedClose(_ frame: WebSocketFrame) async throws {
        switch self.stateMachine.receivedClose(frameData: frame.unmaskedData) {
        case .sendClose(let errorCode):
            try await self.sendClose(code: errorCode, reason: nil)
            // Only server should initiate a connection close. Clients should wait for the
            // server to close the connection when it receives the WebSocket close packet
            // See https://www.rfc-editor.org/rfc/rfc6455#section-7.1.1
            if self.type == .server {
                self.outbound.finish()
            }
        case .doNothing:
            break
        }
    }

    private func sendClose(code: WebSocketErrorCode = .normalClosure, reason: String? = nil) async throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 2 + (reason?.utf8.count ?? 0))
        buffer.write(webSocketErrorCode: code)
        if let reason {
            buffer.writeString(reason)
        }

        try await self.write(frame: .init(fin: true, opcode: .connectionClose, data: buffer))
    }

    /// Make mask key to be used in WebSocket frame
    private func makeMaskKey() -> WebSocketMaskingKey? {
        guard self.type == .client else { return nil }
        let bytes: [UInt8] = (0...3).map { _ in UInt8.random(in: .min ... .max) }
        return WebSocketMaskingKey(bytes)
    }
}

extension WebSocketErrorCode {
    init(_ error: any Error) {
        switch error {
        case NIOWebSocketError.invalidFrameLength:
            self = .messageTooLarge
        case NIOWebSocketError.fragmentedControlFrame,
             NIOWebSocketError.multiByteControlFrameLength:
            self = .protocolError
        case WebSocketHandler.InternalError.close(let error):
            self = error
        default:
            self = .unexpectedServerError
        }
    }
}
