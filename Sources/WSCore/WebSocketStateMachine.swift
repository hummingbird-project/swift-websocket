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

struct WebSocketStateMachine {
    static let pingDataSize = 16
    let pingTimePeriod: Duration
    var state: State

    init(autoPingSetup: AutoPingSetup) {
        switch autoPingSetup.value {
        case .enabled(let timePeriod):
            self.pingTimePeriod = timePeriod
        case .disabled:
            self.pingTimePeriod = .nanoseconds(0)
        }
        self.state = .open(.init())
    }

    enum CloseResult {
        case sendClose
        case doNothing
    }

    mutating func close() -> CloseResult {
        switch self.state {
        case .open:
            self.state = .closing
            return .sendClose
        case .closing:
            return .doNothing
        case .closed:
            return .doNothing
        }
    }

    enum ReceivedCloseResult {
        case sendClose(WebSocketErrorCode)
        case doNothing
    }

    // we received a connection close.
    // send a close back if it hasn't already been send and exit
    mutating func receivedClose(frameData: ByteBuffer) -> ReceivedCloseResult {
        var frameData = frameData
        let dataSize = frameData.readableBytes
        // read close code and close reason
        let closeCode = frameData.readWebSocketErrorCode()
        let reason = frameData.readableBytes > 0
            ? frameData.readString(length: frameData.readableBytes)
            : nil

        switch self.state {
        case .open:
            self.state = .closed(closeCode.map { .init(closeCode: $0, reason: reason) })
            let code: WebSocketErrorCode = if dataSize == 0 || closeCode != nil {
                // codes 3000 - 3999 are reserved for use by libraries, frameworks
                // codes 4000 - 4999 are reserved for private use
                // both of these are considered valid.
                if case .unknown(let code) = closeCode, code < 3000 || code > 4999 {
                    .protocolError
                } else {
                    .normalClosure
                }
            } else {
                .protocolError
            }
            return .sendClose(code)
        case .closing:
            self.state = .closed(closeCode.map { .init(closeCode: $0, reason: reason) })
            return .doNothing
        case .closed:
            return .doNothing
        }
    }

    enum SendPingResult {
        case sendPing(ByteBuffer)
        case wait(Duration)
        case closeConnection(WebSocketErrorCode)
        case stop
    }

    mutating func sendPing() -> SendPingResult {
        switch self.state {
        case .open(var state):
            if let lastPingTime = state.lastPingTime {
                let timeSinceLastPing = .now - lastPingTime
                // if time is less than timeout value, set wait time to when it would timeout
                // and re-run loop
                if timeSinceLastPing < self.pingTimePeriod {
                    return .wait(self.pingTimePeriod - timeSinceLastPing)
                } else {
                    return .closeConnection(.goingAway)
                }
            }
            // creating random payload
            let random = (0..<Self.pingDataSize).map { _ in UInt8.random(in: 0...255) }
            state.pingData.writeBytes(random)
            state.lastPingTime = .now
            self.state = .open(state)
            return .sendPing(state.pingData)

        case .closing:
            return .stop

        case .closed:
            return .stop
        }
    }

    enum ReceivedPingResult {
        case pong(ByteBuffer)
        case protocolError
        case doNothing
    }

    mutating func receivedPing(frameData: ByteBuffer) -> ReceivedPingResult {
        switch self.state {
        case .open:
            guard frameData.readableBytes < 126 else { return .protocolError }
            return .pong(frameData)

        case .closing:
            return .pong(frameData)

        case .closed:
            return .doNothing
        }
    }

    mutating func receivedPong(frameData: ByteBuffer) {
        switch self.state {
        case .open(var state):
            let frameData = frameData
            // ignore pong frames with frame data not the same as the last ping
            guard frameData == state.pingData else { return }
            // clear ping data
            state.lastPingTime = nil
            self.state = .open(state)

        case .closing:
            break

        case .closed:
            break
        }
    }
}

extension WebSocketStateMachine {
    struct OpenState {
        var pingData: ByteBuffer
        var lastPingTime: ContinuousClock.Instant?

        init() {
            self.pingData = ByteBufferAllocator().buffer(capacity: WebSocketStateMachine.pingDataSize)
            self.lastPingTime = nil
        }
    }

    enum State {
        case open(OpenState)
        case closing
        case closed(WebSocketCloseFrame?)
    }
}
