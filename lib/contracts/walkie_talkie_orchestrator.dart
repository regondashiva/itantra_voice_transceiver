import 'dart:async';
import 'transceiver_packet.dart';


enum OrchestratorState {
  idle,
  listening,
  vadTriggered,
  transcribing,
  broadcasting,
  packetSent,
  packetReceived,
  speaking,
  error,
}

/// Module 5: WalkieTalkieOrchestrator
/// Responsibility: Bind the transport, VAD, STT, and TTS modules together into the transceiver loop.
abstract class WalkieTalkieOrchestratorContract {
  /// Current orchestrator state
  OrchestratorState get state;

  /// Stream of orchestrator state updates
  Stream<OrchestratorState> get stateStream;

  /// Stream of outgoing/incoming decoded packets
  Stream<TransceiverPacket> get packetStream;

  /// Latency metric of the last STT transcription in milliseconds (SIH Metric)
  int get lastSttLatencyMs;

  /// Initializes the orchestrator and sub-modules
  Future<void> initialize({String languageCode = 'en'});

  /// Step 1: Push-To-Talk (PTT) pressed - triggers VAD listening
  Future<void> onPttPressed();

  /// Step 3: Push-To-Talk released or manual stop - triggers speech end processing
  Future<void> onPttReleased();

  /// Transmit a custom or emergency packet directly
  Future<void> sendCustomPacket({
    required String text,
    PacketPriority priority = PacketPriority.normal,
    String intent = 'TALK',
  });

  /// Dispose all listeners and streams
  void dispose();
}
