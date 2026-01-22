//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import NIOCore
import NIOWebSocket

/// WebSocket data frame.
public struct WebSocketDataFrame: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Opcode: String, Sendable {
        case text
        case binary
        case continuation
    }

    public var opcode: Opcode
    public var data: ByteBuffer
    public var fin: Bool

    init?(from frame: WebSocketFrame) {
        switch frame.opcode {
        case .binary: self.opcode = .binary
        case .text: self.opcode = .text
        case .continuation: self.opcode = .continuation
        default: return nil
        }
        self.data = frame.unmaskedData
        self.fin = frame.fin
    }

    public var description: String {
        "\(self.opcode): \(self.data.description), finished: \(self.fin)"
    }

    public var debugDescription: String {
        "\(self.opcode): \(self.data.debugDescription), finished: \(self.fin)"
    }
}
