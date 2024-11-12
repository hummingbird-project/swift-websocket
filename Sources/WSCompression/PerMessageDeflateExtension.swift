//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CompressNIO
import NIOCore
import NIOWebSocket
import WSCore

/// PerMessageDeflate Websocket extension builder
struct PerMessageDeflateExtensionBuilder: WebSocketExtensionBuilder {
    static let name = "permessage-deflate"

    let clientMaxWindow: Int?
    let clientNoContextTakeover: Bool
    let serverMaxWindow: Int?
    let serverNoContextTakeover: Bool
    let compressionLevel: Int?
    let memoryLevel: Int?
    let maxDecompressedFrameSize: Int
    let minFrameSizeToCompress: Int

    init(
        clientMaxWindow: Int? = nil,
        clientNoContextTakeover: Bool = false,
        serverMaxWindow: Int? = nil,
        serverNoContextTakeover: Bool = false,
        compressionLevel: Int? = nil,
        memoryLevel: Int? = nil,
        maxDecompressedFrameSize: Int = (1 << 14),
        minFrameSizeToCompress: Int = 256
    ) {
        self.clientMaxWindow = clientMaxWindow
        self.clientNoContextTakeover = clientNoContextTakeover
        self.serverMaxWindow = serverMaxWindow
        self.serverNoContextTakeover = serverNoContextTakeover
        self.compressionLevel = compressionLevel
        self.memoryLevel = memoryLevel
        self.maxDecompressedFrameSize = maxDecompressedFrameSize
        self.minFrameSizeToCompress = minFrameSizeToCompress
    }

    /// Return client request header
    func clientRequestHeader() -> String {
        var header = "permessage-deflate"
        if let maxWindow = self.clientMaxWindow {
            header += ";client_max_window_bits=\(maxWindow)"
        }
        if self.clientNoContextTakeover {
            header += ";client_no_context_takeover"
        }
        if let maxWindow = self.serverMaxWindow {
            header += ";server_max_window_bits=\(maxWindow)"
        }
        if self.serverNoContextTakeover {
            header += ";server_no_context_takeover"
        }
        return header
    }

    /// Return server response header, given a client request
    /// - Parameter request: Client request header parameters
    /// - Returns: Server response parameters
    func serverReponseHeader(to request: WebSocketExtensionHTTPParameters) -> String? {
        let configuration = self.responseConfiguration(to: request)
        var header = "permessage-deflate"
        if let maxWindow = configuration.receiveMaxWindow {
            header += ";client_max_window_bits=\(maxWindow)"
        }
        if configuration.receiveNoContextTakeover {
            header += ";client_no_context_takeover"
        }
        if let maxWindow = configuration.sendMaxWindow {
            header += ";server_max_window_bits=\(maxWindow)"
        }
        if configuration.sendNoContextTakeover {
            header += ";server_no_context_takeover"
        }
        return header
    }

    /// Create server PerMessageDeflateExtension based off request headers
    /// - Parameters:
    ///   - request: Client request
    func serverExtension(from request: WebSocketExtensionHTTPParameters) throws -> (WebSocketExtension)? {
        let configuration = self.responseConfiguration(to: request)
        return try PerMessageDeflateExtension(configuration: configuration)
    }

    /// Create client PerMessageDeflateExtension based off response headers
    /// - Parameters:
    ///   - response: Server response
    func clientExtension(from response: WebSocketExtensionHTTPParameters) throws -> WebSocketExtension? {
        let clientMaxWindowParam = response.parameters["client_max_window_bits"]?.integer
        let clientNoContextTakeoverParam = response.parameters["client_no_context_takeover"] != nil
        let serverMaxWindowParam = response.parameters["server_max_window_bits"]?.integer
        let serverNoContextTakeoverParam = response.parameters["server_no_context_takeover"] != nil
        return try PerMessageDeflateExtension(configuration: .init(
            receiveMaxWindow: serverMaxWindowParam,
            receiveNoContextTakeover: serverNoContextTakeoverParam,
            sendMaxWindow: clientMaxWindowParam,
            sendNoContextTakeover: clientNoContextTakeoverParam,
            compressionLevel: self.compressionLevel,
            memoryLevel: self.memoryLevel,
            maxDecompressedFrameSize: self.maxDecompressedFrameSize,
            minFrameSizeToCompress: self.minFrameSizeToCompress
        ))
    }

    private func responseConfiguration(to request: WebSocketExtensionHTTPParameters) -> PerMessageDeflateExtension.Configuration {
        let requestServerMaxWindow = request.parameters["server_max_window_bits"]
        let requestServerNoContextTakeover = request.parameters["server_no_context_takeover"] != nil
        let requestClientMaxWindow = request.parameters["client_max_window_bits"]
        let requestClientNoContextTakeover = request.parameters["client_no_context_takeover"] != nil

        let receiveMaxWindow: Int?
            // calculate client max window. If parameter doesn't exist then server cannot set it, if it does
            // exist then the value should be set to minimum of both values, or the value of the other if
            // one is nil
            = if let requestClientMaxWindow
        {
            optionalMin(requestClientMaxWindow.integer, self.clientMaxWindow)
        } else {
            nil
        }

        return PerMessageDeflateExtension.Configuration(
            receiveMaxWindow: receiveMaxWindow,
            receiveNoContextTakeover: requestClientNoContextTakeover || self.clientNoContextTakeover,
            sendMaxWindow: optionalMin(requestServerMaxWindow?.integer, self.serverMaxWindow),
            sendNoContextTakeover: requestServerNoContextTakeover || self.serverNoContextTakeover,
            compressionLevel: self.compressionLevel,
            memoryLevel: self.memoryLevel,
            maxDecompressedFrameSize: self.maxDecompressedFrameSize,
            minFrameSizeToCompress: self.minFrameSizeToCompress
        )
    }
}

/// PerMessageDeflate websocket extension
///
/// Uses deflate to compress messages sent across a WebSocket
/// See RFC 7692 for more details https://www.rfc-editor.org/rfc/rfc7692
struct PerMessageDeflateExtension: WebSocketExtension {
    struct Configuration: Sendable {
        let receiveMaxWindow: Int?
        let receiveNoContextTakeover: Bool
        let sendMaxWindow: Int?
        let sendNoContextTakeover: Bool
        let compressionLevel: Int?
        let memoryLevel: Int?
        let maxDecompressedFrameSize: Int
        let minFrameSizeToCompress: Int
    }

    actor Decompressor {
        enum ReceiveState: Sendable {
            case idle
            case receivingMessage
            case decompressingMessage
        }

        fileprivate var decompressor: ZlibDecompressor
        var state: ReceiveState

        init(algorithm: ZlibAlgorithm, windowSize: Int32) throws {
            self.state = .idle
            self.decompressor = try ZlibDecompressor(algorithm: algorithm, windowSize: windowSize)
        }

        func decompress(_ frame: WebSocketFrame, maxSize: Int, resetStream: Bool, context: WebSocketExtensionContext) throws -> WebSocketFrame {
            if self.state == .idle {
                if frame.rsv1 {
                    self.state = .decompressingMessage
                } else {
                    self.state = .receivingMessage
                }
            }
            if self.state == .decompressingMessage {
                var frame = frame
                var unmaskedData = frame.unmaskedData
                if frame.fin {
                    // Reinstate last four bytes 0x00 0x00 0xff 0xff that were removed in the frame
                    // send (see  https://datatracker.ietf.org/doc/html/rfc7692#section-7.2.2).
                    unmaskedData.writeBytes([0, 0, 255, 255])
                    self.state = .idle
                }
                frame.data = try unmaskedData.decompressStream(
                    with: self.decompressor,
                    maxSize: maxSize,
                    allocator: ByteBufferAllocator()
                )
                frame.maskKey = nil
                if resetStream, frame.fin {
                    try self.decompressor.reset()
                }
                return frame
            }
            if frame.fin {
                self.state = .idle
            }
            return frame
        }
    }

    actor Compressor {
        enum SendState: Sendable {
            case idle
            case sendingMessage
        }

        fileprivate var compressor: ZlibCompressor
        var sendState: SendState
        let minFrameSizeToCompress: Int

        init(algorithm: ZlibAlgorithm, configuration: ZlibConfiguration, minFrameSizeToCompress: Int) throws {
            self.compressor = try ZlibCompressor(algorithm: algorithm, configuration: configuration)
            self.minFrameSizeToCompress = minFrameSizeToCompress
            self.sendState = .idle
        }

        func compress(_ frame: WebSocketFrame, resetStream: Bool, context: WebSocketExtensionContext) throws -> WebSocketFrame {
            // if the frame is larger than `minFrameSizeToCompress` bytes, we haven't received a final frame
            // or we are in the process of sending a message compress the data
            let shouldWeCompress = frame.data.readableBytes >= self.minFrameSizeToCompress || !frame.fin || self.sendState != .idle
            if shouldWeCompress {
                var newFrame = frame
                if self.sendState == .idle {
                    newFrame.rsv1 = true
                    self.sendState = .sendingMessage
                }
                newFrame.data = try newFrame.data.compressStream(with: self.compressor, flush: .sync, allocator: ByteBufferAllocator())
                // if final frame then remove last four bytes 0x00 0x00 0xff 0xff
                // (see  https://datatracker.ietf.org/doc/html/rfc7692#section-7.2.1)
                if newFrame.fin {
                    newFrame.data = newFrame.data.getSlice(at: newFrame.data.readerIndex, length: newFrame.data.readableBytes - 4) ?? newFrame.data
                    self.sendState = .idle
                    if resetStream {
                        try self.compressor.reset()
                    }
                }
                return newFrame
            }
            return frame
        }
    }

    let name = "permessage-deflate"
    let configuration: Configuration
    let decompressor: Decompressor
    let compressor: Compressor

    init(configuration: Configuration) throws {
        self.configuration = configuration
        self.decompressor = try .init(
            algorithm: .deflate,
            windowSize: numericCast(configuration.receiveMaxWindow ?? 15)
        )
        self.compressor = try .init(
            algorithm: .deflate,
            configuration: .init(
                windowSize: numericCast(configuration.sendMaxWindow ?? 15),
                compressionLevel: configuration.compressionLevel.map { numericCast($0) } ?? -1,
                memoryLevel: configuration.memoryLevel.map { numericCast($0) } ?? 8
            ),
            minFrameSizeToCompress: self.configuration.minFrameSizeToCompress
        )
    }

    func shutdown() async {}

    func processReceivedFrame(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
        return try await self.decompressor.decompress(
            frame,
            maxSize: self.configuration.maxDecompressedFrameSize,
            resetStream: self.configuration.receiveNoContextTakeover,
            context: context
        )
    }

    func processFrameToSend(_ frame: WebSocketFrame, context: WebSocketExtensionContext) async throws -> WebSocketFrame {
        let isCorrectType = frame.opcode == .text || frame.opcode == .binary || frame.opcode == .continuation
        if isCorrectType {
            return try await self.compressor.compress(frame, resetStream: self.configuration.sendNoContextTakeover, context: context)
        }
        return frame
    }
}

extension WebSocketExtensionFactory {
    ///  permessage-deflate websocket extension
    /// - Parameters:
    ///   - maxWindow: Max window to be used for decompression and compression
    ///   - noContextTakeover: Should we reset window on every message
    ///   - maxDecompressedFrameSize: Maximum size for a decompressed frame
    ///   - minFrameSizeToCompress: Minimum size of a frame before compression is applied
    public static func perMessageDeflate(
        maxWindow: Int? = nil,
        noContextTakeover: Bool = false,
        maxDecompressedFrameSize: Int = 1 << 14,
        minFrameSizeToCompress: Int = 256
    ) -> WebSocketExtensionFactory {
        return .init {
            PerMessageDeflateExtensionBuilder(
                clientMaxWindow: maxWindow,
                clientNoContextTakeover: noContextTakeover,
                serverMaxWindow: maxWindow,
                serverNoContextTakeover: noContextTakeover,
                compressionLevel: nil,
                memoryLevel: nil,
                maxDecompressedFrameSize: maxDecompressedFrameSize,
                minFrameSizeToCompress: minFrameSizeToCompress
            )
        }
    }

    ///  permessage-deflate websocket extension
    /// - Parameters:
    ///   - clientMaxWindow: Max window to be used for client compression
    ///   - clientNoContextTakeover: Should client reset window on every message
    ///   - serverMaxWindow: Max window to be used for server compression
    ///   - serverNoContextTakeover: Should server reset window on every message
    ///   - compressionLevel: Zlib compression level. Value between 0 and 9 where 1 gives best speed, 9 gives
    ///         give best compression and 0 gives no compression.
    ///   - memoryLevel: Defines how much memory should be given to compression. Value between 1 and 9 where 1
    ///         uses least memory and 9 give best compression and optimal speed.
    ///   - maxDecompressedFrameSize: Maximum size for a decompressed frame
    ///   - minFrameSizeToCompress: Minimum size of a frame before compression is applied
    public static func perMessageDeflate(
        clientMaxWindow: Int? = nil,
        clientNoContextTakeover: Bool = false,
        serverMaxWindow: Int? = nil,
        serverNoContextTakeover: Bool = false,
        compressionLevel: Int? = nil,
        memoryLevel: Int? = nil,
        maxDecompressedFrameSize: Int = 1 << 14,
        minFrameSizeToCompress: Int = 256
    ) -> WebSocketExtensionFactory {
        return .init {
            PerMessageDeflateExtensionBuilder(
                clientMaxWindow: clientMaxWindow,
                clientNoContextTakeover: clientNoContextTakeover,
                serverMaxWindow: serverMaxWindow,
                serverNoContextTakeover: serverNoContextTakeover,
                compressionLevel: compressionLevel,
                memoryLevel: memoryLevel,
                maxDecompressedFrameSize: maxDecompressedFrameSize,
                minFrameSizeToCompress: minFrameSizeToCompress
            )
        }
    }
}

/// Minimum of two optional integers.
///
/// Returns the other is one of them is nil
private func optionalMin(_ a: Int?, _ b: Int?) -> Int? {
    switch (a, b) {
    case (.some(let a), .some(let b)):
        return min(a, b)
    case (.some(a), .none):
        return a
    case (.none, .some(b)):
        return b
    default:
        return nil
    }
}
