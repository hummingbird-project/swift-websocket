## swift-websocket

Support for WebSockets

### Overview

Package containing support for WebSockets. It contains three libraries
- WSCore: Core WebSocket handler (can be used by both server and client)
- WSClient: WebSocket client
- WSCompression: WebSocket compression support

### Client

The WebSocketClient is built on top of structured concurrency. When you connect it calls the closure you provide with an inbound stream of frames, a writer to write outbound frames and a context structure. When you exit the closure the client will automatically perform the close handshake for you. 

```swift
import WSClient

let ws = WebSocketClient.connect(url: "ws://mywebsocket.com/ws") { inbound, outbound, context in
    try await outbound.write(.text("Hello"))
    // you can convert the inbound stream of frames into a stream of full messages using `messages(maxSize:)`
    for try await frame in inbound.messages(maxSize: 1 << 14) {
        context.logger.info(frame)
    }
}
```
