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
import XCTest

@testable import WSClient

final class ClientChannelTests: XCTestCase {

    func testInitialRequestHeader() async throws {
        let ws = try WebSocketClientChannel(handler: { _, _, _ in }, url: "wss://echo.websocket.org:443/ws", configuration: .init())

        XCTAssertEqual(ws.urlPath, "/ws")
        XCTAssertEqual(ws.hostHeader, "echo.websocket.org:443")
        XCTAssertEqual(ws.originHeader, "wss://echo.websocket.org")
    }
}
