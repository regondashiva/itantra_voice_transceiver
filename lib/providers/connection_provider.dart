import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_model.dart';
import '../models/device_model.dart';
import 'service_providers.dart';

class ConnectionStateModel {
  final ConnectionStatus status;
  final DeviceModel? connectedDevice;
  final List<DeviceModel> discoveredDevices;
  final ConnectionType preferredTransport;
  final String? errorMessage;

  const ConnectionStateModel({
    required this.status,
    this.connectedDevice,
    this.discoveredDevices = const [],
    this.preferredTransport = ConnectionType.wifiDirect,
    this.errorMessage,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isScanning => status == ConnectionStatus.scanning;
  bool get isConnecting => status == ConnectionStatus.connecting;

  ConnectionStateModel copyWith({
    ConnectionStatus? status,
    DeviceModel? connectedDevice,
    List<DeviceModel>? discoveredDevices,
    ConnectionType? preferredTransport,
    String? errorMessage,
    bool clearConnectedDevice = false,
  }) {
    return ConnectionStateModel(
      status: status ?? this.status,
      connectedDevice: clearConnectedDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      preferredTransport: preferredTransport ?? this.preferredTransport,
      errorMessage: errorMessage,
    );
  }
}

class ConnectionNotifier extends Notifier<ConnectionStateModel> {
  @override
  ConnectionStateModel build() {
    _init();
    final commService = ref.read(communicationServiceProvider);
    return ConnectionStateModel(
      status: commService.currentStatus,
      connectedDevice: commService.connectedDevice,
    );
  }

  void _init() {
    final commService = ref.read(communicationServiceProvider);
    final sub = commService.connectionStatusStream.listen((status) {
      state = state.copyWith(
        status: status,
        connectedDevice: commService.connectedDevice,
      );
    });

    final repo = ref.read(deviceRepositoryProvider);
    final devSub = repo.watchDiscoveredDevices().listen((devices) {
      final filtered = devices
          .where((d) => d.connectionType == state.preferredTransport)
          .toList();
      state = state.copyWith(
        discoveredDevices: filtered,
      );
    });

    ref.onDispose(() {
      sub.cancel();
      devSub.cancel();
    });

    // Trigger initial device discovery immediately on start
    Future.microtask(() => scanDevices());
  }

  void setPreferredTransport(ConnectionType type) {
    state = state.copyWith(preferredTransport: type);
    scanDevices();
  }

  Future<void> scanDevices() async {
    state = state.copyWith(status: ConnectionStatus.scanning);
    try {
      final repo = ref.read(deviceRepositoryProvider);
      final list = await repo.scanForDevices(type: state.preferredTransport);
      state = state.copyWith(
        status: state.connectedDevice != null
            ? ConnectionStatus.connected
            : ConnectionStatus.disconnected,
        discoveredDevices: list,
      );
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Failed to scan tactical channels: $e',
      );
    }
  }

  Future<void> connect(DeviceModel device) async {
    state = state.copyWith(status: ConnectionStatus.connecting);
    try {
      final commService = ref.read(communicationServiceProvider);
      await commService.connect(device);
      final repo = ref.read(deviceRepositoryProvider);
      repo.setConnectedDevice(device);
      state = state.copyWith(
        status: ConnectionStatus.connected,
        connectedDevice: device.copyWith(isConnected: true),
      );
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Failed to connect: $e',
      );
    }
  }

  Future<void> disconnect() async {
    final commService = ref.read(communicationServiceProvider);
    await commService.disconnect();
    final repo = ref.read(deviceRepositoryProvider);
    repo.disconnectDevice();
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      clearConnectedDevice: true,
    );
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStateModel>(
  ConnectionNotifier.new,
);
