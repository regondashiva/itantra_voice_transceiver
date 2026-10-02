import 'dart:async';
import '../models/message_model.dart';

enum MessageFilter {
  all,
  sent,
  received,
  emergency,
}

/// Dynamic repository managing communication history for iTantra.
class MessageRepository {
  final _messages = <MessageModel>[];
  final _streamController = StreamController<List<MessageModel>>.broadcast();

  MessageRepository() {
    _initDefaultSeed();
  }

  void _initDefaultSeed() {
    final now = DateTime.now();
    _messages.addAll([
      MessageModel(
        id: 'seed-1',
        text: 'Radio check from Squad Alpha. Channel clear.',
        sender: 'ALPHA_01',
        receiver: 'You',
        timestamp: now.subtract(const Duration(minutes: 5)),
        language: 'English → English',
        status: MessageStatus.delivered,
        isEmergency: false,
      ),
      MessageModel(
        id: 'seed-2',
        text: 'Copy that Alpha. Advancing to sector 3.',
        sender: 'You',
        receiver: 'ALPHA_01',
        timestamp: now.subtract(const Duration(minutes: 3)),
        language: 'English → English',
        status: MessageStatus.delivered,
        isEmergency: false,
      ),
      MessageModel(
        id: 'seed-3',
        text: 'EMERGENCY: Tree fall blocking perimeter road.',
        sender: 'PATROL_02',
        receiver: 'ALL',
        timestamp: now.subtract(const Duration(minutes: 1)),
        language: 'Hindi → English',
        status: MessageStatus.delivered,
        isEmergency: true,
      ),
    ]);
  }

  /// Loads real history fetched from the backend C2 gateway
  void setRemoteHistory(List<MessageModel> remoteMessages) {
    _messages.clear();
    _messages.addAll(remoteMessages);
    _emit();
  }

  List<MessageModel> getAll() => List.unmodifiable(_messages);

  List<MessageModel> getFiltered(MessageFilter filter) {
    switch (filter) {
      case MessageFilter.all:
        return getAll();
      case MessageFilter.sent:
        return _messages.where((m) => m.isSentByMe).toList();
      case MessageFilter.received:
        return _messages.where((m) => !m.isSentByMe).toList();
      case MessageFilter.emergency:
        return _messages.where((m) => m.isEmergency).toList();
    }
  }

  Stream<List<MessageModel>> watchMessages() => _streamController.stream;

  MessageModel? get latestMessage => _messages.isNotEmpty ? _messages.first : null;

  void addMessage(MessageModel message) {
    _messages.insert(0, message);
    _emit();
  }

  void updateStatus(String id, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: status);
      _emit();
    }
  }

  void _emit() {
    _streamController.add(List.unmodifiable(_messages));
  }

  void dispose() {
    _streamController.close();
  }
}
