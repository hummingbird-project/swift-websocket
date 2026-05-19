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
    func withTestWebSockerServer(
        configuration: WebSocketClientConfiguration,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<WebSocketClient.Context>,
        server: @Sendable @escaping (NIOAsyncTestingChannel) async throws -> Void
    ) async throws -> WebSocketCloseFrame? {
        let channel = NIOAsyncTestingChannel()
        return try await withThrowingTaskGroup(of: WebSocketCloseFrame?.self) { group in
            group.addTask {

            }
        }
    }

    @Test
    func read() async throws {
        var logger = Logger(label: "read")
        logger.logLevel = .trace

    }
}
