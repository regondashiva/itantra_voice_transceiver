// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'dart:developer' as dev;
import '../../contracts/transceiver_packet.dart';
import '../../core/config/api_config.dart';
import '../../models/connection_model.dart';
import '../../models/device_model.dart';
import '../../models/message_model.dart';
import '../api/api_service.dart';
import '../websocket/transceiver_websocket_service.dart';
import 'communication_service.dart';
import 'p2p_mesh_transport_service.dart';

/// Hybrid Communication Transport integrating Offline P2P Mesh, REST API, and WebSocket Gateway.
/// Manages offline-first binary Protobuf transceiver transmissions, peer mesh routing,
/// and automated cloud backlog sync when online.
class BackendCommunicationService implements CommunicationService {
  final ApiService _apiService;
  final TransceiverWebSocketService _wsService;
  final P2pMeshTransportService? _p2pTransport;

  final _incomingController = StreamController<MessageModel>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  final List<MessageModel> _offlineBacklog = [];
  StreamSubscription? _wsMessageSub;
  StreamSubscription? _wsStatusSub;
  StreamSubscription? _p2pPacketSub;

  DeviceModel? _connectedDevice;
  ConnectionStatus _status = ConnectionStatus.connected;

  BackendCommunicationService({
    required ApiService apiService,
    required TransceiverWebSocketService wsService,
    P2pMeshTransportService? p2pTransport,
  })  : _apiService = apiService,
        _wsService = wsService,
        _p2pTransport = p2pTransport {
    _init();
  }

  void _init() {
    // 1. Listen to incoming cloud WebSocket messages
    _wsMessageSub = _wsService.incomingMessages.listen((msg) {
      _incomingController.add(msg);
    });

    _wsStatusSub = _wsService.statusStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        _status = ConnectionStatus.connected;
        _statusController.add(_status);
        _flushOfflineBacklog();
      }
    });

    // 2. Listen to incoming offline P2P mesh packets over local Wi-Fi / Bluetooth UDP
    _p2pPacketSub = _p2pTransport?.onPacketReceived.listen((bytes) {
      try {
        final packet = TransceiverPacket.fromProtobufBytes(bytes);
        if (packet.senderId != ApiConfig.callsign && packet.text.isNotEmpty && packet.intent != 'HEARTBEAT') {
          dev.log('[BackendComm] Received offline P2P message from ${packet.senderId}: "${packet.text}"');
          final incoming = MessageModel(
            id: packet.packetId,
            text: packet.text,
            sender: packet.senderId,
            receiver: 'You',
            timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestampMs),
            language: packet.languageCode,
            status: MessageStatus.received,
            isEmergency: packet.isEmergency,
            connectionType: ConnectionType.wifiDirect,
          );
          _incomingController.add(incoming);
        }
      } catch (e) {
        dev.log('[BackendComm] P2P packet decode error: $e');
      }
    });

    // 3. Set default tactical channel so the device is immediately ready to communicate offline
    _connectedDevice = DeviceModel(
      id: ApiConfig.activeChannelId,
      name: 'COMMAND_NET (434.25 MHz)',
      connectionType: ConnectionType.wifiDirect,
      signalStrength: 0.95,
      isConnected: true,
    );
    _status = ConnectionStatus.connected;

    // Connect to cloud gateway asynchronously in the background
    _connectInitial();
  }

  Future<void> _connectInitial() async {
    final isHealthy = await _apiService.checkHealth();
    if (isHealthy) {
      _wsService.connect();
    }
  }

  @override
  DeviceModel? get connectedDevice => _connectedDevice;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  Stream<MessageModel> get incomingMessages => _incomingController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatusStream => _statusController.stream;

  @override
  Future<void> connect(DeviceModel device) async {
    _status = ConnectionStatus.connecting;
    _statusController.add(_status);

    ApiConfig.activeChannelId = device.id;
    _p2pTransport?.connect(device.id);

    if (_wsService.status == ConnectionStatus.connected) {
      _wsService.subscribeToChannel(device.id);
    } else {
      _wsService.connect();
    }

    _connectedDevice = device.copyWith(isConnected: true);
    _status = ConnectionStatus.connected;
    _statusController.add(_status);
  }

  @override
  Future<void> disconnect() async {
    _wsService.disconnect();
    _connectedDevice = null;
    _status = ConnectionStatus.disconnected;
    _statusController.add(_status);
  }

  @override
  Future<void> sendMessage(MessageModel message) async {
    // 1. Direct offline P2P transmission over Wi-Fi / Bluetooth UDP broadcast (<80 bytes Protobuf)
    if (_p2pTransport != null) {
      final packet = TransceiverPacket(
        packetId: message.id,
        senderId: ApiConfig.callsign,
        text: message.text,
        priority: message.isEmergency ? PacketPriority.emergency : PacketPriority.normal,
        timestampMs: message.timestamp.millisecondsSinceEpoch,
        intent: message.isEmergency ? 'SOS' : 'TALK',
      );
      final protobufBytes = packet.toProtobufBytes();
      await _p2pTransport.sendPacket(protobufBytes);
    }

    // 2. Transmit via cloud WebSocket if connected
    if (_wsService.status == ConnectionStatus.connected) {
      _wsService.sendPacket(message);
    }

    // 3. Transmit via REST API ingest
    final success = await _apiService.sendIngestPacket(message);

    if (!success) {
      // Offline fallback: Buffer to backlog for cloud sync later
      dev.log('[BackendComm] Cloud unavailable, queued for C2 sync: ${message.id}');
      _offlineBacklog.add(message);
    }
  }

  /// Flushes offline queue to backend using batch sync endpoint
  Future<void> _flushOfflineBacklog() async {
    if (_offlineBacklog.isEmpty) return;

    dev.log('[BackendComm] Flushing ${_offlineBacklog.length} queued offline packets...');
    final packetsToSync = List<MessageModel>.from(_offlineBacklog);
    final success = await _apiService.syncBatchPackets(packetsToSync);

    if (success) {
      _offlineBacklog.clear();
      dev.log('[BackendComm] Offline backlog successfully synced to C2 portal.');
    }
  }

  void dispose() {
    _wsMessageSub?.cancel();
    _wsStatusSub?.cancel();
    _p2pPacketSub?.cancel();
    _incomingController.close();
    _statusController.close();
  }
}
