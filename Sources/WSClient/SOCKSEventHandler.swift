//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2026 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore
import NIOSOCKS

final class SOCKSEventsHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny

    enum State {
        // transitions to channelActive or failed
        case initialized
        // transitions to socksEstablished or failed
        case channelActive(Scheduled<Void>)
        // final success state
        case socksEstablished
        // final success state
        case failed(Error)
    }

    private var socksEstablishedPromise: EventLoopPromise<Void>
    private let deadline: NIODeadline
    private var state: State = .initialized

    init(deadline: NIODeadline, promise: EventLoopPromise<Void>) {
        self.deadline = deadline
        self.socksEstablishedPromise = promise
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            self.connectionStarted(context: context)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        struct NoResult: Error {}
        self.socksEstablishedPromise.fail(NoResult())
    }

    func channelActive(context: ChannelHandlerContext) {
        self.connectionStarted(context: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is SOCKSProxyEstablishedEvent:
            switch self.state {
            case .initialized:
                // TODO: remove once propagation of channelActive is added to SOCKSClientHandler
                self.socksEstablishedPromise.succeed(())
                context.fireUserInboundEventTriggered(event)
            case .socksEstablished:
                preconditionFailure("`SOCKSProxyEstablishedEvent` must only be fired once.")
            case .channelActive(let scheduled):
                self.state = .socksEstablished
                scheduled.cancel()
                self.socksEstablishedPromise.succeed(())
                context.fireUserInboundEventTriggered(event)
            case .failed:
                // potentially a race with the timeout...
                break
            }
        default:
            return context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state {
        case .initialized:
            self.state = .failed(error)
            self.socksEstablishedPromise.fail(error)
        case .channelActive(let scheduled):
            scheduled.cancel()
            self.state = .failed(error)
            self.socksEstablishedPromise.fail(error)
        case .socksEstablished, .failed:
            break
        }
        context.fireErrorCaught(error)
    }

    private func connectionStarted(context: ChannelHandlerContext) {
        guard case .initialized = self.state else {
            return
        }

        let scheduled = context.eventLoop.assumeIsolated().scheduleTask(deadline: self.deadline) {
            switch self.state {
            case .initialized, .channelActive:
                // close the connection, if the handshake timed out
                context.close(mode: .all, promise: nil)
                let error = WebSocketClientError.proxyHandshakeTimeout
                self.state = .failed(error)
                self.socksEstablishedPromise.fail(error)
            case .failed, .socksEstablished:
                break
            }
        }

        self.state = .channelActive(scheduled)
    }
}
