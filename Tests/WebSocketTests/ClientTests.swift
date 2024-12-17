//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2024 the Hummingbird authors
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
import NIOSSL
import NIOWebSocket
import WSClient
import XCTest

final class WebSocketClientTests: XCTestCase {

    func testEchoServer() async throws {
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
}
