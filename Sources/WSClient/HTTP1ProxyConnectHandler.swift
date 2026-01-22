//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTP1

final class HTTP1ProxyConnectHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias OutboundIn = Never
    typealias OutboundOut = HTTPClientRequestPart
    typealias InboundIn = HTTPClientResponsePart

    /// Whether we've already seen the first request.
    private var seenFirstRequest = false
    private var bufferedWrittenMessages: MarkedCircularBuffer<BufferedWrite>

    struct BufferedWrite {
        var data: NIOAny
        var promise: EventLoopPromise<Void>?
    }

    private enum State {
        // transitions to `.connectSent` or `.failed`
        case initialized
        // transitions to `.headReceived` or `.failed`
        case connectSent(Scheduled<Void>)
        // transitions to `.completed` or `.failed`
        case headReceived(Scheduled<Void>)
        // final error state
        case failed(Error)
        // final success state
        case completed
    }

    private var state: State = .initialized

    private let targetHost: String
    private let targetPort: Int
    private let headers: HTTPHeaders
    private let deadline: NIODeadline
    private let promise: EventLoopPromise<Void>?

    /// Creates a new ``NIOHTTP1ProxyConnectHandler`` that issues a CONNECT request to a proxy server
    /// and instructs the server to connect to `targetHost`.
    /// - Parameters:
    ///   - targetHost: The desired end point host
    ///   - targetPort: The port to be used when connecting to `targetHost`
    ///   - headers: Headers to supply to the proxy server as part of the CONNECT request
    ///   - deadline: Deadline for the CONNECT request
    ///   - promise: Promise with which the result of the connect operation is communicated
    init(
        targetHost: String,
        targetPort: Int,
        headers: HTTPHeaders,
        deadline: NIODeadline,
        promise: EventLoopPromise<Void>?
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.headers = headers
        self.deadline = deadline
        self.promise = promise

        self.bufferedWrittenMessages = MarkedCircularBuffer(initialCapacity: 16)  // matches CircularBuffer default
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch self.state {
        case .initialized, .connectSent, .headReceived, .completed:
            self.bufferedWrittenMessages.append(BufferedWrite(data: data, promise: promise))
        case .failed(let error):
            promise?.fail(error)
        }
    }

    func flush(context: ChannelHandlerContext) {
        self.bufferedWrittenMessages.mark()
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        // We have been formally removed from the pipeline. We should send any buffered data we have.
        switch self.state {
        case .initialized, .connectSent, .headReceived, .failed:
            self.failWithError(.noResult, context: context)

        case .completed:
            while let (bufferedPart, isMarked) = self.bufferedWrittenMessages.popFirstCheckMarked() {
                context.write(bufferedPart.data, promise: bufferedPart.promise)
                if isMarked {
                    context.flush()
                }
            }
        }

        context.leavePipeline(removalToken: removalToken)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            self.sendConnect(context: context)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        switch self.state {
        case .failed, .completed:
            guard self.bufferedWrittenMessages.isEmpty else {
                self.failWithError(HTTPProxyError.droppedWrites, context: context)
                return
            }
            break

        case .initialized, .connectSent, .headReceived:
            self.failWithError(HTTPProxyError.noResult, context: context)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        self.sendConnect(context: context)
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .initialized:
            self.failWithError(HTTPProxyError.channelUnexpectedlyInactive, context: context, closeConnection: false)
        case .connectSent(let timeout), .headReceived(let timeout):
            timeout.cancel()
            self.failWithError(HTTPProxyError.remoteConnectionClosed, context: context, closeConnection: false)

        case .failed, .completed:
            break
        }
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            self.handleHTTPHeadReceived(head, context: context)
        case .body:
            self.handleHTTPBodyReceived(context: context)
        case .end:
            self.handleHTTPEndReceived(context: context)
        }
    }

    private func sendConnect(context: ChannelHandlerContext) {
        guard case .initialized = self.state else {
            // we might run into this handler twice, once in handlerAdded and once in channelActive.
            return
        }

        let timeout = context.eventLoop.assumeIsolated().scheduleTask(deadline: self.deadline) {
            switch self.state {
            case .initialized:
                preconditionFailure("How can we have a scheduled timeout, if the connection is not even up?")

            case .connectSent, .headReceived:
                self.failWithError(HTTPProxyError.httpProxyHandshakeTimeout, context: context)

            case .failed, .completed:
                break
            }
        }

        self.state = .connectSent(timeout)

        let head = HTTPRequestHead(
            version: .init(major: 1, minor: 1),
            method: .CONNECT,
            uri: "\(self.targetHost):\(self.targetPort)",
            headers: self.headers
        )

        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }

    private func handleHTTPHeadReceived(_ head: HTTPResponseHead, context: ChannelHandlerContext) {
        switch self.state {
        case .connectSent(let scheduled):
            switch head.status.code {
            case 200..<300:
                // Any 2xx (Successful) response indicates that the sender (and all
                // inbound proxies) will switch to tunnel mode immediately after the
                // blank line that concludes the successful response's header section
                self.state = .headReceived(scheduled)
            case 407:
                self.failWithError(HTTPProxyError.proxyAuthenticationRequired, context: context)

            default:
                // Any response other than a successful response indicates that the tunnel
                // has not yet been formed and that the connection remains governed by HTTP.
                self.failWithError(HTTPProxyError.invalidProxyResponseHead, context: context)
            }
        case .failed:
            break
        case .initialized, .headReceived, .completed:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    private func handleHTTPBodyReceived(context: ChannelHandlerContext) {
        switch self.state {
        case .headReceived(let timeout):
            timeout.cancel()
            // we don't expect a body
            self.failWithError(HTTPProxyError.invalidProxyResponse, context: context)
        case .failed:
            // ran into an error before... ignore this one
            break
        case .completed, .connectSent, .initialized:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    private func handleHTTPEndReceived(context: ChannelHandlerContext) {
        switch self.state {
        case .headReceived(let timeout):
            timeout.cancel()
            self.state = .completed
        case .failed:
            // ran into an error before... ignore this one
            return
        case .initialized, .connectSent, .completed:
            preconditionFailure("Invalid state: \(self.state)")
        }

        // Ok, we've set up the proxy connection. We can now remove ourselves, which should happen synchronously.
        context.pipeline.syncOperations.removeHandler(context: context, promise: promise)
    }

    private func failWithError(_ error: HTTPProxyError, context: ChannelHandlerContext, closeConnection: Bool = true) {
        switch self.state {
        case .failed:
            return
        case .initialized, .connectSent, .headReceived, .completed:
            self.state = .failed(error)
            self.promise?.fail(error)
            context.fireErrorCaught(error)
            if closeConnection {
                context.close(mode: .all, promise: nil)
            }
            while let bufferedWrite = self.bufferedWrittenMessages.popFirst() {
                bufferedWrite.promise?.fail(error)
            }
        }
    }

}

/// Error thrown by ``HTTP1ProxyConnectHandler``
enum HTTPProxyError: String, Error {
    case proxyAuthenticationRequired
    case invalidProxyResponseHead
    case invalidProxyResponse
    case remoteConnectionClosed
    case httpProxyHandshakeTimeout
    case noResult
    case channelUnexpectedlyInactive
    case droppedWrites
}

extension HTTPProxyError: CustomStringConvertible {
    var description: String {
        switch self {
        case .proxyAuthenticationRequired:
            return "Proxy Authentication Required"
        case .invalidProxyResponseHead:
            return "Invalid Proxy Response Head"
        case .invalidProxyResponse:
            return "Invalid Proxy Response"
        case .remoteConnectionClosed:
            return "Remote Connection Closed"
        case .httpProxyHandshakeTimeout:
            return "HTTP Proxy Handshake Timeout"
        case .noResult:
            return "No Result"
        case .channelUnexpectedlyInactive:
            return "Channel Unexpectedly Inactive"
        case .droppedWrites:
            return "Handler Was Removed with Writes Left in the Buffer"
        }
    }
}

extension MarkedCircularBuffer {
    @inlinable
    internal mutating func popFirstCheckMarked() -> (Element, Bool)? {
        let marked = self.markedElementIndex == self.startIndex
        return self.popFirst().map { ($0, marked) }
    }
}
