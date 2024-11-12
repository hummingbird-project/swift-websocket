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
@testable import WSCore
import XCTest

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
        guard case .sendClose = stateMachine.close() else { XCTFail(); return }
        guard case .doNothing = stateMachine.close() else { XCTFail(); return }
        guard case .doNothing = stateMachine.receivedClose(frameData: self.closeFrameData()) else { XCTFail(); return }
        guard case .closed(let frame) = stateMachine.state else { XCTFail(); return }
        XCTAssertEqual(frame?.closeCode, .normalClosure)
    }

    func testReceivedClose() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .disabled)
        guard case .sendClose(let error) = stateMachine.receivedClose(frameData: closeFrameData(code: .goingAway)) else { XCTFail(); return }
        XCTAssertEqual(error, .normalClosure)
        guard case .closed(let frame) = stateMachine.state else { XCTFail(); return }
        XCTAssertEqual(frame?.closeCode, .goingAway)
    }

    func testPingLoopNoPong() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .enabled(timePeriod: .seconds(15)))
        guard case .sendPing = stateMachine.sendPing() else { XCTFail(); return }
        guard case .wait = stateMachine.sendPing() else { XCTFail(); return }
    }

    func testPingLoop() {
        var stateMachine = WebSocketStateMachine(autoPingSetup: .enabled(timePeriod: .seconds(15)))
        guard case .sendPing(let buffer) = stateMachine.sendPing() else { XCTFail(); return }
        guard case .wait = stateMachine.sendPing() else { XCTFail(); return }
        stateMachine.receivedPong(frameData: buffer)
        guard case .open(let openState) = stateMachine.state else { XCTFail(); return }
        XCTAssertEqual(openState.lastPingTime, nil)
        guard case .sendPing = stateMachine.sendPing() else { XCTFail(); return }
    }
}
