import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_tts/flutter_tts.dart';
import 'tts_service.dart';

/// Real on-device Text-to-Speech service using native neural voice synthesizer.
class DeviceTtsService implements TtsService {
  FlutterTts? _flutterTts;
  final _speakingController = StreamController<bool>.broadcast();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  DeviceTtsService() {
    _init();
  }

  void _init() {
    if (_isInitialized) return;
    try {
      _flutterTts = FlutterTts();
      _flutterTts?.setStartHandler(() {
        _isSpeaking = true;
        if (!_speakingController.isClosed) _speakingController.add(true);
      });

      _flutterTts?.setCompletionHandler(() {
        _isSpeaking = false;
        if (!_speakingController.isClosed) _speakingController.add(false);
      });

      _flutterTts?.setCancelHandler(() {
        _isSpeaking = false;
        if (!_speakingController.isClosed) _speakingController.add(false);
      });

      _flutterTts?.setErrorHandler((msg) {
        dev.log('[DeviceTtsService] Error: $msg');
        _isSpeaking = false;
        if (!_speakingController.isClosed) _speakingController.add(false);
      });
      _isInitialized = true;
    } catch (e) {
      dev.log('[DeviceTtsService] Init fallback: $e');
    }
  }

  String _mapLocale(String languageCode) {
    switch (languageCode) {
      case 'hi':
        return 'hi-IN';
      case 'te':
        return 'te-IN';
      case 'ta':
        return 'ta-IN';
      case 'kn':
        return 'kn-IN';
      case 'ml':
        return 'ml-IN';
      case 'mr':
        return 'mr-IN';
      case 'gu':
        return 'gu-IN';
      case 'bn':
        return 'bn-IN';
      case 'or':
        return 'or-IN';
      case 'en':
      default:
        return 'en-IN';
    }
  }

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get isSpeakingStream => _speakingController.stream;

  @override
  Future<void> speak(String text, {required String languageCode}) async {
    if (text.trim().isEmpty) return;
    _init();
    try {
      final locale = _mapLocale(languageCode);
      await _flutterTts?.setLanguage(locale);
      await _flutterTts?.setPitch(1.0);
      await _flutterTts?.setSpeechRate(0.48); // Natural conversational cadence
      await _flutterTts?.setVolume(1.0);

      _isSpeaking = true;
      if (!_speakingController.isClosed) _speakingController.add(true);
      await _flutterTts?.speak(text);
    } catch (e) {
      dev.log('[DeviceTtsService] Speak simulation: $e');
      _isSpeaking = true;
      if (!_speakingController.isClosed) _speakingController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));
      _isSpeaking = false;
      if (!_speakingController.isClosed) _speakingController.add(false);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts?.stop();
      _isSpeaking = false;
      if (!_speakingController.isClosed) _speakingController.add(false);
    } catch (e) {
      dev.log('[DeviceTtsService] Stop error: $e');
    }
  }

  void dispose() {
    _speakingController.close();
  }
}
