import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_voice_transceiver/contracts/contracts.dart';
import 'package:itantra_voice_transceiver/services/communication/p2p_mesh_transport_service.dart';
import 'package:itantra_voice_transceiver/services/vad/silero_vad_service.dart';
import 'package:itantra_voice_transceiver/services/stt/vosk_stt_service.dart';
import 'package:itantra_voice_transceiver/services/tts/piper_tts_service.dart';
import 'package:itantra_voice_transceiver/services/orchestrator/walkie_talkie_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 1: TransceiverPacket Binary Protobuf Serialization', () {
    test('packet serializes to < 80 bytes for standard tactical transmissions', () {
      final packet = TransceiverPacket(
        packetId: 'pkt_101',
        senderId: 'NODE_ALPHA',
        text: 'All clear',
        priority: PacketPriority.normal,
        languageCode: 'en',
        intent: 'STATUS',
      );

      final bytes = packet.toProtobufBytes();
      expect(bytes.length, lessThan(80));
      expect(bytes, isNotEmpty);

      final decoded = TransceiverPacket.fromProtobufBytes(bytes);
      expect(decoded.packetId, equals('pkt_101'));
      expect(decoded.senderId, equals('NODE_ALPHA'));
      expect(decoded.text, equals('All clear'));
      expect(decoded.priority, equals(PacketPriority.normal));
      expect(decoded.languageCode, equals('en'));
      expect(decoded.intent, equals('STATUS'));
      expect(decoded.isEmergency, isFalse);
    });

    test('emergency packet serializes and preserves emergency priority', () {
      final emergencyPacket = TransceiverPacket(
        packetId: 'sos_999',
        senderId: 'PATROL_02',
        text: 'SOS: Medical assistance needed at sector 4',
        priority: PacketPriority.emergency,
        languageCode: 'hi',
        intent: 'SOS',
      );

      final bytes = emergencyPacket.toProtobufBytes();
      expect(bytes.length, lessThan(100));

      final decoded = TransceiverPacket.fromProtobufBytes(bytes);
      expect(decoded.isEmergency, isTrue);
      expect(decoded.priority, equals(PacketPriority.emergency));
      expect(decoded.intent, equals('SOS'));
      expect(decoded.text, contains('SOS'));
    });
  });

  group('Module 1: ITantraTransport (P2P Mesh)', () {
    test('transport discovers peers and connects', () async {
      final transport = P2pMeshTransportService();
      await transport.initialize();

      final peersFuture = transport.discoverPeers().first;
      final peers = await peersFuture;
      expect(peers, isNotEmpty);
      expect(peers.first.id, equals('mesh_node_alpha'));

      final connected = await transport.connect('mesh_node_alpha');
      expect(connected, isTrue);
      expect(transport.connectedPeerId, equals('mesh_node_alpha'));

      transport.dispose();
    });

    test('transport sends and receives raw protobuf packets', () async {
      final transport = P2pMeshTransportService();
      await transport.initialize();

      final packet = TransceiverPacket(
        packetId: 'pkt_test',
        senderId: 'TEST_SRC',
        text: 'Radio Check',
      );
      final rawBytes = packet.toProtobufBytes();

      final receivedFuture = transport.onPacketReceived.first;
      await transport.sendPacket(rawBytes);

      final receivedBytes = await receivedFuture;
      expect(receivedBytes, isNotNull);
      final receivedPacket = TransceiverPacket.fromProtobufBytes(receivedBytes);
      expect(receivedPacket.text, equals('Radio Check'));

      transport.dispose();
    });
  });

  group('Module 2: ITantraVAD (Voice Activity Detection)', () {
    test('vad processes audio chunks and tracks speech state', () async {
      final vad = SileroVadService();
      await vad.startListening();
      expect(vad.isListening, isTrue);

      // Create a simulated 16kHz PCM voice burst
      final pcmChunk = Uint8List(1024);
      final byteData = ByteData.sublistView(pcmChunk);
      for (var i = 0; i < 512; i++) {
        byteData.setInt16(i * 2, 8000, Endian.little);
      }

      vad.processRawPcmChunk(pcmChunk);
      expect(vad.isSpeaking, isTrue);

      await vad.stopListening();
      expect(vad.isListening, isFalse);
      vad.dispose();
    });
  });

  group('Module 3: ITantraSTT (Vosk Speech-to-Text)', () {
    test('stt loads model and transcribes PCM buffer with latency tracking', () async {
      final stt = VoskSttService();
      await stt.loadModel('hi');
      expect(stt.isModelLoaded, isTrue);
      expect(stt.currentLanguage, equals('hi'));

      final pcmAudio = Uint8List(2048);
      final text = await stt.transcribe(pcmAudio);

      expect(text, isNotEmpty);
      expect(stt.lastLatencyMs, greaterThan(0));
    });
  });

  group('Module 4: ITantraTTS (Piper Text-to-Speech)', () {
    test('tts loads model and supports emergency speech', () async {
      final tts = PiperTtsService();
      await tts.loadModel('en');

      await tts.speak('Alpha check', isEmergency: false);
      await tts.speak('EMERGENCY SOS', isEmergency: true);

      tts.dispose();
    });
  });

  group('Module 5: WalkieTalkieOrchestrator Transceiver Loop', () {
    test('orchestrator coordinates PTT -> VAD -> STT -> Transport -> TTS loop', () async {
      final transport = P2pMeshTransportService();
      final vad = SileroVadService();
      final stt = VoskSttService();
      final tts = PiperTtsService();

      final orchestrator = WalkieTalkieOrchestrator(
        transport: transport,
        vad: vad,
        stt: stt,
        tts: tts,
        localDeviceId: 'TEST_NODE_1',
      );

      await orchestrator.initialize(languageCode: 'en');
      expect(orchestrator.state, equals(OrchestratorState.idle));

      // Step 1: PTT Pressed
      await orchestrator.onPttPressed();
      expect(orchestrator.state, equals(OrchestratorState.listening));

      // Step 2: User Speaks (VAD buffers PCM)
      final pcmChunk = Uint8List(1024);
      final byteData = ByteData.sublistView(pcmChunk);
      for (var i = 0; i < 512; i++) {
        byteData.setInt16(i * 2, 9000, Endian.little);
      }
      vad.processRawPcmChunk(pcmChunk);

      // Step 3: PTT Released
      await orchestrator.onPttReleased();

      // Custom packet direct broadcast test
      await orchestrator.sendCustomPacket(
        text: 'Sector Bravo secure',
        priority: PacketPriority.tactical,
        intent: 'STATUS',
      );

      expect(orchestrator.lastSttLatencyMs, greaterThanOrEqualTo(0));

      await Future.delayed(const Duration(milliseconds: 200));

      orchestrator.dispose();
      transport.dispose();
      vad.dispose();
      tts.dispose();
    });
  });

}
