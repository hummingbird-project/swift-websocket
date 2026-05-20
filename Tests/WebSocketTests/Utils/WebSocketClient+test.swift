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
@_spi(WSInternal) import WSCore

@testable import WSClient

extension WebSocketClient {
    static func test(
        channel: NIOAsyncTestingChannel,
        configuration: WebSocketClientConfiguration,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) async throws -> WebSocketCloseFrame? {
        let nioAsyncChannel = try await channel.connect(to: .init(ipAddress: "127.0.0.1", port: 8080))
            .flatMap { _ in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
                }
            }
            .get()

        do {
            return try await WebSocketHandler.handle(
                type: .client,
                configuration: .init(
                    extensions: [],
                    autoPing: configuration.autoPing,
                    closeTimeout: configuration.closeTimeout,
                    validateUTF8: configuration.validateUTF8,
                    ignoreUncleanSSLShutdownErrors: configuration.ignoreUncleanSSLShutdownErrors,
                    maxFrameSize: configuration.maxFrameSize
                ),
                asyncChannel: nioAsyncChannel,
                context: WebSocketClient.Context(logger: logger),
                handler: handler
            )
        } catch WebSocketHandler.InternalError.close(let code) {
            switch code {
            case .messageTooLarge:
                throw WebSocketClientError.serverSentMessageTooLarge
            case .dataInconsistentWithMessage:
                throw WebSocketClientError.serverSentDataInconsistentWithMessage
            default:
                throw WebSocketClientError.serverProtocolError
            }
        }
    }
}
