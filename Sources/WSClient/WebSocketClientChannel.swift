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
    let originHeader: String
    let handler: WebSocketDataHandler<WebSocketClient.Context>
    let configuration: WebSocketClientConfiguration

    init(handler: @escaping WebSocketDataHandler<WebSocketClient.Context>, url: URI, configuration: WebSocketClientConfiguration) throws {
        guard let (hostHeader, originHeader) = Self.urlHostAndOriginHeaders(for: url) else { throw WebSocketClientError.invalidURL }
        self.hostHeader = hostHeader
        self.originHeader = originHeader
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
                        let extensions = try configuration.extensions.buildClientExtensions(from: headerFields)
                        if extensions.count > 0 {
                            logger.debug(
                                "Enabled extensions",
                                metadata: ["hb.ws.extensions": .string(extensions.map(\.name).joined(separator: ","))]
                            )
                        }
                        return UpgradeResult.websocket(asyncChannel, extensions)
                    }
                }
            )

            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: "Host", value: self.hostHeader)
            headers.replaceOrAdd(name: "Origin", value: self.originHeader)
            let additionalHeaders = HTTPHeaders(self.configuration.additionalHeaders)
            headers.add(contentsOf: additionalHeaders)
            // add websocket extensions to headers
            headers.add(
                contentsOf: self.configuration.extensions.compactMap {
                    let requestHeaders = $0.clientRequestHeader()
                    return requestHeaders != "" ? ("Sec-WebSocket-Extensions", requestHeaders) : nil
                }
            )

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
                    autoPing: self.configuration.autoPing,
                    closeTimeout: self.configuration.closeTimeout,
                    validateUTF8: self.configuration.validateUTF8
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

    static func urlHostAndOriginHeaders(for url: URI) -> (host: String, origin: String)? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let origin = "\(scheme)://\(host)"
        if let port = url.port {
            return (host: "\(host):\(port)", origin: origin)
        } else {
            return (host: host, origin: origin)
        }
    }
}
