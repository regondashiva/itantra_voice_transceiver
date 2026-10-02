import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../contracts/itantra_stt.dart';
import '../../contracts/itantra_transport.dart';
import '../../contracts/itantra_tts.dart';
import '../../contracts/itantra_vad.dart';
import '../../contracts/transceiver_packet.dart';
import '../../contracts/walkie_talkie_orchestrator.dart';

/// Module 5 Implementation: WalkieTalkieOrchestrator.
/// Binds ITantraTransport, ITantraVAD, ITantraSTT, and ITantraTTS into the full transceiver loop:
/// 1. PTT Pressed -> ITantraVAD.startListening()
/// 2. User Speaks -> VAD pipes audio buffer to memory
/// 3. User Pauses / Released -> VAD triggers onSpeechEnded
/// 4. ITantraSTT.transcribe() processes buffer into text
/// 5. TransceiverPacket (Protobuf) created (<80 bytes)
/// 6. ITantraTransport.sendPacket() broadcasts byte array
/// 7. (Receiver) ITantraTransport.onPacketReceived fires
/// 8. Packet decoded from Protobuf
/// 9. ITantraTTS.speak() plays audio on receiver (with emergency volume override if emergency)
class WalkieTalkieOrchestrator implements WalkieTalkieOrchestratorContract {
  static const _uuid = Uuid();

  final ITantraTransport transport;
  final ITantraVAD vad;
  final ITantraSTT stt;
  final ITantraTTS tts;
  final String localDeviceId;

  OrchestratorState _state = OrchestratorState.idle;
  int _lastSttLatencyMs = 0;
  String _currentLanguage = 'en';
  bool _isDisposed = false;

  final BytesBuilder _audioBuffer = BytesBuilder(copy: false);
  final _stateController = StreamController<OrchestratorState>.broadcast();
  final _packetController = StreamController<TransceiverPacket>.broadcast();

  StreamSubscription? _speechDetectedSub;
  StreamSubscription? _speechEndedSub;
  StreamSubscription? _packetReceivedSub;

  WalkieTalkieOrchestrator({
    required this.transport,
    required this.vad,
    required this.stt,
    required this.tts,
    this.localDeviceId = 'LOCAL_NODE_01',
  });

  @override
  OrchestratorState get state => _state;

  @override
  Stream<OrchestratorState> get stateStream => _stateController.stream;

  @override
  Stream<TransceiverPacket> get packetStream => _packetController.stream;

  @override
  int get lastSttLatencyMs => _lastSttLatencyMs;

  void _setState(OrchestratorState newState) {
    if (_isDisposed || _stateController.isClosed) return;
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> initialize({String languageCode = 'en'}) async {
    if (_isDisposed) return;
    _currentLanguage = languageCode;
    dev.log('[WalkieTalkieOrchestrator] Initializing all transceiver modules...');

    await transport.initialize();
    await stt.loadModel(_currentLanguage);
    await tts.loadModel(_currentLanguage);

    // Step 2 & 3: Listen to VAD audio buffers and speech end events
    _speechDetectedSub?.cancel();
    _speechDetectedSub = vad.onSpeechDetected.listen((pcmChunk) {
      if (_state == OrchestratorState.listening || _state == OrchestratorState.vadTriggered) {
        _setState(OrchestratorState.vadTriggered);
        _audioBuffer.add(pcmChunk);
      }
    });

    _speechEndedSub?.cancel();
    _speechEndedSub = vad.onSpeechEnded.listen((_) {
      dev.log('[WalkieTalkieOrchestrator] VAD speech silence detected -> Processing speech buffer');
      _processRecordedBuffer();
    });

    // Step 7: Listen to incoming transport packets on receiver side
    _packetReceivedSub?.cancel();
    _packetReceivedSub = transport.onPacketReceived.listen(_onIncomingProtobufPacket);

    _setState(OrchestratorState.idle);
    dev.log('[WalkieTalkieOrchestrator] Transceiver ready in idle state.');
  }

  /// Step 1: Push-To-Talk (PTT) Pressed -> ITantraVAD.startListening()
  @override
  Future<void> onPttPressed() async {
    if (_isDisposed || _state == OrchestratorState.speaking) {
      return;
    }

    _audioBuffer.clear();
    _setState(OrchestratorState.listening);
    dev.log('[WalkieTalkieOrchestrator] PTT Pressed -> Starting VAD');
    await vad.startListening();
  }

  /// Step 3: Push-To-Talk Released
  @override
  Future<void> onPttReleased() async {
    if (_isDisposed) return;
    if (_state == OrchestratorState.listening || _state == OrchestratorState.vadTriggered) {
      dev.log('[WalkieTalkieOrchestrator] PTT Released -> Stopping VAD');
      await vad.stopListening();
      await _processRecordedBuffer();
    }
  }

  /// Steps 4 - 6: Transcribe PCM -> Create Protobuf -> Broadcast
  Future<void> _processRecordedBuffer() async {
    if (_isDisposed) return;
    if (_state == OrchestratorState.transcribing || _state == OrchestratorState.broadcasting) {
      return;
    }

    final pcmBytes = _audioBuffer.takeBytes();
    if (pcmBytes.isEmpty) {
      _setState(OrchestratorState.idle);
      return;
    }

    try {
      // Step 4: Local STT Transcription
      _setState(OrchestratorState.transcribing);
      final sw = Stopwatch()..start();
      final transcribedText = await stt.transcribe(pcmBytes);
      sw.stop();
      _lastSttLatencyMs = sw.elapsedMilliseconds;

      dev.log('[WalkieTalkieOrchestrator] STT completed: "$transcribedText" in ${_lastSttLatencyMs}ms');

      if (transcribedText.trim().isEmpty) {
        _setState(OrchestratorState.idle);
        return;
      }

      // Step 5: TransceiverPacket (Protobuf) created
      final packet = TransceiverPacket(
        packetId: 'pkt_${_uuid.v4().substring(0, 8)}',
        senderId: localDeviceId,
        text: transcribedText.trim(),
        priority: PacketPriority.normal,
        languageCode: _currentLanguage,
        intent: 'TALK',
      );

      final protobufBytes = packet.toProtobufBytes();
      dev.log('[WalkieTalkieOrchestrator] Protobuf packet size: ${protobufBytes.length} bytes (Target: <80 bytes)');

      // Step 6: ITantraTransport.sendPacket() broadcasts byte array
      _setState(OrchestratorState.broadcasting);
      await transport.sendPacket(protobufBytes);

      if (!_packetController.isClosed) {
        _packetController.add(packet);
      }
      _setState(OrchestratorState.packetSent);

      // Return to idle after brief pause
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!_isDisposed && _state == OrchestratorState.packetSent) {
          _setState(OrchestratorState.idle);
        }
      });
    } catch (e) {
      dev.log('[WalkieTalkieOrchestrator] Processing error: $e');
      _setState(OrchestratorState.error);
    }
  }

  /// Step 7 - 9: Incoming packet received -> Decode Protobuf -> ITantraTTS.speak()
  Future<void> _onIncomingProtobufPacket(Uint8List protobufBytes) async {
    if (_isDisposed) return;
    try {
      // Step 8: Decode Protobuf
      final packet = TransceiverPacket.fromProtobufBytes(protobufBytes);
      dev.log('[WalkieTalkieOrchestrator] Received packet from ${packet.senderId}: "${packet.text}" (Priority: ${packet.priority.name})');

      if (!_packetController.isClosed) {
        _packetController.add(packet);
      }
      _setState(OrchestratorState.packetReceived);

      // Step 9: ITantraTTS.speak() plays audio on receiver
      _setState(OrchestratorState.speaking);
      await tts.speak(packet.text, isEmergency: packet.isEmergency);

      _setState(OrchestratorState.idle);
    } catch (e) {
      dev.log('[WalkieTalkieOrchestrator] Packet decode/speech error: $e');
      _setState(OrchestratorState.idle);
    }
  }

  @override
  Future<void> sendCustomPacket({
    required String text,
    PacketPriority priority = PacketPriority.normal,
    String intent = 'TALK',
  }) async {
    if (_isDisposed) return;
    final packet = TransceiverPacket(
      packetId: 'pkt_${_uuid.v4().substring(0, 8)}',
      senderId: localDeviceId,
      text: text.trim(),
      priority: priority,
      languageCode: _currentLanguage,
      intent: intent,
    );

    final protobufBytes = packet.toProtobufBytes();
    _setState(OrchestratorState.broadcasting);
    await transport.sendPacket(protobufBytes);

    if (!_packetController.isClosed) {
      _packetController.add(packet);
    }
    _setState(OrchestratorState.packetSent);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_isDisposed && _state == OrchestratorState.packetSent) {
        _setState(OrchestratorState.idle);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _speechDetectedSub?.cancel();
    _speechEndedSub?.cancel();
    _packetReceivedSub?.cancel();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
    if (!_packetController.isClosed) {
      _packetController.close();
    }
  }
}
