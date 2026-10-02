// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../../contracts/transceiver_packet.dart';
import '../../core/config/api_config.dart';
import '../../models/channel_model.dart';
import '../../models/device_model.dart';
import '../../models/incident_model.dart';
import '../../models/message_model.dart';
import '../location/location_service.dart';

/// Real REST API client for iTantra C2 Backend Gateway.
/// Implements BACKEND_API_INTEGRATION_GUIDE_ITantra specifications.
class ApiService {
  final http.Client _client;
  final LocationService? _locationService;

  ApiService({http.Client? client, LocationService? locationService})
      : _client = client ?? http.Client(),
        _locationService = locationService;

  /// GET /api/healthz - Check backend availability
  Future<bool> checkHealth() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/healthz');
      final res = await _client.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['status'] == 'HEALTHY' || data['status'] == 'OK' || data['healthy'] == true;
      }
      return false;
    } catch (e) {
      dev.log('[ApiService] Health check error: $e');
      return false;
    }
  }

  // ==========================================
  // 2. AUTHENTICATION FLOW
  // ==========================================

  /// Step 1: POST /api/v1/auth/device-register
  /// Registers device hardware specs and callsign on the central C2 gateway.
  Future<bool> registerDevice({
    String? callsign,
    String? deviceId,
    String? fingerprint,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/device-register');
      final payload = {
        'callsign': callsign ?? ApiConfig.callsign,
        'deviceId': deviceId ?? ApiConfig.deviceId,
        'deviceFingerprint': fingerprint ?? ApiConfig.deviceFingerprint,
      };

      final res = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      dev.log('[ApiService] Device register status: ${res.statusCode}');
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      dev.log('[ApiService] registerDevice error: $e');
      return false;
    }
  }

  /// Step 2: POST /api/v1/auth/token
  /// Obtains and caches a signed JWT token for all authenticated C2 REST calls.
  Future<String?> obtainAuthToken({
    String? callsign,
    String? deviceId,
    String? fingerprint,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/token');
      final payload = {
        'callsign': callsign ?? ApiConfig.callsign,
        'deviceId': deviceId ?? ApiConfig.deviceId,
        'deviceFingerprint': fingerprint ?? ApiConfig.deviceFingerprint,
      };

      final res = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        final expiresAtStr = data['expiresAt'] as String?;

        if (token != null && token.isNotEmpty) {
          ApiConfig.bearerToken = token;
          if (expiresAtStr != null) {
            ApiConfig.tokenExpiresAt = DateTime.tryParse(expiresAtStr);
          }
          dev.log('[ApiService] Obtained new C2 Auth Token (expires: $expiresAtStr)');
          return token;
        }
      }
      return null;
    } catch (e) {
      dev.log('[ApiService] obtainAuthToken error: $e');
      return null;
    }
  }

  /// Ensures a valid auth token is available before calling authenticated C2 routes
  Future<void> ensureAuthenticated() async {
    if (!ApiConfig.isAuthenticated) {
      await registerDevice();
      await obtainAuthToken();
    }
  }

  // ==========================================
  // 3. OFFLINE BACKLOG SYNCHRONIZATION
  // ==========================================

  /// POST /api/v1/transmissions/sync
  /// Flushes all offline-captured transmissions and emergency SOS packets to C2.
  Future<bool> syncOfflineBacklog(List<dynamic> packets) async {
    if (packets.isEmpty) return true;
    try {
      await ensureAuthenticated();
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/transmissions/sync');

      final packetList = packets.map((p) {
        if (p is TransceiverPacket) {
          return {
            'packetId': p.packetId,
            'senderCallsign': p.senderId,
            'channelId': ApiConfig.activeChannelId,
            'compactTextPayload': p.text,
            'priority': p.isEmergency ? 'PRIORITY_EMERGENCY_SOS' : 'PRIORITY_ROUTINE',
            'transportUsed': 'TRANSPORT_WIFI_DIRECT',
            'timestampEpochMs': p.timestampMs,
          };
        } else if (p is MessageModel) {
          return {
            'packetId': p.id,
            'senderCallsign': p.sender == 'You' ? ApiConfig.callsign : p.sender,
            'channelId': ApiConfig.activeChannelId,
            'compactTextPayload': p.text,
            'priority': p.isEmergency ? 'PRIORITY_EMERGENCY_SOS' : 'PRIORITY_ROUTINE',
            'transportUsed': p.connectionType == ConnectionType.bluetooth
                ? 'TRANSPORT_BLUETOOTH_LE'
                : 'TRANSPORT_WIFI_DIRECT',
            'timestampEpochMs': p.timestamp.millisecondsSinceEpoch,
          };
        } else if (p is Map<String, dynamic>) {
          return p;
        }
        return <String, dynamic>{};
      }).where((m) => m.isNotEmpty).toList();

      final payload = {
        'packets': packetList,
      };

      final res = await _client
          .post(
            url,
            headers: ApiConfig.authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      dev.log('[ApiService] Sync offline backlog status: ${res.statusCode} (${packetList.length} packets synced)');
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      dev.log('[ApiService] syncOfflineBacklog error: $e');
      return false;
    }
  }

  /// Compatibility helper for syncing message backlog
  Future<bool> syncBatchPackets(List<MessageModel> packets) => syncOfflineBacklog(packets);

  /// Compatibility helper for single ingest packet
  Future<bool> sendIngestPacket(MessageModel message) => syncOfflineBacklog([message]);


  // ==========================================
  // 4. OTA AI MODEL HUB
  // ==========================================

  /// GET /api/v1/models
  /// Fetches the manifest of downloadable on-device AI models (Vosk, Piper, Whisper).
  Future<List<Map<String, dynamic>>> fetchModelManifest() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/models');
      final res = await _client.get(url, headers: ApiConfig.authHeaders).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['models'] is List) {
          return List<Map<String, dynamic>>.from(data['models'] as List);
        } else if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return _fallbackModelManifest();
    } catch (e) {
      dev.log('[ApiService] fetchModelManifest error (using fallback): $e');
      return _fallbackModelManifest();
    }
  }

  List<Map<String, dynamic>> _fallbackModelManifest() {
    return [
      {
        'id': 'vosk-model-small-in-0.4',
        'type': 'STT',
        'language': 'hi/en/te',
        'downloadUrl': 'https://cdn.itantra.org/models/vosk-small-in.zip',
        'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'sizeMb': 42.5,
      },
      {
        'id': 'piper-onnx-indic-neural-v1',
        'type': 'TTS',
        'language': 'hi/te/ta/en',
        'downloadUrl': 'https://cdn.itantra.org/models/piper-indic-neural.onnx',
        'sha256': 'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0',
        'sizeMb': 38.2,
      },
    ];
  }

  // ==========================================
  // 5. OPERATIONAL C2 CHANNELS & INCIDENTS
  // ==========================================

  /// GET /api/v1/channels - Retrieve tactical radio channels
  Future<List<ChannelModel>> fetchChannels() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/channels');
      final res = await _client.get(url, headers: ApiConfig.authHeaders).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['channels'] is List) {
          return (data['channels'] as List)
              .map((c) => ChannelModel.fromJson(c as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      dev.log('[ApiService] fetchChannels error: $e');
      return [];
    }
  }

  /// GET /api/v1/channels/{channelId}/messages - Paginated message history
  Future<List<MessageModel>> fetchChannelMessages(
    String channelId, {
    int? since,
    int limit = 50,
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        if (since != null) 'since': since.toString(),
      };
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/channels/$channelId/messages')
          .replace(queryParameters: queryParams);

      final res = await _client.get(uri, headers: ApiConfig.authHeaders).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['messages'] is List) {
          final rawList = data['messages'] as List;
          return rawList.map((m) {
            final map = m as Map<String, dynamic>;
            final sender = map['senderCallsign'] as String? ?? 'REMOTE';
            final text = map['compactTextPayload'] as String? ?? '';
            final isEmergency = map['priority'] == 'PRIORITY_EMERGENCY_SOS';
            final packetId = map['packetId'] as String? ?? '';
            final transportStr = map['transportUsed'] as String? ?? 'TRANSPORT_WIFI_DIRECT';

            return MessageModel(
              id: packetId.isNotEmpty ? packetId : DateTime.now().microsecondsSinceEpoch.toString(),
              text: text,
              sender: sender == ApiConfig.callsign ? 'You' : sender,
              receiver: map['recipientCallsign'] as String? ?? 'All',
              timestamp: DateTime.now(),
              language: 'Tactical Mesh',
              status: MessageStatus.delivered,
              isEmergency: isEmergency,
              connectionType: transportStr.contains('BLUETOOTH')
                  ? ConnectionType.bluetooth
                  : ConnectionType.wifiDirect,
            );
          }).toList();
        }
      }
      return [];
    } catch (e) {
      dev.log('[ApiService] fetchChannelMessages error: $e');
      return [];
    }
  }

  /// GET /api/v1/incidents/active - Query active emergency SOS incidents
  Future<List<ActiveIncidentModel>> fetchActiveIncidents() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/incidents/active');
      final res = await _client.get(url, headers: ApiConfig.authHeaders).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['incidents'] is List) {
          return (data['incidents'] as List)
              .map((i) => ActiveIncidentModel.fromJson(i as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      dev.log('[ApiService] fetchActiveIncidents error: $e');
      return [];
    }
  }

  /// POST /api/v1/sos - Emergency SOS transmission
  Future<bool> sendSos(MessageModel message) async {
    try {
      await ensureAuthenticated();
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/sos');
      final payload = {
        'packetId': message.id,
        'senderCallsign': ApiConfig.callsign,
        'recipientCallsign': 'BROADCAST_ALL',
        'channelId': ApiConfig.activeChannelId,
        'compactTextPayload': message.text,
        'priority': 'PRIORITY_EMERGENCY_SOS',
        'transportUsed': message.connectionType == ConnectionType.bluetooth
            ? 'TRANSPORT_BLUETOOTH_LE'
            : 'TRANSPORT_WIFI_DIRECT',
        'latitude': _locationService?.latitude ?? 17.3850,
        'longitude': _locationService?.longitude ?? 78.4867,
      };

      final res = await _client
          .post(
            url,
            headers: ApiConfig.authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      dev.log('[ApiService] sendSos error: $e');
      return false;
    }
  }

  /// POST /api/v1/telemetry - Report device battery & radio health
  Future<bool> sendTelemetry({
    required double batteryPercent,
    required double signalStrengthDbm,
    String transportType = 'TRANSPORT_WIFI_DIRECT',
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/telemetry');
      final payload = {
        'callsign': ApiConfig.callsign,
        'batteryPercent': batteryPercent,
        'signalStrengthDbm': signalStrengthDbm,
        'transportType': transportType,
        'latitude': _locationService?.latitude ?? 17.3850,
        'longitude': _locationService?.longitude ?? 78.4867,
        'nodeTemperatureC': 36.5,
      };

      final res = await _client
          .post(
            url,
            headers: ApiConfig.authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));

      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      dev.log('[ApiService] sendTelemetry error: $e');
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
