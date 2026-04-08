//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

public import Logging

/// Protocol for WebSocket Data handling functions context parameter
public protocol WebSocketContext: Sendable {
    var logger: Logger { get }
}
