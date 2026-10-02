import 'dart:typed_data';

/// Module 2: iTantraVAD (Voice Activity Detection)
/// Responsibility: Monitor microphone efficiently, trigger recording only when speech is present.
abstract class ITantraVAD {
  /// Start idle listening (must consume <5% CPU)
  Future<void> startListening();
  
  /// Stop listening and release microphone
  Future<void> stopListening();
  
  /// Emits a continuous audio buffer (16kHz PCM) only when a human is speaking
  Stream<Uint8List> get onSpeechDetected;
  
  /// Fires when 500ms of silence is detected, signaling end of sentence
  Stream<void> get onSpeechEnded;
}
