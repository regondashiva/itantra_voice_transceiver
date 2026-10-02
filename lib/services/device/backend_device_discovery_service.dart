// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:developer' as dev;
import '../../contracts/peer_device.dart';
import '../../core/config/api_config.dart';
import '../../models/device_model.dart';
import '../api/api_service.dart';
import '../communication/p2p_mesh_transport_service.dart';
import 'device_discovery_service.dart';

/// Tactical channel & nearby transceiver discovery service.
/// Automatically discovers physical nearby devices over offline Wi-Fi/Bluetooth UDP beacons
/// and merges with online C2 backend channels and tactical mesh nodes.
class BackendDeviceDiscoveryService implements DeviceDiscoveryService {
  final ApiService _apiService;
  final P2pMeshTransportService? _p2pTransport;
  final _deviceStreamController = StreamController<List<DeviceModel>>.broadcast();
  StreamSubscription? _p2pSub;

  List<DeviceModel> _cachedDevices = [];

  BackendDeviceDiscoveryService({
    required ApiService apiService,
    P2pMeshTransportService? p2pTransport,
  })  : _apiService = apiService,
        _p2pTransport = p2pTransport {
    _initP2pListener();
  }

  void _initP2pListener() {
    if (_p2pTransport != null) {
      _p2pSub = _p2pTransport.discoverPeers().listen((peers) {
        _emitMergedDevices(peers);
      });
    }
  }

  void _emitMergedDevices(List<PeerDevice> peers) {
    final liveDevices = peers.map((p) => _peerToDevice(p)).toList();
    final combined = <String, DeviceModel>{};

    for (final d in _getTacticalMeshNodes()) {
      combined[d.id] = d;
    }
    for (final d in liveDevices) {
      combined[d.id] = d;
    }

    _cachedDevices = combined.values.toList();
    _deviceStreamController.add(_cachedDevices);
  }

  DeviceModel _peerToDevice(PeerDevice peer) {
    return DeviceModel(
      id: peer.id,
      name: peer.name,
      connectionType: peer.transportType == PeerTransportType.bluetoothLe
          ? ConnectionType.bluetooth
          : ConnectionType.wifiDirect,
      signalStrength: peer.signalQuality,
      isConnected: peer.isConnected,
    );
  }

  List<DeviceModel> _getTacticalMeshNodes() {
    return const [
      DeviceModel(
        id: 'mesh_node_alpha',
        name: 'ALPHA_NODE_01 (Squad Lead)',
        connectionType: ConnectionType.wifiDirect,
        signalStrength: 0.95,
        isConnected: false,
      ),
      DeviceModel(
        id: 'mesh_node_relay',
        name: 'RELAY_BASE_STATION (Mesh Link)',
        connectionType: ConnectionType.wifiDirect,
        signalStrength: 0.90,
        isConnected: false,
      ),
      DeviceModel(
        id: 'mesh_node_delta',
        name: 'DELTA_PATROL_04 (Wi-Fi Direct)',
        connectionType: ConnectionType.wifiDirect,
        signalStrength: 0.82,
        isConnected: false,
      ),
      DeviceModel(
        id: 'ble_node_bravo',
        name: 'BRAVO_PATROL_02 (BLE Tactical)',
        connectionType: ConnectionType.bluetooth,
        signalStrength: 0.88,
        isConnected: false,
      ),
      DeviceModel(
        id: 'ble_node_charlie',
        name: 'CHARLIE_RECON_03 (BLE Mesh)',
        connectionType: ConnectionType.bluetooth,
        signalStrength: 0.80,
        isConnected: false,
      ),
      DeviceModel(
        id: 'ble_node_echo',
        name: 'ECHO_OBSERVER_05 (Bluetooth 5.0)',
        connectionType: ConnectionType.bluetooth,
        signalStrength: 0.74,
        isConnected: false,
      ),
    ];
  }

  @override
  Stream<List<DeviceModel>> get discoveredDevicesStream =>
      _deviceStreamController.stream;

  @override
  Future<List<DeviceModel>> discoverDevices({ConnectionType? type}) async {
    final allDevices = <String, DeviceModel>{};

    // 1. Seed tactical mesh nodes for both Wi-Fi and Bluetooth
    for (final node in _getTacticalMeshNodes()) {
      allDevices[node.id] = node;
    }

    // 2. Add real local peers from offline P2P transport
    if (_p2pTransport != null) {
      final localPeers = _p2pTransport.currentDiscoveredPeers;
      for (final peer in localPeers) {
        final devModel = _peerToDevice(peer);
        allDevices[devModel.id] = devModel;
      }
    }

    // 3. Fetch remote C2 tactical channels if backend is reachable (fast 2s timeout)
    try {
      final channels = await _apiService.fetchChannels().timeout(const Duration(seconds: 2));
      if (channels.isNotEmpty) {
        for (final c in channels) {
          final isCmd = c.channelId == ApiConfig.activeChannelId;
          allDevices[c.channelId] = DeviceModel(
            id: c.channelId,
            name: '${c.name} (${c.frequencyMhz} MHz)',
            connectionType: ConnectionType.wifiDirect,
            signalStrength: isCmd ? 0.98 : 0.85,
            isConnected: isCmd,
          );
        }
      }
    } catch (e) {
      dev.log('[DeviceDiscovery] Backend channel query timed out or offline, using mesh nodes.');
    }

    _cachedDevices = allDevices.values.toList();
    _deviceStreamController.add(_cachedDevices);

    // Filter by requested transport type if specified
    if (type != null) {
      final filtered = _cachedDevices.where((d) => d.connectionType == type).toList();
      return filtered;
    }

    return _cachedDevices;
  }

  @override
  Future<void> stopDiscovery() async {
    // No-op
  }

  void dispose() {
    _p2pSub?.cancel();
    _deviceStreamController.close();
  }
}
