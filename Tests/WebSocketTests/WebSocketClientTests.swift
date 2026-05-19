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
@_spi(WSInternal) import WSCore

struct WebSocketClientTests {
    func createRandomBuffer(size: Int) -> ByteBuffer {
        // create buffer
        var data = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            data[i] = UInt8.random(in: 0...255)
        }
        return ByteBuffer(bytes: data)
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
        return try await withThrowingTaskGroup(of: TestResult.self) { group in
            group.addTask {
                do {
                    let result = try await WebSocketClient.test(channel: channel, configuration: configuration, logger: logger, handler: handler)
                    return .client(.success(result))
                } catch {
                    return .client(.failure(error))
                }
            }
            group.addTask {
                do {
                    try await server(channel)
                    try await channel.writeCloseFrame(code: .normalClosure)
                    let outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
                    #expect(outbound.opcode == .connectionClose)
                    try await channel.close()
                } catch {
                    try await channel.writeCloseFrame(code: .unexpectedServerError)
                    let outbound = try await channel.waitForOutboundWrite(as: WebSocketFrame.self)
                    #expect(outbound.opcode == .connectionClose)
                    try await channel.close()
                }
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
    func binaryMessageWriter() async throws {
        var logger = Logger(label: "binaryMessageWriter")
        logger.logLevel = .trace

        let buffer = createRandomBuffer(size: 3072)
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

        let (stream, cont) = AsyncStream.makeStream(of: Void.self)
        let closeFrame = try await withTestWebSocketServer(configuration: .init(maxFrameSize: 1024), logger: logger) { inbound, outbound, _ in
            cont.finish()
            for try await _ in inbound {}
        } server: { channel in
            _ = await stream.first { _ in true }
            throw CancellationError()
        }
        #expect(closeFrame?.closeCode == .unexpectedServerError)
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
