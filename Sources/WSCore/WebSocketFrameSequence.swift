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

import NIOCore
import NIOWebSocket

/// Sequence of fragmented WebSocket frames.
struct WebSocketFrameSequence {
    var frames: [WebSocketDataFrame]
    var size: Int
    var first: WebSocketDataFrame { self.frames[0] }

    init(frame: WebSocketDataFrame) {
        assert(frame.opcode != .continuation, "Cannot create a WebSocketFrameSequence starting with a continuation")
        self.frames = [frame]
        self.size = 0
    }

    mutating func append(_ frame: WebSocketDataFrame) {
        assert(frame.opcode == .continuation)
        self.frames.append(frame)
        self.size += frame.data.readableBytes
    }

    var bytes: ByteBuffer {
        if self.frames.count == 1 {
            return self.frames[0].data
        } else {
            var result = ByteBufferAllocator().buffer(capacity: self.size)
            for frame in self.frames {
                var data = frame.data
                result.writeBuffer(&data)
            }
            return result
        }
    }

    var message: WebSocketMessage {
        .init(frame: self.collated)!
    }

    var collated: WebSocketDataFrame {
        var frame = self.first
        frame.data = self.bytes
        frame.fin = true
        return frame
    }
}
