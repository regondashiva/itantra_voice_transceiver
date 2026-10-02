// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../contracts/transceiver_packet.dart';
import '../../core/config/api_config.dart';
import '../../models/connection_model.dart';
import '../../models/device_model.dart';
import '../../models/message_model.dart';
import '../location/location_service.dart';

/// Real WebSocket Gateway Client for bidirectional real-time Protobuf packet exchange.
/// Implements Section 5 of BACKEND_API_INTEGRATION_GUIDE_ITantra.
class TransceiverWebSocketService {
  final LocationService? _locationService;
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isDisposed = false;

  TransceiverWebSocketService({LocationService? locationService})
      : _locationService = locationService;

  final _incomingMessageController = StreamController<MessageModel>.broadcast();
  final _incomingProtobufController = StreamController<TransceiverPacket>.broadcast();
  final _incomingSosController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  LocationService? get locationService => _locationService;
  ConnectionStatus get status => _status;
  Stream<MessageModel> get incomingMessages => _incomingMessageController.stream;
  Stream<TransceiverPacket> get incomingProtobufPackets => _incomingProtobufController.stream;
  Stream<Map<String, dynamic>> get incomingSosStream => _incomingSosController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  /// Connect to the WebSocket stream gateway (`ws://<HOST>:3000/v1/transceiver/channel`)

  void connect() {
    if (_isDisposed) return;
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.connected) return;

    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(ApiConfig.wsUrl);
      dev.log('[WebSocketService] Connecting to ${ApiConfig.wsUrl}');

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          _handleIncomingData(data);
        },
        onDone: () {
          dev.log('[WebSocketService] Connection closed');
          _setStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onError: (error) {
          dev.log('[WebSocketService] Connection error: $error');
          _setStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _setStatus(ConnectionStatus.connected);
      _startHeartbeat();
    } catch (e) {
      dev.log('[WebSocketService] Exception during connect: $e');
      _setStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(_status);
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == ConnectionStatus.connected) {
        final hbPacket = TransceiverPacket(
          packetId: 'hb_${DateTime.now().millisecondsSinceEpoch}',
          senderId: ApiConfig.callsign,
          text: 'HEARTBEAT_ACK',
          intent: 'HEARTBEAT',
          priority: PacketPriority.normal,
        );
        sendProtobufPacket(hbPacket);
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isDisposed && _status == ConnectionStatus.disconnected) {
        dev.log('[WebSocketService] Attempting automatic reconnect...');
        connect();
      }
    });
  }

  /// Subscribe to specific channel
  void subscribeToChannel(String channelId) {
    ApiConfig.activeChannelId = channelId;
    final packet = TransceiverPacket(
      packetId: 'sub_${DateTime.now().millisecondsSinceEpoch}',
      senderId: ApiConfig.callsign,
      text: channelId,
      intent: 'SUBSCRIBE',
    );
    sendProtobufPacket(packet);
  }

  /// Sends a binary Protobuf packet (<80 bytes) over WebSocket
  void sendProtobufPacket(TransceiverPacket packet) {
    if (_channel == null || _status != ConnectionStatus.connected) return;
    try {
      final bytes = packet.toProtobufBytes();
      dev.log('[WebSocketService] Sending Protobuf packet (${bytes.length} bytes): "${packet.text}"');
      _channel!.sink.add(bytes);
    } catch (e) {
      dev.log('[WebSocketService] Error sending Protobuf packet: $e');
    }
  }

  /// Send compact-text packet over WebSocket (converts to Protobuf)
  void sendPacket(MessageModel message) {
    final packet = TransceiverPacket(
      packetId: message.id,
      senderId: ApiConfig.callsign,
      text: message.text,
      priority: message.isEmergency ? PacketPriority.emergency : PacketPriority.normal,
      timestampMs: message.timestamp.millisecondsSinceEpoch,
      intent: message.isEmergency ? 'SOS' : 'TALK',
    );
    sendProtobufPacket(packet);
  }

  /// Send emergency SOS alert over WebSocket
  void sendSos(MessageModel message) {
    final packet = TransceiverPacket(
      packetId: message.id,
      senderId: ApiConfig.callsign,
      text: message.text,
      priority: PacketPriority.emergency,
      timestampMs: message.timestamp.millisecondsSinceEpoch,
      intent: 'SOS',
    );
    sendProtobufPacket(packet);
  }

  void _handleIncomingData(dynamic rawData) {
    try {
      if (rawData is List<int>) {
        // Incoming Protobuf binary data
        final bytes = rawData is Uint8List ? rawData : Uint8List.fromList(rawData);
        final packet = TransceiverPacket.fromProtobufBytes(bytes);
        dev.log('[WebSocketService] Received incoming Protobuf packet from ${packet.senderId}: "${packet.text}"');

        if (!_incomingProtobufController.isClosed) {
          _incomingProtobufController.add(packet);
        }

        final msg = MessageModel(
          id: packet.packetId,
          text: packet.text,
          sender: packet.senderId == ApiConfig.callsign ? 'You' : packet.senderId,
          receiver: 'You',
          timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestampMs),
          language: packet.languageCode,
          status: MessageStatus.received,
          isEmergency: packet.isEmergency,
          connectionType: ConnectionType.wifiDirect,
        );

        if (!_incomingMessageController.isClosed) {
          _incomingMessageController.add(msg);
        }

        if (packet.isEmergency && !_incomingSosController.isClosed) {
          _incomingSosController.add({
            'incidentId': packet.packetId,
            'callsign': packet.senderId,
            'text': packet.text,
            'alertType': 'CRITICAL_SOS_BROADCAST',
          });
        }
      } else if (rawData is String) {
        // Fallback for JSON strings
        final json = jsonDecode(rawData) as Map<String, dynamic>;
        final event = json['event'] as String? ?? '';
        final senderCallsign = json['callsign'] as String? ?? 'REMOTE';
        final data = (json['data'] as Map<String, dynamic>?) ?? {};

        switch (event) {
          case 'INGEST_PACKET_RECEIVED':
            final payload = data['compactTextPayload'] as String? ?? '';
            final packetId = data['packetId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
            final isEmergency = data['priority'] == 'PRIORITY_EMERGENCY_SOS';

            final incoming = MessageModel(
              id: packetId,
              text: payload,
              sender: senderCallsign == ApiConfig.callsign ? 'You' : senderCallsign,
              receiver: 'You',
              timestamp: DateTime.now(),
              language: 'Tactical Stream',
              status: MessageStatus.received,
              isEmergency: isEmergency,
              connectionType: ConnectionType.wifiDirect,
            );

            if (!_incomingMessageController.isClosed) {
              _incomingMessageController.add(incoming);
            }
            break;

          case 'CRITICAL_SOS_TRIGGERED':
            if (!_incomingSosController.isClosed) {
              _incomingSosController.add({
                'incidentId': data['incidentId'] ?? '',
                'callsign': senderCallsign,
                'packetId': data['packetId'] ?? '',
                'alertType': data['alertType'] ?? 'CRITICAL_SOS_BROADCAST',
              });
            }
            break;

          default:
            dev.log('[WebSocketService] Received event: $event');
            break;
        }
      }
    } catch (e) {
      dev.log('[WebSocketService] Error parsing incoming data: $e');
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    if (!_incomingMessageController.isClosed) {
      _incomingMessageController.close();
    }
    if (!_incomingProtobufController.isClosed) {
      _incomingProtobufController.close();
    }
    if (!_incomingSosController.isClosed) {
      _incomingSosController.close();
    }
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}
