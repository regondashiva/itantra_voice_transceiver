import 'dart:typed_data';
import 'peer_device.dart';

/// Module 1: iTantraTransport (P2P Mesh Network)
/// Responsibility: Handle fully offline device-to-device communication without internet routing.
abstract class ITantraTransport {
  /// Initializes Wi-Fi Direct (Aware) or Bluetooth LE
  Future<void> initialize();
  
  /// Discovers nearby devices running the iTantra app
  Stream<List<PeerDevice>> discoverPeers();
  
  /// Connects to a specific peer or mesh group
  Future<bool> connect(String peerId);
  
  /// Sends a binary Protobuf packet (<80 bytes) over the local link
  Future<void> sendPacket(Uint8List protobufData);
  
  /// Stream of incoming raw Protobuf binary packets
  Stream<Uint8List> get onPacketReceived;
}
