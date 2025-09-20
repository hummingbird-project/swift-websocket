//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import NIOWebSocket
import Testing

@testable import WSCompression
@testable import WSCore

struct WebSocketExtensionNegotiationTests {
    @Test func testExtensionHeaderParsing() {
        let headers: HTTPFields = .init([
            .init(name: .secWebSocketExtensions, value: "permessage-deflate; client_max_window_bits; server_max_window_bits=10"),
            .init(name: .secWebSocketExtensions, value: "permessage-deflate;client_max_window_bits"),
        ])
        let extensions = WebSocketExtensionHTTPParameters.parseHeaders(headers)
        #expect(
            extensions == [
                .init("permessage-deflate", parameters: ["client_max_window_bits": .null, "server_max_window_bits": .value("10")]),
                .init("permessage-deflate", parameters: ["client_max_window_bits": .null]),
            ]
        )
    }

    @Test func testDeflateServerResponse() {
        let requestHeaders: [WebSocketExtensionHTTPParameters] = [
            .init("permessage-deflate", parameters: ["client_max_window_bits": .value("10")])
        ]
        let ext = PerMessageDeflateExtensionBuilder(clientNoContextTakeover: true, serverNoContextTakeover: true)
        let serverResponse = ext.serverResponseHeader(to: requestHeaders)
        #expect(
            serverResponse == "permessage-deflate;client_max_window_bits=10;client_no_context_takeover;server_no_context_takeover"
        )
    }

    @Test func testDeflateServerResponseClientMaxWindowBits() {
        let requestHeaders: [WebSocketExtensionHTTPParameters] = [
            .init("permessage-deflate", parameters: ["client_max_window_bits": .null])
        ]
        let ext1 = PerMessageDeflateExtensionBuilder(serverNoContextTakeover: true)
        let serverResponse1 = ext1.serverResponseHeader(to: requestHeaders)
        #expect(
            serverResponse1 == "permessage-deflate;server_no_context_takeover"
        )
        let ext2 = PerMessageDeflateExtensionBuilder(clientNoContextTakeover: true, serverMaxWindow: 12)
        let serverResponse2 = ext2.serverResponseHeader(to: requestHeaders)
        #expect(
            serverResponse2 == "permessage-deflate;client_no_context_takeover;server_max_window_bits=12"
        )
    }

    @Test func testUnregonisedExtensionServerResponse() throws {
        let serverExtensions: [WebSocketExtensionBuilder] = [PerMessageDeflateExtensionBuilder()]
        let (headers, extensions) = try serverExtensions.serverExtensionNegotiation(
            requestHeaders: [
                .secWebSocketExtensions: "permessage-foo;bar=baz",
                .secWebSocketExtensions: "permessage-deflate;client_max_window_bits=10",
            ]
        )
        #expect(
            headers[.secWebSocketExtensions] == "permessage-deflate;client_max_window_bits=10"
        )
        #expect(extensions.count == 1)
        let firstExtension = try #require(extensions.first)
        #expect(firstExtension is PerMessageDeflateExtension)

        let requestExtensions = try serverExtensions.buildClientExtensions(from: headers)
        #expect(requestExtensions.count == 1)
        #expect(requestExtensions[0] is PerMessageDeflateExtension)
    }

    @Test func testNonNegotiableClientExtension() throws {
        struct MyExtension: WebSocketExtension {
            var name = "my-extension"

            func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                frame
            }

            func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                frame
            }

            func shutdown() async {}
        }
        let clientExtensionBuilders: [WebSocketExtensionBuilder] = [
            WebSocketExtensionFactory.nonNegotiatedExtension {
                MyExtension()
            }.build()
        ]
        let clientExtensions = try clientExtensionBuilders.buildClientExtensions(from: [:])
        #expect(clientExtensions.count == 1)
        let myExtension = try #require(clientExtensions.first)
        #expect(myExtension is MyExtension)
    }

    @Test func testNonNegotiableServerExtension() throws {
        struct MyExtension: WebSocketExtension {
            var name = "my-extension"

            func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                frame
            }

            func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                frame
            }

            func shutdown() async {}
        }
        let serverExtensionBuilders: [WebSocketExtensionBuilder] = [WebSocketNonNegotiableExtensionBuilder { MyExtension() }]
        let (headers, serverExtensions) = try serverExtensionBuilders.serverExtensionNegotiation(
            requestHeaders: [:]
        )
        #expect(headers.count == 0)
        #expect(serverExtensions.count == 1)
        let myExtension = try #require(serverExtensions.first)
        #expect(myExtension is MyExtension)
    }
}
