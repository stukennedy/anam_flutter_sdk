import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

import '../events/anam_event.dart';
import '../events/event_emitter.dart';
import '../utils/client_error.dart';

class StreamingClient {
  final EventEmitter eventEmitter;
  final Logger _logger;
  final List<Map<String, dynamic>>? iceServers;
  
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  bool _isConnected = false;
  bool _inputAudioEnabled = true;

  StreamingClient({
    required this.eventEmitter,
    this.iceServers,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  Future<void> initializePeerConnection() async {
    final configuration = {
      'iceServers': iceServers ?? [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };

    try {
      _peerConnection = await createPeerConnection(configuration, constraints);
      
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        eventEmitter.emit(AnamEvent.iceConnectionStateChanged, {
          'candidate': candidate.toMap(),
        });
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        _logger.d('🔌 WebRTC Connection state changed: $state');
        
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _isConnected = true;
          _logger.d('✅ WebRTC Connected!');
          eventEmitter.emit(AnamEvent.connectionEstablished);
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                   state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _isConnected = false;
          _logger.d('❌ WebRTC Disconnected/Failed');
          eventEmitter.emit(AnamEvent.connectionClosed);
        }
      };
      
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        _logger.d('🧊 ICE Connection state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          _logger.d('🔍 ICE: Checking connectivity...');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          _logger.d('✅ ICE: Connected!');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _logger.e('❌ ICE: Connection failed!');
        }
      };
      
      _peerConnection!.onSignalingState = (RTCSignalingState state) {
        _logger.d('📡 Signaling state: $state');
      };
      
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        _logger.d('🧊 ICE Gathering state: $state');
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        _logger.d('📹 Track received: ${event.track.kind}, id: ${event.track.id}');
        _logger.d('📹 Track enabled: ${event.track.enabled}, muted: ${event.track.muted}');
        _logger.d('📹 Track settings: ${event.track.getSettings()}');
        
        if (event.streams.isNotEmpty) {
          _logger.d('📺 Stream count: ${event.streams.length}');
          _remoteStream = event.streams.first;
          _logger.d('📺 Stream ID: ${_remoteStream!.id}');
          _logger.d('📺 Stream active: ${_remoteStream!.active}');
          
          if (event.track.kind == 'video') {
            _logger.d('🎥 Video track received - emitting stream');
            eventEmitter.emit(AnamEvent.videoStreamStarted, _remoteStream);
          } else if (event.track.kind == 'audio') {
            _logger.d('🔊 Audio track received');
            eventEmitter.emit(AnamEvent.audioStreamStarted, _remoteStream);
          }
        } else {
          _logger.w('⚠️ Track received but no streams attached');
        }
      };

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        _setupDataChannel(channel);
      };
      
      // Also listen for onAddStream in case tracks come that way
      _peerConnection!.onAddStream = (MediaStream stream) {
        _logger.d('🎬 onAddStream: Stream added with ${stream.getVideoTracks().length} video tracks and ${stream.getAudioTracks().length} audio tracks');
        if (stream.getVideoTracks().isNotEmpty) {
          _logger.d('🎥 Video tracks found in stream!');
          _remoteStream = stream;
          eventEmitter.emit(AnamEvent.videoStreamStarted, stream);
        }
      };

      await _setupLocalStream();
      
      // Create data channel for bidirectional communication
      final channelConfig = RTCDataChannelInit()
        ..ordered = true;
      
      _dataChannel = await _peerConnection!.createDataChannel('anam-data', channelConfig);
      _setupDataChannel(_dataChannel!);
      _logger.d('📡 Data channel created');
      
      // Add transceivers like the JS SDK does
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      _logger.d('📹 Added video transceiver (recvonly)');
      
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _logger.d('🔊 Added audio transceiver (sendrecv)');
      
    } catch (e) {
      _logger.e('Failed to initialize peer connection', error: e);
      throw ClientError(
        message: 'Failed to initialize peer connection: ${e.toString()}',
      );
    }
  }

  Future<void> _setupLocalStream() async {
    try {
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _logger.d('Local stream setup complete');
    } catch (e) {
      _logger.e('Failed to setup local stream', error: e);
      throw ClientError(
        message: 'Failed to access microphone: ${e.toString()}',
      );
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    _logger.d('📊 Setting up data channel: ${channel.label}');
    
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      try {
        final data = jsonDecode(message.text);
        _logger.d('💬 Data channel message received: $data');
        
        eventEmitter.emit(AnamEvent.dataChannelMessage, data);
        
        if (data['type'] == 'persona_talking') {
          eventEmitter.emit(AnamEvent.personaTalking);
        } else if (data['type'] == 'persona_listening') {
          eventEmitter.emit(AnamEvent.personaListening);
        }
      } catch (e) {
        _logger.e('Failed to parse data channel message', error: e);
      }
    };

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      _logger.d('📊 Data channel state changed: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _logger.d('✅ Data channel opened!');
      }
    };
  }

  Future<Map<String, dynamic>> createOffer() async {
    try {
      // JS SDK doesn't pass any constraints to createOffer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      _logger.d('📋 Created offer with SDP: ${offer.sdp?.substring(0, 100)}...');
      
      return {
        'type': offer.type,
        'sdp': offer.sdp,
      };
    } catch (e) {
      _logger.e('Failed to create offer', error: e);
      throw ClientError(
        message: 'Failed to create offer: ${e.toString()}',
      );
    }
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> answer) async {
    try {
      final description = RTCSessionDescription(
        answer['sdp'],
        answer['type'],
      );
      
      await _peerConnection!.setRemoteDescription(description);
      _logger.d('Remote answer set successfully');
    } catch (e) {
      _logger.e('Failed to set remote answer', error: e);
      throw ClientError(
        message: 'Failed to set remote answer: ${e.toString()}',
      );
    }
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    try {
      final iceCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      
      await _peerConnection!.addCandidate(iceCandidate);
      _logger.d('ICE candidate added successfully');
    } catch (e) {
      _logger.e('Failed to add ICE candidate', error: e);
    }
  }

  void sendMessage(String message) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(message));
      _logger.d('Message sent via data channel: $message');
    } else {
      _logger.w('Cannot send message - data channel not ready');
    }
  }

  void setInputAudioEnabled(bool enabled) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = enabled;
      });
      
      _inputAudioEnabled = enabled;
      eventEmitter.emit(
        enabled ? AnamEvent.inputAudioEnabled : AnamEvent.inputAudioDisabled,
      );
      
      _logger.d('Input audio ${enabled ? "enabled" : "disabled"}');
    }
  }

  bool get isConnected => _isConnected;
  bool get inputAudioEnabled => _inputAudioEnabled;
  MediaStream? get remoteStream => _remoteStream;
  RTCPeerConnection? get peerConnection => _peerConnection;

  Future<void> close() async {
    try {
      _dataChannel?.close();
      _dataChannel = null;

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_remoteStream != null) {
        _remoteStream!.getTracks().forEach((track) {
          track.stop();
        });
        await _remoteStream!.dispose();
        _remoteStream = null;
      }

      await _peerConnection?.close();
      _peerConnection = null;

      _isConnected = false;
      _logger.d('Streaming client closed');
    } catch (e) {
      _logger.e('Error closing streaming client', error: e);
    }
  }
}