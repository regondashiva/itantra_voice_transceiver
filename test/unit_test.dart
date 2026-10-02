import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_voice_transceiver/core/constants/app_constants.dart';
import 'package:itantra_voice_transceiver/models/connection_model.dart';
import 'package:itantra_voice_transceiver/models/device_model.dart';
import 'package:itantra_voice_transceiver/models/language_model.dart';
import 'package:itantra_voice_transceiver/models/message_model.dart';
import 'package:itantra_voice_transceiver/providers/emergency_provider.dart';
import 'package:itantra_voice_transceiver/providers/language_provider.dart';
import 'package:itantra_voice_transceiver/providers/service_providers.dart';
import 'package:itantra_voice_transceiver/repositories/message_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:itantra_voice_transceiver/core/config/api_config.dart';
import 'package:itantra_voice_transceiver/services/api/api_service.dart';
import 'package:itantra_voice_transceiver/services/communication/communication_service.dart';


class FakeCommunicationService implements CommunicationService {
  @override
  DeviceModel? get connectedDevice => null;
  @override
  ConnectionStatus get currentStatus => ConnectionStatus.connected;
  @override
  Stream<ConnectionStatus> get connectionStatusStream => const Stream.empty();
  @override
  Stream<MessageModel> get incomingMessages => const Stream.empty();
  @override
  Future<void> connect(DeviceModel device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendMessage(MessageModel message) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Model & Constant Tests', () {
    test('LanguageModel equality and string formatting', () {
      const lang1 = LanguageModel(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు');
      const lang2 = LanguageModel(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు');
      expect(lang1, equals(lang2));
      expect(lang1.toString(), 'Telugu (తెలుగు)');
    });

    test('Supported languages include 10 required Indian languages', () {
      final codes = AppConstants.supportedLanguages.map((l) => l.code).toSet();
      expect(codes.contains('en'), isTrue);
      expect(codes.contains('hi'), isTrue);
      expect(codes.contains('te'), isTrue);
      expect(codes.contains('ta'), isTrue);
      expect(codes.contains('kn'), isTrue);
      expect(codes.contains('ml'), isTrue);
      expect(codes.contains('mr'), isTrue);
      expect(codes.contains('gu'), isTrue);
      expect(codes.contains('bn'), isTrue);
      expect(codes.contains('or'), isTrue);
    });

    test('MessageModel creation and copyWith', () {
      final now = DateTime.now();
      final msg = MessageModel(
        id: 'test-1',
        text: 'Send the location to the rescue team.',
        sender: 'You',
        receiver: 'iTantra-Rescue-01',
        timestamp: now,
        language: 'English → Telugu',
        status: MessageStatus.sending,
      );

      expect(msg.isSentByMe, isTrue);
      final delivered = msg.copyWith(status: MessageStatus.delivered);
      expect(delivered.status, MessageStatus.delivered);
    });

    test('DeviceModel connectionType label is correct', () {
      const device = DeviceModel(
        id: 'dev-001',
        name: 'iTantra-Rescue-01',
        connectionType: ConnectionType.wifiDirect,
        signalStrength: 0.85,
      );
      // The extension on ConnectionType provides a label getter
      expect(device.connectionType.label, 'Wi-Fi Direct');
      expect(device.signalStrength, greaterThan(0.5));
    });
  });



  group('Emergency State Transition Tests', () {
    test('Emergency state transitions from Idle -> Confirming -> Sent -> Received -> Idle', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'OK', 'token': 'mock-jwt'}), 200);
      });
      final mockApi = ApiService(client: mockClient);
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(mockApi),
          communicationServiceProvider.overrideWithValue(FakeCommunicationService()),
        ],
      );
      addTearDown(() {
        container.dispose();
        mockApi.dispose();
      });

      final notifier = container.read(emergencyProvider.notifier);
      expect(container.read(emergencyProvider).state, EmergencyState.idle);

      // Arm
      notifier.arm('Medical emergency. Immediate assistance required.');
      expect(container.read(emergencyProvider).isConfirming, isTrue);

      // Confirm & Send
      await notifier.confirmAndSend();
      expect(container.read(emergencyProvider).isSent, isTrue);

      // Simulate receiving
      notifier.simulateReceiveEmergency(
        text: 'Rescue team en route to grid.',
        sender: 'iTantra-Rescue-01',
      );
      expect(container.read(emergencyProvider).isReceived, isTrue);

      // Acknowledge
      notifier.acknowledge();
      expect(container.read(emergencyProvider).state, EmergencyState.idle);
    });
  });

  group('Language Provider Tests', () {
    test('LanguageNotifier switches and swaps language pairs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(languageProvider.notifier);
      expect(container.read(languageProvider).pairLabel, 'English → Telugu');

      notifier.swapLanguages();
      expect(container.read(languageProvider).pairLabel, 'Telugu → English');
    });
  });

  group('MessageRepository Tests', () {
    test('Repository initializes with seed history and filters correctly', () {
      final repo = MessageRepository();
      expect(repo.getAll().isNotEmpty, isTrue);

      final sentMessages = repo.getFiltered(MessageFilter.sent);
      for (final m in sentMessages) {
        expect(m.isSentByMe, isTrue);
      }

      final emergencyMessages = repo.getFiltered(MessageFilter.emergency);
      for (final m in emergencyMessages) {
        expect(m.isEmergency, isTrue);
      }

      repo.dispose();
    });
  });

  group('Backend API Integration Guide Tests', () {
    test('ApiConfig URLs format correctly for production, emulator and LAN', () {
      ApiConfig.environment = BackendEnvironment.production;
      expect(ApiConfig.baseUrl, equals('https://itantra-backend-bwoq.onrender.com'));
      expect(ApiConfig.wsUrl, equals('wss://itantra-backend-bwoq.onrender.com/v1/transceiver/channel'));

      ApiConfig.environment = BackendEnvironment.emulator;
      expect(ApiConfig.baseUrl, equals('http://10.0.2.2:3000'));
      expect(ApiConfig.wsUrl, equals('ws://10.0.2.2:3000/v1/transceiver/channel'));

      ApiConfig.environment = BackendEnvironment.lan;
      ApiConfig.lanHostIp = '192.168.1.50';
      expect(ApiConfig.baseUrl, equals('http://192.168.1.50:3000'));
      expect(ApiConfig.wsUrl, equals('ws://192.168.1.50:3000/v1/transceiver/channel'));

      // Reset to production
      ApiConfig.environment = BackendEnvironment.production;
    });

    test('ApiService fallback model manifest returns required AI models', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server unavailable', 503);
      });
      final api = ApiService(client: mockClient);
      final manifest = await api.fetchModelManifest();
      expect(manifest, isNotEmpty);
      expect(manifest.any((m) => m['id'].toString().contains('vosk') || m['id'].toString().contains('whisper')), isTrue);
      expect(manifest.any((m) => m['id'].toString().contains('piper')), isTrue);
      api.dispose();
    });
  });
}

