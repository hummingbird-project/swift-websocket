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
import NIOSSL
import NIOWebSocket
@_spi(WSInternal) import WSCore

struct WebSocketClientChannel: ClientConnectionChannel {
    enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, [any WebSocketExtension])
        case notUpgraded
    }

    typealias Value = EventLoopFuture<UpgradeResult>

    let url: URI
    let handler: WebSocketDataHandler<WebSocketClient.Context>
    let configuration: WebSocketClientConfiguration
    let sslContext: NIOSSLContext?

    init(
        handler: @escaping WebSocketDataHandler<WebSocketClient.Context>,
        url: URI,
        configuration: WebSocketClientConfiguration,
        tlsConfiguration: TLSConfiguration?
    ) throws {
        self.url = url
        self.handler = handler
        self.configuration = configuration
        self.sslContext = try tlsConfiguration.map { try NIOSSLContext(configuration: $0) }
    }

    func setup(channel: any Channel, logger: Logger) -> EventLoopFuture<Value> {
        channel.eventLoop.makeCompletedFuture {
            guard var host = url.host else { throw WebSocketClientError.invalidURL }
            guard let (hostHeader, originHeader) = Self.urlHostAndOriginHeaders(for: url) else { throw WebSocketClientError.invalidURL }
            let urlPath = Self.urlPath(for: url)

            if let proxy = self.configuration.proxySettings {
                host = proxy.host
            }

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
            headers.replaceOrAdd(name: "Host", value: hostHeader)
            headers.replaceOrAdd(name: "Origin", value: originHeader)
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
                uri: urlPath,
                headers: headers
            )

            let clientUpgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
                upgradeRequestHead: requestHead,
                upgraders: [upgrader],
                notUpgradingCompletionHandler: { channel in
                    channel.eventLoop.makeCompletedFuture {
                        UpgradeResult.notUpgraded
                    }
                }
            )

            var pipelineConfiguration = NIOUpgradableHTTPClientPipelineConfiguration(upgradeConfiguration: clientUpgradeConfiguration)
            pipelineConfiguration.leftOverBytesStrategy = .forwardBytes
            if let sslContext {
                let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.configuration.sniHostname ?? host)
                try channel.pipeline.syncOperations.addHandler(sslHandler, position: .first)
            }
            let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                configuration: pipelineConfiguration
            )
            if let proxy = self.configuration.proxySettings {
                let requiresTLS = self.url.scheme == .wss || self.url.scheme == .https
                let port = self.url.port ?? (requiresTLS ? 443 : 80)
                let promise = channel.eventLoop.makePromise(of: Void.self)
                let negotiationResultPromise = channel.eventLoop.makePromise(of: UpgradeResult.self)
                let proxyHandler = HTTP1ProxyConnectHandler(
                    targetHost: host,
                    targetPort: port,
                    headers: HTTPHeaders(proxy.connectHeaders),
                    deadline: .now() + .init(proxy.timeout),
                    promise: promise
                )
                let upgradeHandler = try channel.pipeline.syncOperations.handler(type: NIOTypedHTTPClientUpgradeHandler<Value>.self)
                try channel.pipeline.syncOperations.addHandler(proxyHandler, position: .before(upgradeHandler))

                promise.futureResult.cascadeFailure(to: negotiationResultPromise)
                negotiationResultFuture.cascade(to: negotiationResultPromise)
                return negotiationResultPromise.futureResult
            }
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
