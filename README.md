# Anam Flutter SDK

A Flutter SDK for integrating Anam's realtime Avatar system into your Flutter applications. This is a port of the [Anam JavaScript SDK](https://github.com/anam-org/javascript-sdk).

## Features

- Real-time avatar streaming via WebRTC
- Two-way audio communication
- Text messaging interface
- Event-driven architecture
- Support for custom personas
- Microphone controls

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  anam_flutter_sdk: ^0.0.1
```

## Platform Setup

### iOS

Add the following to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone for voice communication with the avatar</string>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video communication</string>
```

### macOS

1. Add the following to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone for voice communication with the avatar</string>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video communication</string>
```

2. Update your entitlements files (`DebugProfile.entitlements` and `Release.entitlements`):

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
```

### Android

Add the following permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

## Usage

### Basic Example

```dart
import 'package:anam_flutter_sdk/anam_flutter_sdk.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// Create client with API key (for development only)
final client = AnamClientFactory.unsafeCreateClientWithApiKey(
  apiKey: 'your-api-key',
  enableLogging: true,
);

// Or create client with session token (recommended for production)
final client = AnamClientFactory.createClient(
  sessionToken: 'your-session-token',
);

// Configure persona
final personaConfig = PersonaConfig(
  personaId: 'default',
  name: 'AI Assistant',
  avatarId: 'default_avatar',
  voiceId: 'default_voice',
  systemPrompt: 'You are a helpful AI assistant.',
);

// Initialize video renderer
final renderer = RTCVideoRenderer();
await renderer.initialize();

// Start avatar session
await client.talk(
  personaConfig: personaConfig,
  onStreamReady: (stream) {
    if (stream != null) {
      renderer.srcObject = stream;
    }
  },
);

// Send a message
client.sendUserMessage('Hello, how are you?');

// Toggle microphone
client.setInputAudioEnabled(false);

// Stop streaming
await client.stopStreaming();
```

### Event Handling

```dart
// Listen for message updates
client.on<List<Message>>(AnamEvent.messageHistoryUpdated).listen((messages) {
  print('Messages updated: ${messages.length}');
});

// Listen for connection events
client.on(AnamEvent.connectionEstablished).listen((_) {
  print('Connected to avatar');
});

client.on(AnamEvent.connectionClosed).listen((_) {
  print('Disconnected from avatar');
});

// Listen for errors
client.on(AnamEvent.error).listen((error) {
  print('Error occurred: $error');
});
```

### Using the Avatar View Widget

```dart
AnamAvatarView(
  renderer: renderer,
  onMicToggle: () {
    // Toggle microphone
  },
  isMicEnabled: true,
  showControls: true,
  borderRadius: 12.0,
  backgroundColor: Colors.black,
)
```

## Example App

See the `/example` folder for a complete example application demonstrating:

- API key authentication
- Avatar connection and streaming
- Real-time messaging
- Microphone controls
- Error handling

To run the example:

```bash
cd example
flutter pub get
flutter run
```

## API Reference

### AnamClient

The main client class for interacting with Anam's API.

#### Methods

- `talk(personaConfig, onStreamReady)` - Start an avatar session
- `sendUserMessage(content)` - Send a text message to the avatar
- `interruptPersona()` - Interrupt the avatar while it's speaking
- `setInputAudioEnabled(enabled)` - Enable/disable microphone
- `stopStreaming()` - End the current session
- `on<T>(event)` - Subscribe to events

### PersonaConfig

Configuration for the avatar persona.

```dart
PersonaConfig({
  required String personaId,
  required String name,
  required String avatarId,
  required String voiceId,
  String? llmId,
  String? systemPrompt,
  int? maxSessionLengthSeconds,
  String? languageCode,
})
```

### Events

Available events to subscribe to:

- `AnamEvent.messageHistoryUpdated`
- `AnamEvent.connectionEstablished`
- `AnamEvent.connectionClosed`
- `AnamEvent.videoStreamStarted`
- `AnamEvent.audioStreamStarted`
- `AnamEvent.sessionReady`
- `AnamEvent.personaTalking`
- `AnamEvent.personaListening`
- `AnamEvent.error`

## License

This SDK is licensed under the same terms as the original Anam JavaScript SDK.