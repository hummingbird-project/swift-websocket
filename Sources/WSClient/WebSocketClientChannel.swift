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

import HTTPTypes
import Logging
import NIOCore
import NIOHTTP1
import NIOHTTPTypesHTTP1
import NIOWebSocket
@_spi(WSInternal) import WSCore

struct WebSocketClientChannel: ClientConnectionChannel {
    enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, [any WebSocketExtension])
        case notUpgraded
    }

    typealias Value = EventLoopFuture<UpgradeResult>

    let urlPath: String
    let hostHeader: String
    let handler: WebSocketDataHandler<WebSocketClient.Context>
    let configuration: WebSocketClientConfiguration

    init(handler: @escaping WebSocketDataHandler<WebSocketClient.Context>, url: URI, configuration: WebSocketClientConfiguration) throws {
        guard let hostHeader = Self.urlHostHeader(for: url) else { throw WebSocketClientError.invalidURL }
        self.hostHeader = hostHeader
        self.urlPath = Self.urlPath(for: url)
        self.handler = handler
        self.configuration = configuration
    }

    func setup(channel: any Channel, logger: Logger) -> NIOCore.EventLoopFuture<Value> {
        channel.eventLoop.makeCompletedFuture {
            let upgrader = NIOTypedWebSocketClientUpgrader<UpgradeResult>(
                maxFrameSize: self.configuration.maxFrameSize,
                upgradePipelineHandler: { channel, head in
                    channel.eventLoop.makeCompletedFuture {
                        let asyncChannel = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
                        // work out what extensions we should add based off the server response
                        let headerFields = HTTPFields(head.headers, splitCookie: false)
                        let serverExtensions = WebSocketExtensionHTTPParameters.parseHeaders(headerFields)
                        let extensions = try configuration.extensions.compactMap {
                            try $0.clientExtension(from: serverExtensions)
                        }
                        return UpgradeResult.websocket(asyncChannel, extensions)
                    }
                }
            )

            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "0")
            headers.add(name: "Host", value: self.hostHeader)
            let additionalHeaders = HTTPHeaders(self.configuration.additionalHeaders)
            headers.add(contentsOf: additionalHeaders)
            // add websocket extensions to headers
            headers.add(contentsOf: self.configuration.extensions.map { (name: "Sec-WebSocket-Extensions", value: $0.clientRequestHeader()) })

            let requestHead = HTTPRequestHead(
                version: .http1_1,
                method: .GET,
                uri: self.urlPath,
                headers: headers
            )

            let clientUpgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
                upgradeRequestHead: requestHead,
                upgraders: [upgrader],
                notUpgradingCompletionHandler: { channel in
                    channel.eventLoop.makeCompletedFuture {
                        return UpgradeResult.notUpgraded
                    }
                }
            )

            var pipelineConfiguration = NIOUpgradableHTTPClientPipelineConfiguration(upgradeConfiguration: clientUpgradeConfiguration)
            pipelineConfiguration.leftOverBytesStrategy = .forwardBytes
            let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                configuration: pipelineConfiguration
            )

            return negotiationResultFuture
        }
    }

    func handle(value: Value, logger: Logger) async throws -> WebSocketCloseFrame? {
        switch try await value.get() {
        case .websocket(let webSocketChannel, let extensions):
            return try await WebSocketHandler.handle(
                type: .client,
                configuration: .init(
                    extensions: extensions,
                    autoPing: self.configuration.autoPing
                ),
                asyncChannel: webSocketChannel,
                context: WebSocketClient.Context(logger: logger),
                handler: self.handler
            )
        case .notUpgraded:
            // The upgrade to websocket did not succeed.
            logger.debug("Upgrade declined")
            throw WebSocketClientError.webSocketUpgradeFailed
        }
    }

    static func urlPath(for url: URI) -> String {
        url.path + (url.query.map { "?\($0)" } ?? "")
    }

    static func urlHostHeader(for url: URI) -> String? {
        guard let host = url.host else { return nil }
        if let port = url.port {
            return "\(host):\(port)"
        } else {
            return host
        }
    }
}
