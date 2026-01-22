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
import NIOEmbedded
import NIOHTTP1
import NIOSSL
import Testing

@testable import NIOWebSocket
@testable import WSClient

let magicWebSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

struct WebSocketClientTests {
    /// Read HTTP headers from request. Assumes request has no body
    func readHTTPRequest(from buffer: ByteBuffer) -> (String, HTTPFields) {
        let text = String(buffer: buffer)
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        let fields: [(HTTPField.Name, String)] = lines.dropFirst().compactMap { line in
            let values = line.split(separator: ":", maxSplits: 1)
            guard values.count == 2 else { return nil }
            guard let field = HTTPField.Name(String(values[0])) else { return nil }
            return (field, String(values[1].trimmingPrefix(while: \.isWhitespace)))
        }
        var headers = HTTPFields()
        for field in fields {
            headers[field.0] = field.1
        }
        return (String(lines[0]), headers)
    }

    @Test
    func testUpgrade() async throws {
        let logger = {
            var logger = Logger(label: "client")
            logger.logLevel = .trace
            return logger
        }()
        let channel = NIOAsyncTestingChannel()
        let wsChannel = try WebSocketClientChannel(
            handler: { _, _, _ in },
            url: "ws://localhost:8080/ws",
            configuration: .init(),
            tlsConfiguration: nil,
            proxySettings: nil
        )
        let setup = try await channel.eventLoop.submit {
            wsChannel.setup(channel: channel, logger: logger)
        }.get()
        try await channel.connect(to: try SocketAddress(ipAddress: "127.0.0.1", port: 8080)).get()
        let outbound = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        let (head, headers) = readHTTPRequest(from: outbound)
        #expect(head == "GET /ws HTTP/1.1")
        #expect(headers[.host] == "localhost:8080")
        #expect(headers[.origin] == "ws://localhost")
        #expect(headers[.connection] == "upgrade")
        #expect(headers[.upgrade] == "websocket")
        #expect(headers[.secWebSocketVersion] == "13")
        let key = try #require(headers[.secWebSocketKey])

        var hasher = SHA1()
        hasher.update(string: key)
        hasher.update(string: magicWebSocketGUID)
        let acceptValue = String(_base64Encoding: hasher.finish())

        let response = "HTTP/1.1 101 Switching Protocols\r\nConnection: upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: \(acceptValue)\r\n\r\n"
        try await channel.writeInbound(ByteBuffer(string: response))

        let value = try await setup.get()
        let upgradeResult = try await value.get()
        guard case .websocket(_, _) = upgradeResult else {
            Issue.record()
            return
        }
    }

    @Test
    func testHTTPProxyUpgrade() async throws {
        let logger = {
            var logger = Logger(label: "client")
            logger.logLevel = .trace
            return logger
        }()
        let channel = NIOAsyncTestingChannel()
        let wsChannel = try WebSocketClientChannel(
            handler: { _, _, _ in },
            url: "ws://localhost:8080/ws",
            configuration: .init(),
            tlsConfiguration: nil,
            proxySettings: .init(host: "localhost", port: 8081, type: .http(connectHeaders: [.userAgent: "WSTests"]), timeout: .seconds(30))
        )
        let setup = try await channel.eventLoop.submit {
            wsChannel.setup(channel: channel, logger: logger)
        }.get()
        try await channel.connect(to: try SocketAddress(ipAddress: "127.0.0.1", port: 8081)).get()
        var outbound = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        let (proxyHead, proxyHeaders) = readHTTPRequest(from: outbound)
        #expect(proxyHead == "CONNECT localhost:8080 HTTP/1.1")
        #expect(proxyHeaders[.userAgent] == "WSTests")
        let proxyResponse = "HTTP/1.1 200 Ok\r\n\r\n"
        try await channel.writeInbound(ByteBuffer(string: proxyResponse))

        outbound = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        let (head, headers) = readHTTPRequest(from: outbound)
        #expect(head == "GET /ws HTTP/1.1")
        #expect(headers[.origin] == "ws://localhost")
        #expect(headers[.connection] == "upgrade")
        #expect(headers[.upgrade] == "websocket")
        #expect(headers[.secWebSocketVersion] == "13")
        let key = try #require(headers[.secWebSocketKey])

        var hasher = SHA1()
        hasher.update(string: key)
        hasher.update(string: magicWebSocketGUID)
        let acceptValue = String(_base64Encoding: hasher.finish())

        let response = "HTTP/1.1 101 Switching Protocols\r\nConnection: upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: \(acceptValue)\r\n\r\n"
        try await channel.writeInbound(ByteBuffer(string: response))

        let value = try await setup.get()
        let upgradeResult = try await value.get()
        guard case .websocket(_, _) = upgradeResult else {
            Issue.record()
            return
        }
    }

    @Test
    func testHTTPProxyFail() async throws {
        let logger = {
            var logger = Logger(label: "client")
            logger.logLevel = .trace
            return logger
        }()
        let channel = NIOAsyncTestingChannel()
        let wsChannel = try WebSocketClientChannel(
            handler: { _, _, _ in },
            url: "ws://localhost:8080/ws",
            configuration: .init(),
            tlsConfiguration: nil,
            proxySettings: .init(host: "localhost", port: 8081, type: .http())
        )
        let setup = try await channel.eventLoop.submit {
            wsChannel.setup(channel: channel, logger: logger)
        }.get()
        try await channel.connect(to: try SocketAddress(ipAddress: "127.0.0.1", port: 8081)).get()
        let outbound = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        let (proxyHead, _) = readHTTPRequest(from: outbound)
        #expect(proxyHead == "CONNECT localhost:8080 HTTP/1.1")
        let proxyResponse = "HTTP/1.1 400 Bad Request\r\n\r\n"
        await #expect(throws: HTTPProxyError.self) {
            try await channel.writeInbound(ByteBuffer(string: proxyResponse))
        }
        let upgradeFuture = try await setup.get()
        await #expect(throws: WebSocketClientError.proxyHandshakeInvalidResponse) { try await upgradeFuture.get() }
    }

    @Test func testEchoServer() async throws {
        let clientLogger = {
            var logger = Logger(label: "client")
            logger.logLevel = .trace
            return logger
        }()
        try await WebSocketClient.connect(
            url: "wss://echo.websocket.org/",
            tlsConfiguration: TLSConfiguration.makeClientConfiguration(),
            logger: clientLogger
        ) { inbound, outbound, _ in
            var inboundIterator = inbound.messages(maxSize: .max).makeAsyncIterator()
            try await outbound.write(.text("hello"))
            if let msg = try await inboundIterator.next() {
                print(msg)
            }
        }
    }

    @Test func testEchoServerWithSNIHostname() async throws {
        let clientLogger = {
            var logger = Logger(label: "client")
            logger.logLevel = .trace
            return logger
        }()
        try await WebSocketClient.connect(
            url: "wss://echo.websocket.org/",
            configuration: .init(sniHostname: "echo.websocket.org"),
            tlsConfiguration: TLSConfiguration.makeClientConfiguration(),
            logger: clientLogger
        ) { inbound, outbound, _ in
            var inboundIterator = inbound.messages(maxSize: .max).makeAsyncIterator()
            try await outbound.write(.text("hello"))
            if let msg = try await inboundIterator.next() {
                print(msg)
            }
        }
    }
}

extension HTTPField.Name {
    static var host: Self { self.init("host")! }
}
