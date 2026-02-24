//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Testing

@testable import WSClient

@Suite("ProxySettings Tests", .serialized)
struct ProxySettingsTests {
    @Test func testHTTPProxyEnvVar() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.websocket.org/")
        #expect(values?.host == "test.com")
        #expect(values?.port == 8888)
    }

    @Test func testHTTPSProxyEnvVar() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("https_proxy", "http://test2.com:8888", 1)
        defer { unsetenv("https_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "wss://echo.websocket.org/")
        #expect(values?.host == "test2.com")
        #expect(values?.port == 8888)
    }

    @Test func testNoProxyWildcard() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("no_proxy", "*", 1)
        defer { unsetenv("no_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.websocket.org/")
        #expect(values == nil)
    }

    @Test func testNoProxyMatch() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("no_proxy", "websocket.org", 1)
        defer { unsetenv("no_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.websocket.org/")
        #expect(values == nil)
    }

    @Test func testNoProxyMatchWithLeadingDot() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("no_proxy", ".websocket.org", 1)
        defer { unsetenv("no_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://websocket.org/")
        #expect(values == nil)
    }

    @Test func testNoProxyMultipleDomains() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("no_proxy", "ws.org,websocket.org", 1)
        defer { unsetenv("no_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.websocket.org/")
        #expect(values == nil)
    }

    @Test func testNoProxyMultipleDomainsWithWhitespace() async throws {
        setenv("http_proxy", "http://test.com:8888", 1)
        defer { unsetenv("http_proxy") }
        setenv("no_proxy", "ws.org , websocket.org", 1)
        defer { unsetenv("no_proxy") }
        let values = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.websocket.org/")
        #expect(values == nil)
        let values2 = WebSocketProxySettings.getProxyEnvironmentValues(for: "ws://echo.ws.org/")
        #expect(values2 == nil)
    }
}
