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
@testable import WSCompression
@testable import WSCore
import XCTest

final class WebSocketExtensionNegotiationTests: XCTestCase {
    func testExtensionHeaderParsing() {
        let headers: HTTPFields = .init([
            .init(name: .secWebSocketExtensions, value: "permessage-deflate; client_max_window_bits; server_max_window_bits=10"),
            .init(name: .secWebSocketExtensions, value: "permessage-deflate;client_max_window_bits"),
        ])
        let extensions = WebSocketExtensionHTTPParameters.parseHeaders(headers)
        XCTAssertEqual(
            extensions,
            [
                .init("permessage-deflate", parameters: ["client_max_window_bits": .null, "server_max_window_bits": .value("10")]),
                .init("permessage-deflate", parameters: ["client_max_window_bits": .null]),
            ]
        )
    }

    func testDeflateServerResponse() {
        let requestHeaders: [WebSocketExtensionHTTPParameters] = [
            .init("permessage-deflate", parameters: ["client_max_window_bits": .value("10")]),
        ]
        let ext = PerMessageDeflateExtensionBuilder(clientNoContextTakeover: true, serverNoContextTakeover: true)
        let serverResponse = ext.serverResponseHeader(to: requestHeaders)
        XCTAssertEqual(
            serverResponse,
            "permessage-deflate;client_max_window_bits=10;client_no_context_takeover;server_no_context_takeover"
        )
    }

    func testDeflateServerResponseClientMaxWindowBits() {
        let requestHeaders: [WebSocketExtensionHTTPParameters] = [
            .init("permessage-deflate", parameters: ["client_max_window_bits": .null]),
        ]
        let ext1 = PerMessageDeflateExtensionBuilder(serverNoContextTakeover: true)
        let serverResponse1 = ext1.serverResponseHeader(to: requestHeaders)
        XCTAssertEqual(
            serverResponse1,
            "permessage-deflate;server_no_context_takeover"
        )
        let ext2 = PerMessageDeflateExtensionBuilder(clientNoContextTakeover: true, serverMaxWindow: 12)
        let serverResponse2 = ext2.serverResponseHeader(to: requestHeaders)
        XCTAssertEqual(
            serverResponse2,
            "permessage-deflate;client_no_context_takeover;server_max_window_bits=12"
        )
    }

    func testUnregonisedExtensionServerResponse() throws {
        let serverExtensions: [WebSocketExtensionBuilder] = [PerMessageDeflateExtensionBuilder()]
        let (headers, extensions) = try serverExtensions.serverExtensionNegotiation(
            requestHeaders: [.secWebSocketExtensions: "permessage-foo;bar=baz,permessage-deflate;client_max_window_bits=10"]
        )
        XCTAssertEqual(
            headers[.secWebSocketExtensions],
            "permessage-deflate;client_max_window_bits=10"
        )
        XCTAssertEqual(extensions.count, 1)
        XCTAssert(extensions[0] is PerMessageDeflateExtension)

        let requestExtensions = try serverExtensions.buildClientExtensions(from: headers)
        XCTAssertEqual(requestExtensions.count, 1)
        XCTAssert(requestExtensions[0] is PerMessageDeflateExtension)
    }

    func testNonNegotiableClientExtension() throws {
        struct MyExtensionBuilder: WebSocketNonNegotiableExtensionBuilder {
            func build() -> any WebSocketExtension {
                MyExtension()
            }

            static let name = "my-extension"

            struct MyExtension: WebSocketExtension {
                var name = "my-extension"

                func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                    return frame
                }

                func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                    return frame
                }

                func shutdown() async {}
            }
        }
        let clientExtensionBuilders: [WebSocketExtensionBuilder] = [MyExtensionBuilder()]
        let clientExtensions = try clientExtensionBuilders.buildClientExtensions(from: [:])
        XCTAssertEqual(clientExtensions.count, 1)
        let myExtension = try XCTUnwrap(clientExtensions.first)
        XCTAssert(myExtension is MyExtensionBuilder.MyExtension)
    }

    func testNonNegotiableServerExtension() throws {
        struct MyExtensionBuilder: WebSocketNonNegotiableExtensionBuilder {
            func build() -> any WebSocketExtension {
                MyExtension()
            }

            static let name = "my-extension"

            struct MyExtension: WebSocketExtension {
                var name = "my-extension"

                func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                    return frame
                }

                func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
                    return frame
                }

                func shutdown() async {}
            }
        }
        let serverExtensionBuilders: [WebSocketExtensionBuilder] = [MyExtensionBuilder()]
        let (headers, serverExtensions) = try serverExtensionBuilders.serverExtensionNegotiation(
            requestHeaders: [:]
        )
        XCTAssertEqual(headers.count, 0)
        XCTAssertEqual(serverExtensions.count, 1)
        let myExtension = try XCTUnwrap(serverExtensions.first)
        XCTAssert(myExtension is MyExtensionBuilder.MyExtension)
    }
}
