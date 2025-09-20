//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2025 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import Testing

@testable import WSClient

struct ClientChannelTests {

    @Test func testInitialRequestHeader() async throws {
        let ws = try WebSocketClientChannel(handler: { _, _, _ in }, url: "wss://echo.websocket.org:443/ws", configuration: .init())

        #expect(ws.urlPath == "/ws")
        #expect(ws.hostHeader == "echo.websocket.org:443")
        #expect(ws.originHeader == "wss://echo.websocket.org")
    }
}
