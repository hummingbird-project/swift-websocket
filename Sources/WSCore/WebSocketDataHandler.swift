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

/// Function that handles websocket data and text blocks
public typealias WebSocketDataHandler<Context: WebSocketContext> =
    @Sendable (WebSocketInboundStream, WebSocketOutboundWriter, Context) async throws -> Void
