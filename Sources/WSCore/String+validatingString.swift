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

extension String {
    init?(buffer: ByteBuffer, validateUTF8: Bool) {
        #if compiler(>=6)
        if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *), validateUTF8 {
            do {
                var buffer = buffer
                self = try buffer.readUTF8ValidatedString(length: buffer.readableBytes)!
            } catch {
                return nil
            }
        } else {
            self = .init(buffer: buffer)
        }
        #else
        self = .init(buffer: buffer)
        #endif  // compiler(>=6)
    }
}
