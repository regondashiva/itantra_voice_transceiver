/// Module 4: iTantraTTS (Text-to-Speech)
/// Responsibility: Convert received text back into spoken audio.
abstract class ITantraTTS {
  /// Loads the ONNX Piper TTS model for the specified language
  Future<void> loadModel(String languageCode);
  
  /// Synthesizes and plays audio. If [isEmergency] is true, overrides system volume.
  Future<void> speak(String text, {bool isEmergency = false});
}
