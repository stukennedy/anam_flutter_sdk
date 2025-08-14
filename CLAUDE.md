# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Common Development Tasks
```bash
# Install dependencies
flutter pub get

# Run tests
flutter test

# Analyze code for issues
flutter analyze

# Format code
dart format .

# Run example app
cd example
flutter pub get
flutter run
```

### Development on different platforms
```bash
# Run on iOS simulator
flutter run -d ios

# Run on Android emulator
flutter run -d android

# Run on macOS
flutter run -d macos

# Run on web
flutter run -d chrome
```

## Architecture Overview

The Anam Flutter SDK is a Flutter package that enables real-time avatar communication via WebRTC. It's a port of the Anam JavaScript SDK designed to work seamlessly in Flutter applications.

### Core Components

1. **AnamClient** (`lib/src/anam_client.dart`): The main client class that manages sessions, WebRTC connections, and message handling. Key responsibilities:
   - Session management (creation, authentication)
   - WebRTC offer/answer negotiation
   - Message history tracking
   - Audio control (mute/unmute)
   - Event emission for state changes

2. **StreamingClient** (`lib/src/streaming/streaming_client.dart`): Handles WebRTC peer connection and media streams:
   - Creates and manages RTCPeerConnection
   - Handles ICE candidates
   - Manages audio/video tracks
   - Data channel communication

3. **SignalingClient** (`lib/src/streaming/signaling_client.dart`): WebSocket-based signaling for WebRTC negotiation:
   - Connects to Anam's signaling server (or proxy)
   - Sends/receives offers, answers, and ICE candidates
   - Handles session-related messages

4. **CoreApiClient** (`lib/src/api/core_api_client.dart`): REST API client for Anam services:
   - Session token generation
   - Session creation with persona configuration
   - API authentication handling

### Key Architectural Patterns

- **Event-Driven**: Uses EventEmitter for decoupled communication between components
- **Factory Pattern**: AnamClientFactory provides multiple ways to create clients (API key, session token, with options)
- **WebSocket Proxy Support**: Allows server-side session management while maintaining client-side WebRTC handling

### Session Flow

1. **Direct Mode** (client has API key):
   - Client creates session token using API key
   - Client creates engine session with Anam
   - Client connects directly to Anam's WebSocket

2. **Proxy Mode** (server manages sessions):
   - Server creates session using API key
   - Server provides session data and proxy URL to client
   - Client connects through server's WebSocket proxy
   - All WebRTC negotiation happens client-side as normal

### Dependencies

- `flutter_webrtc`: WebRTC implementation for Flutter
- `web_socket_channel`: WebSocket client
- `http`: HTTP client for REST API calls
- `jwt_decoder`: For session token validation
- `uuid`: Message ID generation
- `logger`: Structured logging

### Custom Audio Handling

The SDK now supports disabling client audio capture through the `disableClientAudio` option:

```dart
// Create client without microphone access
final client = AnamClientFactory.createClient(
  sessionToken: sessionToken,
  disableClientAudio: true, // Disables mic access
);
```

When `disableClientAudio: true`:
- No microphone permission is requested
- No local audio stream is created
- Audio transceiver is set to `recvonly` (receive only)
- Allows implementing custom transcription and turn-taking logic
- Data channel remains available for sending custom messages

This is useful when you want to:
- Handle transcription yourself (e.g., using device speech recognition)
- Implement custom interruption logic
- Control turn-taking behavior
- Use alternative audio input methods