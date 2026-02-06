//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HTTPTypes
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import NIOTransportServices
import NIOWebSocket
import WSCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// WebSocket client
///
/// Connect to HTTP server with WebSocket upgrade available.
///
/// Supports TLS via both NIOSSL and Network framework.
///
/// Initialize the WebSocketClient with your handler and then call ``WebSocketClient/run()``
/// to connect. The handler is provider with an `inbound` stream of WebSocket packets coming
/// from the server and an `outbound` writer that can be used to write packets to the server.
/// ```swift
/// let webSocket = WebSocketClient(url: "ws://test.org/ws", logger: logger) { inbound, outbound, context in
///     for try await packet in inbound {
///         if case .text(let string) = packet {
///             try await outbound.write(.text(string))
///         }
///     }
/// }
/// ```
public struct WebSocketClient {
    /// Client implementation of ``/WSCore/WebSocketContext``.
    public struct Context: WebSocketContext {
        public let logger: Logger

        package init(logger: Logger) {
            self.logger = logger
        }
    }

    enum MultiPlatformTLSConfiguration: Sendable {
        case niossl(TLSConfiguration)
        #if canImport(Network)
        case ts(TSTLSOptions)
        #endif
    }

    /// WebSocket URL
    let url: URI
    /// WebSocket data handler
    let handler: WebSocketDataHandler<Context>
    /// configuration
    let configuration: WebSocketClientConfiguration
    /// proxy settings
    let proxySettings: WebSocketProxySettings?
    /// EventLoopGroup to use
    let eventLoopGroup: any EventLoopGroup
    /// Logger
    let logger: Logger
    /// TLS configuration
    let tlsConfiguration: MultiPlatformTLSConfiguration?

    /// Initialize websocket client
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - tlsConfiguration: TLS configuration
    ///   - handler: WebSocket data handler
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    public init(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        tlsConfiguration: TLSConfiguration? = nil,
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) {
        self.url = .init(url)
        self.handler = handler
        self.configuration = configuration
        self.proxySettings = nil
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.tlsConfiguration = tlsConfiguration.map { .niossl($0) }
    }

    /// Initialize websocket client
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - tlsConfiguration: TLS configuration for connection to websocket server
    ///   - proxySettings: Proxy connection settings
    ///   - handler: WebSocket data handler
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    public init(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        tlsConfiguration: TLSConfiguration? = nil,
        proxySettings: WebSocketProxySettings,
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) {
        self.url = .init(url)
        self.handler = handler
        self.configuration = configuration
        self.proxySettings = proxySettings
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.tlsConfiguration = tlsConfiguration.map { .niossl($0) }
    }

    #if canImport(Network)
    /// Initialize websocket client
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - transportServicesTLSOptions: TLS options for NIOTransportServices
    ///   - handler: WebSocket data handler
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    public init(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        transportServicesTLSOptions: TSTLSOptions,
        eventLoopGroup: NIOTSEventLoopGroup = NIOTSEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) {
        self.url = .init(url)
        self.handler = handler
        self.configuration = configuration
        self.proxySettings = nil
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
        self.tlsConfiguration = .ts(transportServicesTLSOptions)
    }
    #endif

    /// Connect and run handler
    /// - Returns: WebSocket close frame details if server returned any
    @discardableResult public func run() async throws -> WebSocketCloseFrame? {
        guard var host = url.host else { throw WebSocketClientError.invalidURL }
        let requiresTLS = self.url.scheme == .wss || self.url.scheme == .https
        var port = self.url.port ?? (requiresTLS ? 443 : 80)
        if let proxySettings = self.proxySettings ?? self.getProxyEnvironmentValues(requiresTLS: requiresTLS) {
            host = proxySettings.host
            port = proxySettings.port
        }
        var tlsConfiguration: TLSConfiguration? = nil
        if requiresTLS {
            switch self.tlsConfiguration {
            case .niossl(let config):
                tlsConfiguration = config
            case .none:
                tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            #if canImport(Network)
            case .ts(let tlsOptions):
                let client = try ClientConnection(
                    WebSocketClientChannel(
                        handler: handler,
                        url: url,
                        configuration: self.configuration,
                        tlsConfiguration: nil,
                        proxySettings: nil
                    ),
                    address: .hostname(host, port: port),
                    transportServicesTLSOptions: tlsOptions,
                    eventLoopGroup: self.eventLoopGroup,
                    logger: self.logger
                )
                return try await client.run()

            #endif
            }
        }
        let client = try ClientConnection(
            WebSocketClientChannel(
                handler: handler,
                url: url,
                configuration: self.configuration,
                tlsConfiguration: tlsConfiguration,
                proxySettings: self.proxySettings
            ),
            address: .hostname(host, port: port),
            eventLoopGroup: self.eventLoopGroup,
            logger: self.logger
        )
        return try await client.run()
    }

    private func getProxyEnvironmentValues(requiresTLS: Bool) -> WebSocketProxySettings? {
        guard self.configuration.readProxyEnvironmentVariables == true else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let proxy =
            if !requiresTLS {
                environment["http_proxy"]
            } else {
                environment["HTTPS_PROXY"] ?? environment["https_proxy"] ?? environment["http_proxy"]
            }
        guard let proxy else { return nil }
        let proxyURL = URI(proxy)
        guard proxyURL.scheme == .http else { return nil }
        guard let host = proxyURL.host else { return nil }
        guard let port = proxyURL.port else { return nil }
        return .init(host: host, port: port, type: .http())
    }
}

extension WebSocketClient {
    /// Create websocket client, connect and handle connection
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - tlsConfiguration: TLS configuration
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    ///   - process: Closure handling webSocket
    /// - Returns: WebSocket close frame details if server returned any
    @discardableResult public static func connect(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        tlsConfiguration: TLSConfiguration? = nil,
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) async throws -> WebSocketCloseFrame? {
        let ws = self.init(
            url: url,
            configuration: configuration,
            tlsConfiguration: tlsConfiguration,
            eventLoopGroup: eventLoopGroup,
            logger: logger,
            handler: handler
        )
        return try await ws.run()
    }

    /// Create websocket client, connect and handle connection
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - configuration: WebSocket client configuration
    ///   - tlsConfiguration: TLS configuration
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    ///   - process: Closure handling webSocket
    /// - Returns: WebSocket close frame details if server returned any
    @discardableResult public static func connect(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        tlsConfiguration: TLSConfiguration? = nil,
        proxySettings: WebSocketProxySettings,
        eventLoopGroup: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) async throws -> WebSocketCloseFrame? {
        let ws = self.init(
            url: url,
            configuration: configuration,
            tlsConfiguration: tlsConfiguration,
            proxySettings: proxySettings,
            eventLoopGroup: eventLoopGroup,
            logger: logger,
            handler: handler
        )
        return try await ws.run()
    }

    #if canImport(Network)
    /// Create websocket client, connect and handle connection
    ///
    /// - Parametes:
    ///   - url: URL of websocket
    ///   - transportServicesTLSOptions: TLS options for NIOTransportServices
    ///   - maxFrameSize: Max frame size for a single packet
    ///   - eventLoopGroup: EventLoopGroup to run WebSocket client on
    ///   - logger: Logger
    ///   - process: WebSocket data handler
    /// - Returns: WebSocket close frame details if server returned any
    public static func connect(
        url: String,
        configuration: WebSocketClientConfiguration = .init(),
        transportServicesTLSOptions: TSTLSOptions,
        eventLoopGroup: NIOTSEventLoopGroup = NIOTSEventLoopGroup.singleton,
        logger: Logger,
        handler: @escaping WebSocketDataHandler<Context>
    ) async throws -> WebSocketCloseFrame? {
        let ws = self.init(
            url: url,
            configuration: configuration,
            transportServicesTLSOptions: transportServicesTLSOptions,
            eventLoopGroup: eventLoopGroup,
            logger: logger,
            handler: handler
        )
        return try await ws.run()
    }
    #endif
}
