//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2024 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Simple URL parser
struct URI: Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    struct Scheme: RawRepresentable, Equatable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        static var http: Self { return .init(rawValue: "http") }
        static var https: Self { return .init(rawValue: "https") }
        static var unix: Self { return .init(rawValue: "unix") }
        static var http_unix: Self { return .init(rawValue: "http_unix") }
        static var https_unix: Self { return .init(rawValue: "https_unix") }
        static var ws: Self { return .init(rawValue: "ws") }
        static var wss: Self { return .init(rawValue: "wss") }
    }

    let string: String

    /// URL scheme
    var scheme: Scheme? { return self._scheme.map { .init(rawValue: $0.string) } }
    /// URL host
    var host: String? { return self._host.map(\.string) }
    /// URL port
    var port: Int? { return self._port.map { Int($0.string) } ?? nil }
    /// URL path
    var path: String { return self._path.map(\.string) ?? "/" }
    /// URL query
    var query: String? { return self._query.map { String($0.string) }}

    private let _scheme: Parser?
    private let _host: Parser?
    private let _port: Parser?
    private let _path: Parser?
    private let _query: Parser?

    var description: String { self.string }

    /// Initialize `URI` from `String`
    /// - Parameter string: input string
    init(_ string: String) {
        enum ParsingState {
            case readingScheme
            case readingHost
            case readingPort
            case readingPath
            case readingQuery
            case finished
        }
        var scheme: Parser?
        var host: Parser?
        var port: Parser?
        var path: Parser?
        var query: Parser?
        var state: ParsingState = .readingScheme
        if string.first == "/" {
            state = .readingPath
        }

        var parser = Parser(string)
        while state != .finished {
            if parser.reachedEnd() { break }
            switch state {
            case .readingScheme:
                // search for "://" to find scheme and host
                scheme = try? parser.read(untilString: "://", skipToEnd: true)
                if scheme != nil {
                    state = .readingHost
                } else {
                    state = .readingPath
                }

            case .readingHost:
                let h = try! parser.read(until: Self.hostEndSet, throwOnOverflow: false)
                if h.count != 0 {
                    host = h
                }
                if parser.current() == ":" {
                    state = .readingPort
                } else if parser.current() == "?" {
                    state = .readingQuery
                } else {
                    state = .readingPath
                }

            case .readingPort:
                parser.unsafeAdvance()
                port = try! parser.read(until: Self.portEndSet, throwOnOverflow: false)
                state = .readingPath

            case .readingPath:
                path = try! parser.read(until: "?", throwOnOverflow: false)
                state = .readingQuery

            case .readingQuery:
                parser.unsafeAdvance()
                query = try! parser.read(until: "#", throwOnOverflow: false)
                state = .finished

            case .finished:
                break
            }
        }

        self.string = string
        self._scheme = scheme
        self._host = host
        self._port = port
        self._path = path
        self._query = query
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    private static let hostEndSet: Set<Unicode.Scalar> = Set(":/?")
    private static let portEndSet: Set<Unicode.Scalar> = Set("/?")
}
