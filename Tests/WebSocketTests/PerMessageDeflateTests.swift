//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Logging
import NIOCore
import NIOWebSocket
import Testing

@testable import WSCompression
@testable import WSCore

struct PerMessageDeflateTests {
    func negotiateExtensions(
        client: WebSocketExtensionFactory,
        server: WebSocketExtensionFactory
    ) throws -> (client: PerMessageDeflateExtension, server: PerMessageDeflateExtension) {
        let clientBuilder = client.build()
        let serverBuilder = server.build()
        let clientHTTPParameters = try #require(WebSocketExtensionHTTPParameters(from: clientBuilder.clientRequestHeader()))
        let serverResponse = try #require(serverBuilder.serverReponseHeader(to: clientHTTPParameters))
        let serverHTTPParameters = try #require(WebSocketExtensionHTTPParameters(from: serverResponse))
        let serverExtension = try #require(try serverBuilder.serverExtension(from: clientHTTPParameters))
        let clientExtension = try #require(try clientBuilder.clientExtension(from: serverHTTPParameters))
        let extensions = try (#require(clientExtension as? PerMessageDeflateExtension), #require(serverExtension as? PerMessageDeflateExtension))
        return extensions

    }

    @Test
    func defaultsSettings() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(), server: .perMessageDeflate())
        let bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        let frame = WebSocketFrame(fin: true, opcode: .binary, data: bytes)
        let processedFrame = try await clientExtension.processFrameToSend(frame, context: .init(logger: logger))
        let finalFrame = try await serverExtension.processReceivedFrame(processedFrame, context: .init(logger: logger))
        #expect(finalFrame.data == frame.data)
    }

    @Test
    func singleBuffer() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(), server: .perMessageDeflate())
        let bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        let compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        let decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func smallBuffer() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(), server: .perMessageDeflate())
        let bytes = ByteBuffer(bytes: RandomBytes(length: 16))
        let compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        let decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func multipleBufferContextTakeover() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(), server: .perMessageDeflate())
        var bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        var compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        var decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
        bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func maxWindowBits() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(maxWindow: 11), server: .perMessageDeflate())
        let bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        let compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        let decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func multipleBufferClientNoContextTakeover() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(
            client: .perMessageDeflate(clientNoContextTakeover: true),
            server: .perMessageDeflate()
        )
        var bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        var compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        var decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
        bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        decompressedFrame = try await serverExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func multipleBufferServerNoContextTakeover() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(
            client: .perMessageDeflate(),
            server: .perMessageDeflate(serverNoContextTakeover: true)
        )
        var bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        var compressedFrame = try await serverExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        var decompressedFrame = try await clientExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
        bytes = ByteBuffer(bytes: RandomBytes(length: 2049))
        compressedFrame = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .binary, data: bytes),
            context: .init(logger: logger)
        )
        decompressedFrame = try await clientExtension.processReceivedFrame(compressedFrame, context: .init(logger: logger))
        #expect(decompressedFrame.data == bytes)
    }

    @Test
    func multipleFrames() async throws {
        let logger = Logger(label: "PerMessageDeflate")
        let (clientExtension, serverExtension) = try negotiateExtensions(client: .perMessageDeflate(), server: .perMessageDeflate())
        let bytes1 = ByteBuffer(bytes: RandomBytes(length: 2300))
        let bytes2 = ByteBuffer(bytes: RandomBytes(length: 2700))
        let compressedFrame1 = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: false, opcode: .binary, data: bytes1),
            context: .init(logger: logger)
        )
        let compressedFrame2 = try await clientExtension.processFrameToSend(
            WebSocketFrame(fin: true, opcode: .continuation, data: bytes2),
            context: .init(logger: logger)
        )
        let decompressedFrame1 = try await serverExtension.processReceivedFrame(compressedFrame1, context: .init(logger: logger))
        let decompressedFrame2 = try await serverExtension.processReceivedFrame(compressedFrame2, context: .init(logger: logger))
        #expect(bytes1 == decompressedFrame1.data)
        #expect(bytes2 == decompressedFrame2.data)
    }
}
