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

import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOPosix
import WSClient
import WSCompression
import XCTest

final class AutobahnTests: XCTestCase {
    /// To run all the autobahn tests takes a long time. By default we only run a selection.
    /// The `AUTOBAHN_ALL_TESTS` environment flag triggers running all of them.
    var runAllTests: Bool { ProcessInfo.processInfo.environment["AUTOBAHN_ALL_TESTS"] == "true" }
    var autobahnServer: String { ProcessInfo.processInfo.environment["FUZZING_SERVER"] ?? "localhost" }

    func getValue<T: Decodable & Sendable>(_ path: String, as: T.Type) async throws -> T {
        let result: NIOLockedValueBox<T?> = .init(nil)
        try await WebSocketClient.connect(
            url: .init("ws://\(self.autobahnServer):9001/\(path)"),
            configuration: .init(validateUTF8: true),
            logger: Logger(label: "Autobahn")
        ) { inbound, _, _ in
            var inboundIterator = inbound.messages(maxSize: .max).makeAsyncIterator()
            switch try await inboundIterator.next() {
            case .text(let text):
                let data = Data(text.utf8)
                let report = try JSONDecoder().decode(T.self, from: data)
                result.withLockedValue { $0 = report }

            case .binary:
                preconditionFailure("Received unexpected data")

            case .none:
                return
            }
        }
        return try result.withLockedValue { try XCTUnwrap($0) }
    }

    func autobahnTests(
        cases: Set<Int>,
        extensions: [WebSocketExtensionFactory] = [.perMessageDeflate(maxDecompressedFrameSize: 16_777_216)]
    ) async throws {
        struct CaseInfo: Decodable {
            let id: String
            let description: String
        }
        struct CaseStatus: Decodable {
            let behavior: String
        }

        let logger = Logger(label: "Autobahn")

        // Run tests
        do {
            for index in cases.sorted() {
                // get case info
                let info = try await getValue("getCaseInfo?case=\(index)&agent=swift-websocket", as: CaseInfo.self)
                logger.info("\(info.id): \(info.description)")

                // run case
                try await WebSocketClient.connect(
                    url: .init("ws://\(self.autobahnServer):9001/runCase?case=\(index)&agent=swift-websocket"),
                    configuration: .init(
                        maxFrameSize: 16_777_216,
                        extensions: extensions,
                        validateUTF8: true
                    ),
                    logger: logger
                ) { inbound, outbound, _ in
                    for try await msg in inbound.messages(maxSize: .max) {
                        switch msg {
                        case .binary(let buffer):
                            try await outbound.write(.binary(buffer))
                        case .text(let string):
                            try await outbound.write(.text(string))
                        }
                    }
                }

                // get case status
                let status = try await getValue("getCaseStatus?case=\(index)&agent=swift-websocket", as: CaseStatus.self)
                XCTAssert(status.behavior == "OK" || status.behavior == "INFORMATIONAL" || status.behavior == "NON-STRICT")
            }

            try await WebSocketClient.connect(url: .init("ws://\(self.autobahnServer):9001/updateReports?agent=HB"), logger: logger) { inbound, _, _ in
                for try await _ in inbound {}
            }
        } catch let error as NIOConnectionError {
            logger.error("Autobahn tests require a running Autobahn fuzzing server. Run ./scripts/autobahn-server.sh")
            throw error
        }
    }

    func test_1_Framing() async throws {
        try await self.autobahnTests(cases: .init(1..<17))
    }

    func test_2_PingPongs() async throws {
        try await self.autobahnTests(cases: .init(17..<28))
    }

    func test_3_ReservedBits() async throws {
        // Reserved bits tests fail
        try XCTSkipIf(true)
        try await self.autobahnTests(cases: .init(28..<35))
    }

    func test_4_Opcodes() async throws {
        try await self.autobahnTests(cases: .init(35..<45))
    }

    func test_5_Fragmentation() async throws {
        try await self.autobahnTests(cases: .init(45..<65))
    }

    func test_6_UTF8Handling() async throws {
        try await self.autobahnTests(cases: .init(65..<210))
    }

    func test_7_CloseHandling() async throws {
        try await self.autobahnTests(cases: .init(210..<247))
    }

    func test_9_Performance() async throws {
        if !self.runAllTests {
            try await self.autobahnTests(cases: .init([247, 260, 270, 281, 291, 296]))
        } else {
            try await self.autobahnTests(cases: .init(247..<301))
        }
    }

    func test_10_AutoFragmentation() async throws {
        try await self.autobahnTests(cases: .init([301]))
    }

    func test_12_CompressionDifferentPayloads() async throws {
        if !self.runAllTests {
            try await self.autobahnTests(cases: .init([302, 330, 349, 360, 388]))
        } else {
            try await self.autobahnTests(cases: .init(302..<391))
        }
    }

    func test_13_CompressionDifferentParameters() async throws {
        if !self.runAllTests {
            try await self.autobahnTests(cases: .init([392]), extensions: [.perMessageDeflate(noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([427]), extensions: [.perMessageDeflate(noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([440]), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([451]), extensions: [.perMessageDeflate(maxWindow: 15, noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([473]), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([498]), extensions: [.perMessageDeflate(maxWindow: 15, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            // case 13.7.x are repeated with different setups
            try await self.autobahnTests(cases: .init([509]), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([517]), extensions: [.perMessageDeflate(noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init([504]), extensions: [.perMessageDeflate(noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
        } else {
            try await self.autobahnTests(cases: .init(392..<410), extensions: [.perMessageDeflate(noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(410..<428), extensions: [.perMessageDeflate(noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(428..<446), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(446..<464), extensions: [.perMessageDeflate(maxWindow: 15, noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(464..<482), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(482..<500), extensions: [.perMessageDeflate(maxWindow: 15, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            // case 13.7.x are repeated with different setups
            try await self.autobahnTests(cases: .init(500..<518), extensions: [.perMessageDeflate(maxWindow: 9, noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(500..<518), extensions: [.perMessageDeflate(noContextTakeover: true, maxDecompressedFrameSize: 131_072)])
            try await self.autobahnTests(cases: .init(500..<518), extensions: [.perMessageDeflate(noContextTakeover: false, maxDecompressedFrameSize: 131_072)])
        }
    }
}
