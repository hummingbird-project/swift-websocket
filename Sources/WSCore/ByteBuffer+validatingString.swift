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

#if compiler(>=6)

extension ByteBuffer {
    /// Get the string at `index` from this `ByteBuffer` decoding using the UTF-8 encoding. Does not move the reader index.
    /// The selected bytes must be readable or else `nil` will be returned.
    ///
    /// This is an alternative to `ByteBuffer.getString(at:length:)` which ensures the string is valid UTF8
    ///
    /// - Parameters:
    ///   - index: The starting index into `ByteBuffer` containing the string of interest.
    ///   - length: The number of bytes making up the string.
    /// - Returns: A `String` value containing the UTF-8 decoded selected bytes from this `ByteBuffer` or `nil` if
    ///            the requested bytes are not readable.
    @inlinable
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
    public func getValidatedString(at index: Int, length: Int) -> String? {
        guard let range = self.rangeWithinReadableBytes(index: index, length: length) else {
            return nil
        }
        return self.withUnsafeReadableBytes { pointer in
            assert(range.lowerBound >= 0 && (range.upperBound - range.lowerBound) <= pointer.count)
            return String(validating: UnsafeRawBufferPointer(fastRebase: pointer[range]), as: Unicode.UTF8.self)
        }
    }

    /// Read `length` bytes off this `ByteBuffer`, decoding it as `String` using the UTF-8 encoding. Move the reader index
    /// forward by `length`.
    ///
    /// This is an alternative to `ByteBuffer.readString(length:)` which ensures the string is valid UTF8. Is the string
    /// is not valid UTF8 then the reader index is not advanced.
    ///
    /// - Parameters:
    ///   - length: The number of bytes making up the string.
    /// - Returns: A `String` value deserialized from this `ByteBuffer` or `nil` if there aren't at least `length` bytes readable.
    @inlinable
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
    public mutating func readValidatedString(length: Int) -> String? {
        guard let result = self.getValidatedString(at: self.readerIndex, length: length) else {
            return nil
        }
        self.moveReaderIndex(forwardBy: length)
        return result
    }

    @inlinable
    func rangeWithinReadableBytes(index: Int, length: Int) -> Range<Int>? {
        guard index >= self.readerIndex, length >= 0 else {
            return nil
        }

        // both these &-s are safe, they can't underflow because both left & right side are >= 0 (and index >= readerIndex)
        let indexFromReaderIndex = index &- self.readerIndex
        assert(indexFromReaderIndex >= 0)
        guard indexFromReaderIndex <= self.readableBytes &- length else {
            return nil
        }

        let upperBound = indexFromReaderIndex &+ length // safe, can't overflow, we checked it above.

        // uncheckedBounds is safe because `length` is >= 0, so the lower bound will always be lower/equal to upper
        return Range<Int>(uncheckedBounds: (lower: indexFromReaderIndex, upper: upperBound))
    }
}

extension UnsafeRawBufferPointer {
    @inlinable
    init(fastRebase slice: Slice<UnsafeRawBufferPointer>) {
        let base = slice.base.baseAddress?.advanced(by: slice.startIndex)
        self.init(start: base, count: slice.endIndex &- slice.startIndex)
    }
}

#endif // compiler(>=6)

extension String {
    init?(buffer: ByteBuffer, validateUTF8: Bool) {
        #if compiler(>=6)
        if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, *), validateUTF8 {
            if let validatedString = buffer.getValidatedString(at: buffer.readerIndex, length: buffer.readableBytes) {
                self = validatedString
            } else {
                return nil
            }
        } else {
            self = .init(buffer: buffer)
        }
        #else
        self = .init(buffer: buffer)
        #endif // compiler(>=6)
    }
}
