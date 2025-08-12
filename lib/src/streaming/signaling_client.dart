import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';

import '../utils/client_error.dart';
import '../utils/constants.dart';

enum SignalingMessageType {
  offer,
  answer,
  iceCandidate,
  heartbeat,
  error,
  close,
}

class SignalingClient {
  final String sessionId;
  final String sessionToken;
  final String engineHost;
  final String engineProtocol;
  final String signallingEndpoint;
  final String? proxyUrl;
  final Logger _logger;
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  bool _isConnected = false;
  int _reconnectAttempts = 0;

  SignalingClient({
    required this.sessionId,
    required this.sessionToken,
    required this.engineHost,
    required this.engineProtocol,
    required this.signallingEndpoint,
    this.proxyUrl,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  Future<void> connect() async {
    try {
      String wsUrl;
      
      if (proxyUrl != null) {
        // Use proxy URL if provided (for server-side WebSocket)
        wsUrl = proxyUrl!;
        if (!wsUrl.contains('?')) {
          wsUrl += '?';
        } else {
          wsUrl += '&';
        }
        wsUrl += 'engineHost=$engineHost&engineProtocol=$engineProtocol&signallingEndpoint=${Uri.encodeComponent(signallingEndpoint)}&session_id=$sessionId';
        
        _logger.d('Using proxy WebSocket connection');
      } else {
        // Construct WebSocket URL from engine session data (direct connection)
        final wsProtocol = engineProtocol == 'https' ? 'wss' : 'ws';
        
        // The engineHost might already include part of the path, and signallingEndpoint 
        // includes the full path, so we need to extract just the host
        final hostParts = engineHost.split('/');
        final host = hostParts.first;
        
        wsUrl = '$wsProtocol://$host$signallingEndpoint?session_id=$sessionId';
      }
      
      _logger.d('Attempting WebSocket connection');
      _logger.d('URL: $wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startHeartbeat();
      
      _logger.d('WebSocket connection opened');
    } catch (e) {
      _logger.e('Failed to connect to signaling server', error: e);
      _scheduleReconnect();
      throw ClientError(
        message: 'Failed to connect to signaling server: ${e.toString()}',
      );
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      
      // Handle different message formats based on what we receive
      final messageType = message['type'] ?? message['actionType'];
      _logger.d('Received signaling message: $messageType');
      _logger.d('Full message: $message');
      
      if (messageType == 'heartbeat') {
        _sendHeartbeatResponse();
      } else if (messageType == 'endsession') {
        _logger.w('Session ended by server: ${message['sessionId']}');
        _isConnected = false;
        _stopHeartbeat();
        // Don't reconnect - session is terminated
        _messageController.addError(ClientError(
          message: 'Session ended by server',
        ));
        return;
      } else if (messageType == 'answer') {
        // The JS SDK receives answer with payload.connectionDescription
        final payload = message['payload'];
        if (payload != null && payload['connectionDescription'] != null) {
          _messageController.add({
            'type': 'answer',
            'data': payload['connectionDescription'],
          });
        } else {
          // Fallback for other formats
          final answerData = message['data'] ?? message['payload'] ?? message;
          _messageController.add({
            'type': 'answer',
            'data': answerData,
          });
        }
      } else if (messageType == 'icecandidate') {
        // Forward ICE candidates with consistent format
        _messageController.add({
          'type': 'ice_candidate',
          'data': message['payload'],
        });
      } else {
        _messageController.add(message);
      }
    } catch (e) {
      _logger.e('Failed to parse signaling message', error: e);
    }
  }

  void _handleError(error) {
    _logger.e('WebSocket error', error: error);
    _messageController.addError(ClientError(
      message: 'WebSocket error: ${error.toString()}',
    ));
  }

  void _handleDisconnect() {
    _logger.d('Disconnected from signaling server');
    _isConnected = false;
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Constants.heartbeatInterval, (_) {
      if (_isConnected) {
        sendMessage({
          'actionType': 'heartbeat',
          'sessionId': sessionId,
          'payload': '',
        });
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeatResponse() {
    _logger.d('💓 Received heartbeat, sending response');
    // The JS SDK doesn't seem to send heartbeat responses
    // The server heartbeats are just to keep the connection alive
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= Constants.maxReconnectAttempts) {
      _logger.e('Max reconnect attempts reached');
      _messageController.addError(ClientError(
        message: 'Failed to reconnect after ${Constants.maxReconnectAttempts} attempts',
      ));
      return;
    }

    final delay = Duration(seconds: 2 << _reconnectAttempts);
    _reconnectAttempts++;
    
    _logger.d('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
      } catch (e) {
        _logger.e('Reconnect attempt $_reconnectAttempts failed', error: e);
      }
    });
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
      final messageType = message['type'] ?? message['actionType'] ?? 'unknown';
      _logger.d('Sent signaling message: $messageType');
    } else {
      _logger.w('Cannot send message - not connected');
    }
  }

  void sendOffer(Map<String, dynamic> offer) {
    // Match JS SDK format exactly
    sendMessage({
      'actionType': 'offer',
      'sessionId': sessionId,
      'payload': {
        'connectionDescription': offer,
        'userUid': sessionId,
      },
    });
  }

  void sendIceCandidate(Map<String, dynamic> candidate) {
    sendMessage({
      'actionType': 'icecandidate',
      'sessionId': sessionId,
      'payload': candidate,
    });
  }

  bool get isConnected => _isConnected;

  Future<void> close() async {
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    await _channel?.sink.close();
    await _messageController.close();
    _isConnected = false;
    _logger.d('Signaling client closed');
  }
}