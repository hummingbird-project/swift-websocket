//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Logging
import NIOCore
import NIOEmbedded
import NIOWebSocket
import Testing
import WSClient

@testable import WSCore

struct WebSocketClientTests {
    struct CloseError: Error {
        let errorCode: WebSocketErrorCode
        let reason: String?
    }

    @discardableResult func withTestWebSocketServer(
        configuration: WebSocketClientConfiguration = .init(),
        logger: Logger,
        handler: @escaping WebSocketDataHandler<WebSocketClient.Context>,
        server: @Sendable @escaping (NIOAsyncTestingChannel) async throws -> Void
    ) async throws -> WebSocketCloseFrame? {
        enum TestResult {
            case client(Result<WebSocketCloseFrame?, any Error>)
            case server
        }
        let channel = NIOAsyncTestingChannel()
        let (stream, cont) = AsyncStream.makeStream(of: Void.self)

        return try await withThrowingTaskGroup(of: TestResult.self) { group in
            group.addTask {
                do {
                    let result = try await WebSocketClient.test(channel: channel, configuration: configuration, logger: logger) {
                        cont.yield()
                        try await handler($0, $1, $2)
                    }
                    return .client(.success(result))
                } catch {
                    return .client(.failure(error))
                }
            }
            group.addTask {
                await stream.first { _ in true }
                let closeFrame: (WebSocketErrorCode, String?)
                do {
                    try await server(channel)
                    closeFrame = (.normalClosure, nil)
                } catch let error as CloseError {
                    closeFrame = (error.errorCode, error.reason)
                } catch {
                    closeFrame = (.unexpectedServerError, nil)
                }
                try await channel.writeCloseFrame(code: closeFrame.0, reason: closeFrame.1)
                let outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
                #expect(outbound.opcode == .connectionClose)
                // ignore errors from close as it appears NIOAsyncTestingChannel doesn't support half closure
                try? await channel.close(mode: .input)
                return .server
            }
            while let result = try await group.next() {
                switch result {
                case .client(let result):
                    group.cancelAll()
                    return try result.get()
                case .server:
                    break
                }
            }
            fatalError("Cannot reach here")
        }
    }

    @Test
    func read() async throws {
        var logger = Logger(label: "read")
        logger.logLevel = .trace

        try await withTestWebSocketServer(logger: logger) { inbound, _, _ in
            for try await frame in inbound {
                #expect(frame.opcode == .text)
                #expect(frame.data == .init(string: "Hello!"))
            }
        } server: { channel in
            try await channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: .init(string: "Hello!")))
        }
    }

    @Test
    func readMessage() async throws {
        var logger = Logger(label: "readMessage")
        logger.logLevel = .trace

        try await withTestWebSocketServer(logger: logger) { inbound, _, _ in
            for try await message in inbound.messages(maxSize: .max) {
                #expect(message == .text("Hello, world!"))
            }
        } server: { channel in
            try await channel.writeInbound(WebSocketFrame(fin: false, opcode: .text, data: .init(string: "Hello,")))
            try await channel.writeInbound(WebSocketFrame(fin: true, opcode: .continuation, data: .init(string: " world!")))
        }
    }

    @Test
    func write() async throws {
        var logger = Logger(label: "write")
        logger.logLevel = .trace

        try await withTestWebSocketServer(logger: logger) { inbound, outbound, _ in
            try await outbound.write(.text("Hello!"))
        } server: { channel in
            let outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .text)
            #expect(outbound.data == .init(string: "Hello!"))
        }
    }

    @Test
    func textMessageWriter() async throws {
        var logger = Logger(label: "textMessageWriter")
        logger.logLevel = .trace

        try await withTestWebSocketServer(logger: logger) { inbound, outbound, _ in
            try await outbound.withTextMessageWriter { writer in
                try await writer("Hello,")
                try await writer(" world!")
            }
        } server: { channel in
            var outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .text)
            #expect(outbound.fin == false)
            #expect(outbound.data == .init(string: "Hello,"))
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == true)
            #expect(outbound.data == .init(string: " world!"))
        }
    }

    @Test
    func writeTextMessage() async throws {
        var logger = Logger(label: "textMessageWriter")
        logger.logLevel = .trace

        let textBuffer = String((0..<3000).map { _ in "abcdefghijkl".randomElement()! })
        try await withTestWebSocketServer(configuration: .init(maxFrameSize: 1024), logger: logger) { inbound, outbound, _ in
            try await outbound.writeTextMessage(textBuffer)
        } server: { channel in
            var string = ""
            var outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .text)
            #expect(outbound.fin == false)
            string += String(buffer: outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == false)
            string += String(buffer: outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == true)
            string += String(buffer: outbound.data)
            #expect(string == textBuffer)
        }
    }

    @Test
    func writeBinaryMessage() async throws {
        var logger = Logger(label: "writeBinaryMessage")
        logger.logLevel = .trace

        let buffer = ByteBuffer(bytes: RandomBytes(length: 3500))
        try await withTestWebSocketServer(configuration: .init(maxFrameSize: 1024), logger: logger) { inbound, outbound, _ in
            try await outbound.writeBinaryMessage(buffer)
        } server: { channel in
            var buffer2 = ByteBuffer()
            var outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .binary)
            #expect(outbound.fin == false)
            buffer2.writeImmutableBuffer(outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == false)
            buffer2.writeImmutableBuffer(outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == false)
            buffer2.writeImmutableBuffer(outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == true)
            buffer2.writeImmutableBuffer(outbound.data)
            #expect(buffer2 == buffer)
        }
    }

    @Test
    func binaryMessageWriter() async throws {
        var logger = Logger(label: "binaryMessageWriter")
        logger.logLevel = .trace

        let buffer = ByteBuffer(bytes: RandomBytes(length: 3072))
        try await withTestWebSocketServer(logger: logger) { inbound, outbound, _ in
            try await outbound.withBinaryMessageWriter { writer in
                var buffer = buffer
                try await writer(buffer.readSlice(length: 1024)!)
                try await writer(buffer.readSlice(length: 1024)!)
                try await writer(buffer.readSlice(length: 1024)!)
            }
        } server: { channel in
            var outputBuffer = ByteBuffer()
            var outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .binary)
            #expect(outbound.fin == false)
            outputBuffer.writeImmutableBuffer(outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == false)
            outputBuffer.writeImmutableBuffer(outbound.data)
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .continuation)
            #expect(outbound.fin == true)
            outputBuffer.writeImmutableBuffer(outbound.data)
            #expect(outputBuffer == buffer)
        }
    }

    @Test
    func serverClosedConnection() async throws {
        var logger = Logger(label: "serverClosedConnection")
        logger.logLevel = .trace

        let closeFrame = try await withTestWebSocketServer(logger: logger) { inbound, outbound, _ in
            for try await _ in inbound {}
        } server: { channel in
            throw CloseError(errorCode: .unacceptableData, reason: "Don't like it")
        }
        #expect(closeFrame?.closeCode == .unacceptableData)
        #expect(closeFrame?.reason == "Don't like it")
    }

    @Test
    func ping() async throws {
        let logger = {
            var logger = Logger(label: "ping")
            logger.logLevel = .trace
            return logger
        }()

        try await withTestWebSocketServer(logger: logger) { inbound, outbound, context in
            context.logger.info("START CLIENT")
            for try await _ in inbound {}
        } server: { channel in
            logger.info("START SERVER")
            let pingBuffer = ByteBuffer(bytes: (0..<16).map { _ in UInt8.random(in: 0...255) })
            try await channel.writeInbound(WebSocketFrame(fin: true, opcode: .ping, data: pingBuffer))
            let outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .pong)
            #expect(outbound.fin == true)
            #expect(outbound.data == pingBuffer)
        }
    }

    @Test
    func autoPing() async throws {
        var logger = Logger(label: "autoPing")
        logger.logLevel = .trace

        try await withTestWebSocketServer(
            configuration: .init(autoPing: .enabled(timePeriod: .milliseconds(200))),
            logger: logger
        ) { inbound, outbound, _ in
            for try await _ in inbound {}
        } server: { channel in
            // respond to first ping to see if we receive another, don't respond to second ping
            var outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .ping)
            #expect(outbound.fin == true)
            try await channel.writeInbound(WebSocketFrame(fin: true, opcode: .pong, data: outbound.data))
            outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
            #expect(outbound.opcode == .ping)
            // If we don't cancel before 60 seconds has passed record issue
            try await Task.sleep(for: .seconds(60))
            Issue.record("Should have cancelled the server as the client ping timed out")
        }
    }

    @Test
    func serverMessageTooLargeError() async throws {
        var logger = Logger(label: "messageTooLarge")
        logger.logLevel = .trace

        await #expect(throws: WebSocketClientError.serverSentMessageTooLarge) {
            try await withTestWebSocketServer(
                configuration: .init(maxFrameSize: 1024),
                logger: logger
            ) { inbound, outbound, _ in
                for try await _ in inbound.messages(maxSize: 1500) {}
            } server: { channel in
                try await channel.writeInbound(
                    WebSocketFrame(fin: false, opcode: .binary, data: .init(bytes: RandomBytes(length: 1024)))
                )
                try await channel.writeInbound(
                    WebSocketFrame(fin: true, opcode: .continuation, data: .init(bytes: RandomBytes(length: 1024)))
                )
            }
        }
    }

    @Test
    func serverProtocolError() async throws {
        var logger = Logger(label: "messageTooLarge")
        logger.logLevel = .trace

        await #expect(throws: WebSocketClientError.serverProtocolError) {
            try await withTestWebSocketServer(
                configuration: .init(maxFrameSize: 1024),
                logger: logger
            ) { inbound, outbound, _ in
                for try await _ in inbound.messages(maxSize: 1500) {}
            } server: { channel in
                try await channel.writeInbound(
                    WebSocketFrame(fin: false, opcode: .binary, data: .init(bytes: RandomBytes(length: 1024)))
                )
                try await channel.writeInbound(
                    WebSocketFrame(fin: true, opcode: .binary, data: .init(bytes: RandomBytes(length: 1024)))
                )
            }
        }
    }

    @Test
    func serverInconsistentDataError() async throws {
        var logger = Logger(label: "messageTooLarge")
        logger.logLevel = .trace

        await #expect(throws: WebSocketClientError.serverSentDataInconsistentWithMessage) {
            try await withTestWebSocketServer(
                configuration: .init(validateUTF8: true),
                logger: logger
            ) { inbound, outbound, _ in
                for try await _ in inbound.messages(maxSize: 1024) {}
            } server: { channel in
                try await channel.writeInbound(
                    WebSocketFrame(fin: true, opcode: .text, data: .init(repeating: 0xff, count: 16))
                )
            }
        }
    }
}

extension NIOAsyncTestingChannel {
    fileprivate func writeCloseFrame(code: WebSocketErrorCode = .normalClosure, reason: String? = nil) async throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 2 + (reason?.utf8.count ?? 0))
        buffer.write(webSocketErrorCode: code)
        if let reason {
            buffer.writeString(reason)
        }
        try await self.writeInbound(WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer))
    }
}
