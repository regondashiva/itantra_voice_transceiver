import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/device_repository.dart';
import '../repositories/message_repository.dart';
import '../services/api/api_service.dart';
import '../services/communication/backend_communication_service.dart';
import '../services/communication/communication_service.dart';
import '../services/device/backend_device_discovery_service.dart';
import '../services/device/device_discovery_service.dart';
import '../services/location/location_service.dart';
import '../services/settings/device_settings_service.dart';
import '../services/stt/device_stt_service.dart';
import '../services/stt/stt_service.dart';
import '../services/tts/device_tts_service.dart';
import '../services/tts/tts_service.dart';
import '../services/websocket/transceiver_websocket_service.dart';
import '../services/communication/p2p_mesh_transport_service.dart';
import '../services/vad/silero_vad_service.dart';
import '../services/stt/vosk_stt_service.dart';
import '../services/tts/piper_tts_service.dart';
import '../services/orchestrator/walkie_talkie_orchestrator.dart';


final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  service.updateCurrentLocation();
  return service;
});

final deviceSettingsServiceProvider = Provider<DeviceSettingsService>((ref) {
  final service = DeviceSettingsService();
  service.init();
  return service;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final location = ref.watch(locationServiceProvider);
  final service = ApiService(locationService: location);
  ref.onDispose(() => service.dispose());
  return service;
});

final webSocketServiceProvider = Provider<TransceiverWebSocketService>((ref) {
  final location = ref.watch(locationServiceProvider);
  final service = TransceiverWebSocketService(locationService: location);
  ref.onDispose(() => service.dispose());
  return service;
});

final sttServiceProvider = Provider<SttService>((ref) {
  final service = DeviceSttService();
  ref.onDispose(() => service.dispose());
  return service;
});

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = DeviceTtsService();
  ref.onDispose(() => service.dispose());
  return service;
});

// --- iTantra Feature Contracts & Offline P2P Transceiver Modules ---

final iTantraTransportProvider = Provider<P2pMeshTransportService>((ref) {
  final service = P2pMeshTransportService();
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

final communicationServiceProvider = Provider<CommunicationService>((ref) {
  final api = ref.watch(apiServiceProvider);
  final ws = ref.watch(webSocketServiceProvider);
  final p2p = ref.watch(iTantraTransportProvider);
  final service = BackendCommunicationService(
    apiService: api,
    wsService: ws,
    p2pTransport: p2p,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final deviceDiscoveryServiceProvider = Provider<DeviceDiscoveryService>((ref) {
  final api = ref.watch(apiServiceProvider);
  final p2p = ref.watch(iTantraTransportProvider);
  final service = BackendDeviceDiscoveryService(
    apiService: api,
    p2pTransport: p2p,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final repo = MessageRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final discovery = ref.watch(deviceDiscoveryServiceProvider);
  final repo = DeviceRepository(discoveryService: discovery);
  ref.onDispose(() => repo.dispose());
  return repo;
});


final iTantraVadProvider = Provider<SileroVadService>((ref) {
  final service = SileroVadService();
  ref.onDispose(() => service.dispose());
  return service;
});

final iTantraSttProvider = Provider<VoskSttService>((ref) {
  final service = VoskSttService();
  return service;
});

final iTantraTtsProvider = Provider<PiperTtsService>((ref) {
  final service = PiperTtsService();
  ref.onDispose(() => service.dispose());
  return service;
});

final walkieTalkieOrchestratorProvider = Provider<WalkieTalkieOrchestrator>((ref) {
  final transport = ref.watch(iTantraTransportProvider);
  final vad = ref.watch(iTantraVadProvider);
  final stt = ref.watch(iTantraSttProvider);
  final tts = ref.watch(iTantraTtsProvider);

  final orchestrator = WalkieTalkieOrchestrator(
    transport: transport,
    vad: vad,
    stt: stt,
    tts: tts,
    localDeviceId: 'ITANTRA_NODE_01',
  );

  orchestrator.initialize();
  ref.onDispose(() => orchestrator.dispose());
  return orchestrator;
});

