enum PeerTransportType {
  wifiDirect,
  bluetoothLe,
  mesh,
}

/// Representation of a discovered peer running iTantra P2P Mesh
class PeerDevice {
  final String id;
  final String name;
  final int rssi; // Signal strength in dBm (e.g. -45 dBm)
  final PeerTransportType transportType;
  final bool isConnected;
  final DateTime lastSeen;

  const PeerDevice({
    required this.id,
    required this.name,
    this.rssi = -60,
    this.transportType = PeerTransportType.wifiDirect,
    this.isConnected = false,
    required this.lastSeen,
  });

  double get signalQuality {
    // Convert RSSI (-100 to -40 dBm) to 0.0 - 1.0
    if (rssi >= -50) return 1.0;
    if (rssi <= -100) return 0.0;
    return (rssi + 100) / 50.0;
  }

  PeerDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    PeerTransportType? transportType,
    bool? isConnected,
    DateTime? lastSeen,
  }) {
    return PeerDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      transportType: transportType ?? this.transportType,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
