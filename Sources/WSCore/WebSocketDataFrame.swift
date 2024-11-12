//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023-2024 the Hummingbird authors
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
        return "\(self.opcode): \(self.data.description), finished: \(self.fin)"
    }

    public var debugDescription: String {
        return "\(self.opcode): \(self.data.debugDescription), finished: \(self.fin)"
    }
}
