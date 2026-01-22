//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

/// Function that handles websocket data and text blocks
public typealias WebSocketDataHandler<Context: WebSocketContext> =
    @Sendable (WebSocketInboundStream, WebSocketOutboundWriter, Context) async throws -> Void
