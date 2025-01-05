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

import NIOCore
import NIOWebSocket
import XCTest

@testable import WSCore

final class WebSocketStateMachineTests: XCTestCase {
    private func closeFrameData(code: WebSocketErrorCode = .normalClosure, reason: String? = nil) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 2 + (reason?.utf8.count ?? 0))
        buffer.write(webSocketErrorCode: code)
        if let reason {
            buffer.writeString(reason)
        }
        return buffer
    }

    func testClose() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .disabled)
        guard case .sendClose = stateMachine.close() else {
            XCTFail()
            return
        }
        guard case .doNothing = stateMachine.close() else {
            XCTFail()
            return
        }
        guard case .doNothing = stateMachine.receivedClose(frameData: self.closeFrameData(), validateUTF8: false) else {
            XCTFail()
            return
        }
        guard case .closed(let frame) = stateMachine.state else {
            XCTFail()
            return
        }
        XCTAssertEqual(frame?.closeCode, .normalClosure)
    }

    func testReceivedClose() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .disabled)
        guard case .sendClose(let error) = stateMachine.receivedClose(frameData: closeFrameData(code: .goingAway), validateUTF8: false) else {
            XCTFail()
            return
        }
        XCTAssertEqual(error, .normalClosure)
        guard case .closed(let frame) = stateMachine.state else {
            XCTFail()
            return
        }
        XCTAssertEqual(frame?.closeCode, .goingAway)
    }

    func testPingLoopNoPong() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .enabled(timePeriod: .seconds(15)))
        guard case .sendPing = stateMachine.sendPing() else {
            XCTFail()
            return
        }
        guard case .wait = stateMachine.sendPing() else {
            XCTFail()
            return
        }
    }

    func testPingLoop() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .enabled(timePeriod: .seconds(15)))
        guard case .sendPing(let buffer) = stateMachine.sendPing() else {
            XCTFail()
            return
        }
        guard case .wait = stateMachine.sendPing() else {
            XCTFail()
            return
        }
        stateMachine.receivedPong(frameData: buffer)
        guard case .open(let openState) = stateMachine.state else {
            XCTFail()
            return
        }
        XCTAssertEqual(openState.lastPingTime, nil)
        guard case .sendPing = stateMachine.sendPing() else {
            XCTFail()
            return
        }
    }

    // Verify ping buffer size doesnt grow
    func testPingBufferSize() async throws {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .enabled(timePeriod: .milliseconds(1)))
        var currentBuffer = ByteBuffer()
        var count = 0
        while true {
            switch stateMachine.sendPing() {
            case .sendPing(let buffer):
                XCTAssertEqual(buffer.readableBytes, 16)
                currentBuffer = buffer
                count += 1
                if count > 4 {
                    return
                }

            case .wait(let time):
                try await Task.sleep(for: time)
                stateMachine.receivedPong(frameData: currentBuffer)

            case .closeConnection:
                XCTFail("Should not timeout")
                return

            case .stop:
                XCTFail("Should not stop")
                return
            }
        }
    }
}
