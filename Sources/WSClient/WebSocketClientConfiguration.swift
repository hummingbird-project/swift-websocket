//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HTTPTypes
import NIOCore
import NIOSSL
import WSCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Configuration for a client connecting to a WebSocket
public struct WebSocketClientConfiguration: Sendable {
    /// Max websocket frame size that can be sent/received
    public var maxFrameSize: Int
    /// Additional headers to be sent with the initial HTTP request
    public var additionalHeaders: HTTPFields
    /// WebSocket extensions
    public var extensions: [any WebSocketExtensionBuilder]
    /// Close timeout
    public var closeTimeout: Duration
    /// Automatic ping setup
    public var autoPing: AutoPingSetup
    /// Should text be validated to be UTF8
    public var validateUTF8: Bool
    /// Hostname used during TLS handshake
    public var sniHostname: String?

    /// Initialize WebSocketClient configuration
    ///   - Paramters
    ///     - maxFrameSize: Max websocket frame size that can be sent/received
    ///     - additionalHeaders: Additional headers to be sent with the initial HTTP request
    ///     - extensions: WebSocket extensions
    ///     - autoPing: Automatic Ping configuration
    ///     - validateUTF8: Should text be checked to see if it is valid UTF8
    ///     - sniHostname: Hostname used during TLS handshake
    public init(
        maxFrameSize: Int = (1 << 14),
        additionalHeaders: HTTPFields = .init(),
        extensions: [WebSocketExtensionFactory] = [],
        closeTimeout: Duration = .seconds(15),
        autoPing: AutoPingSetup = .disabled,
        validateUTF8: Bool = false,
        sniHostname: String? = nil,
    ) {
        self.maxFrameSize = maxFrameSize
        self.additionalHeaders = additionalHeaders
        self.extensions = extensions.map { $0.build() }
        self.closeTimeout = closeTimeout
        self.autoPing = autoPing
        self.validateUTF8 = validateUTF8
        self.sniHostname = sniHostname
    }
}

/// WebSocket client proxy settings
public struct WebSocketProxySettings: Sendable {
    /// Type of proxy
    public struct ProxyType: Sendable {
        enum Base {
            case socks
            case http(connectHeaders: HTTPFields = [:])
        }
        let value: Base

        /// SOCKS proxy
        public static var socks: ProxyType { .init(value: .socks) }
        /// HTTP proxy
        public static func http(connectHeaders: HTTPFields = [:]) -> ProxyType { .init(value: .http(connectHeaders: connectHeaders)) }
    }
    public enum ProxyAddress: Sendable {
        case hostname(String, port: Int)
        case environment
    }
    /// Network address
    public var address: ProxyAddress
    /// Proxy type
    public var type: ProxyType
    /// Timeout for CONNECT response
    public var timeout: Duration

    /// Initialize ProxySettings
    /// - Parameters:
    ///   - host: Proxy endpoint host name
    ///   - port: Proxy endoint port
    ///   - type: Proxy type HTTP or SOCKS
    ///   - timeout: Timeout for CONNECT request
    public init(
        host: String,
        port: Int,
        type: ProxyType,
        timeout: Duration = .seconds(30)
    ) {
        self.address = .hostname(host, port: port)
        self.type = type
        self.timeout = timeout
    }

    ///  Return proxy settings that will use environment variables for settings
    /// - Parameter timeout: Timeout for CONNECT request
    /// - Returns: proxy settings
    public static func environment(timeout: Duration = .seconds(30)) -> WebSocketProxySettings {
        .init(address: .environment, type: .http(), timeout: timeout)
    }

    /// Internal init
    internal init(address: ProxyAddress, type: ProxyType, timeout: Duration) {
        self.address = address
        self.type = type
        self.timeout = timeout
    }

    /// Get proxy settings from environment
    static func getProxyEnvironmentValues(for url: URI) -> (host: String, port: Int)? {
        let requiresTLS = url.scheme == .wss || url.scheme == .https
        let environment = ProcessInfo.processInfo.environment
        let proxy =
            if !requiresTLS {
                environment["http_proxy"]
            } else {
                environment["https_proxy"] ?? environment["HTTPS_PROXY"] ?? environment["http_proxy"]
            }
        guard let proxy else { return nil }
        let proxyURL = URI(proxy)
        guard proxyURL.scheme == .http else { return nil }
        guard let host = proxyURL.host else { return nil }
        guard let port = proxyURL.port else { return nil }
        return (host: host, port: port)
    }
}
