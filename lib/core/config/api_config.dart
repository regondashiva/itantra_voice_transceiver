enum BackendEnvironment {
  production,
  emulator,
  lan,
  fieldEdge,
  customDomain,
}

/// Centralized configuration for iTantra Backend APIs & Real-Time Gateway.
/// Implements BACKEND_API_INTEGRATION_GUIDE_ITantra specifications.
class ApiConfig {
  ApiConfig._();

  static BackendEnvironment currentEnvironment = BackendEnvironment.production;

  // Active callsign representing this handset node
  static String callsign = 'ALPHA-1';

  // Device hardware identifier
  static String deviceId = 'hardware-uuid-1234';

  // Device specs fingerprint
  static String deviceFingerprint = 'sha256-itantra-node-hardware-specs';

  // C2 Authentication JWT token
  static String bearerToken = '';

  // Expiration ISO timestamp
  static DateTime? tokenExpiresAt;

  // Currently active channel ID (defaulting to Command Net)
  static String activeChannelId = 'chan-cmd';

  // Local workstation LAN IP when testing on physical handset
  static String lanHostIp = '192.168.1.100';

  // Custom host and port
  static String customHost = '192.168.1.100';
  static int customPort = 3000;

  static BackendEnvironment get environment => currentEnvironment;
  static set environment(BackendEnvironment env) => currentEnvironment = env;

  static bool get isAuthenticated =>
      bearerToken.isNotEmpty && (tokenExpiresAt == null || tokenExpiresAt!.isAfter(DateTime.now()));

  /// REST Base URLs according to BACKEND_API_INTEGRATION_GUIDE_ITantra
  static String get baseUrl {
    switch (currentEnvironment) {
      case BackendEnvironment.production:
        return 'https://itantra-backend-bwoq.onrender.com';
      case BackendEnvironment.emulator:
        return 'http://10.0.2.2:3000';
      case BackendEnvironment.lan:
        return 'http://$lanHostIp:3000';
      case BackendEnvironment.fieldEdge:
        return 'http://192.168.10.1:3000';
      case BackendEnvironment.customDomain:
        return 'http://$customHost:$customPort';
    }
  }

  /// WebSocket URLs according to BACKEND_API_INTEGRATION_GUIDE_ITantra
  static String get wsUrl {
    switch (currentEnvironment) {
      case BackendEnvironment.production:
        return 'wss://itantra-backend-bwoq.onrender.com/v1/transceiver/channel';
      case BackendEnvironment.emulator:
        return 'ws://10.0.2.2:3000/v1/transceiver/channel';
      case BackendEnvironment.lan:
        return 'ws://$lanHostIp:3000/v1/transceiver/channel';
      case BackendEnvironment.fieldEdge:
        return 'ws://192.168.10.1:3000/v1/transceiver/channel';
      case BackendEnvironment.customDomain:
        return 'ws://$customHost:$customPort/v1/transceiver/channel';
    }
  }

  static Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        'x-transceiver-callsign': callsign,
        if (bearerToken.isNotEmpty) 'Authorization': 'Bearer $bearerToken',
      };
}
