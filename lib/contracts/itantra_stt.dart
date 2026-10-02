import 'dart:typed_data';

/// Module 3: iTantraSTT (Speech-to-Text)
/// Responsibility: Convert raw audio chunks into text locally.
abstract class ITantraSTT {
  /// Loads the lightweight Vosk model from local storage
  Future<void> loadModel(String languageCode);
  
  /// Processes a complete audio chunk and returns the transcribed text
  Future<String> transcribe(Uint8List audioPcm16Data);
}
