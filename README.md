# iTantra — Voice Transceiver

> **ISRO PSID SIH26173: Smart Automation Software Hackathon**  
> *Indian Multilingual TTS & STT Aided Neural Transceiver Radio Access for Low-Bitrate Links*

---

## 🛰️ 1. Overview

Voice and audio communications require significant bandwidth (16–64 kbps), making direct audio streaming unreliable or impossible over constrained tactical channels, disaster zones, or deep-space links.

**iTantra** revolutionizes voice transmission by exchanging **compact text payloads & binary Protobuf packets (<80 bytes)** instead of raw audio streams, running entirely **on-device without cloud dependencies**:

```
[ Sender Handset ]                                                 [ Receiver Handset ]
┌───────────────┐     ┌──────────────┐     ┌──────────────┐       ┌─────────────────┐
│ Speech Input  │ ──> │ On-Device    │ ──> │ Protobuf     │ ───>  │ Low-Bitrate     │
│ (Mic / PTT)   │     │ Vosk STT     │     │ Binary (<80B)│ (P2P) │ Mesh / Radio    │
└───────────────┘     └──────────────┘     └──────────────┘       └────────┬────────┘
                                                                           │
                                                                           ▼
                                                                  ┌─────────────────┐
                                                                  │ On-Device Piper │
                                                                  │ ONNX Neural TTS │
                                                                  └────────┬────────┘
                                                                           │
                                                                           ▼
                                                                  ┌─────────────────┐
                                                                  │ Spoken Audio    │
                                                                  │ (Speaker Output)│
                                                                  └─────────────────┘
```

---

## 🌐 2. Supported Languages (10 Indian Languages)

iTantra natively supports 10 official Indian languages with localized translation and on-device neural voice models:

| Language | Native Script | Code | Language | Native Script | Code |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **English** | English | `en` | **Telugu** | తెలుగు | `te` |
| **Hindi** | हिन्दी | `hi` | **Tamil** | தமிழ் | `ta` |
| **Kannada** | ಕನ್ನಡ | `kn` | **Malayalam** | മലയാളം | `ml` |
| **Marathi** | मराठी | `mr` | **Gujarati** | ગુજરાતી | `gu` |
| **Bengali** | বাংলা | `bn` | **Odia** | ଓଡ଼ିଆ | `or` |

---

## 🧩 3. Core Architecture & Frontend Feature Contracts

Each core transceiver module is isolated behind strict Dart contracts (`lib/contracts/`):

### Module 1: `ITantraTransport` (P2P Mesh Network)
- **Responsibility:** Offline peer-to-peer radio link over Wi-Fi Direct, Bluetooth LE, and local UDP broadcast mesh without cellular or internet data.
- **Payload Protocol:** Compact binary Protobuf packets (`TransceiverPacket`, `<80 bytes`) with tag-based varint encoding.
- **Contract:** `lib/contracts/itantra_transport.dart`
- **Implementation:** `lib/services/communication/p2p_mesh_transport_service.dart`

### Module 2: `ITantraVAD` (Voice Activity Detection)
- **Responsibility:** Low-power (<5% CPU) microphone monitoring with 16kHz PCM audio frame energy & zero-crossing rate analysis.
- **Silence Trigger:** Automatically triggers `onSpeechEnded` after **500ms of trailing silence** to delimit sentences.
- **Contract:** `lib/contracts/itantra_vad.dart`
- **Implementation:** `lib/services/vad/silero_vad_service.dart`

### Module 3: `ITantraSTT` (Speech-to-Text)
- **Responsibility:** Converts 16-bit PCM voice buffers into transcribed text locally using cached Vosk models.
- **Latency Tracking:** Measures and logs execution latency for SIH evaluation metrics (`[SIH Metrics] Vosk STT Latency: Xms`).
- **Contract:** `lib/contracts/itantra_stt.dart`
- **Implementation:** `lib/services/stt/vosk_stt_service.dart`

### Module 4: `ITantraTTS` (Text-to-Speech)
- **Responsibility:** Converts incoming text back into spoken audio using on-device ONNX Piper neural speech.
- **Emergency Priority Override:** Uses Android `AudioManager.STREAM_ALARM` equivalent volume override (max audio stream & non-interruptible lock) for critical SOS broadcasts.
- **Contract:** `lib/contracts/itantra_tts.dart`
- **Implementation:** `lib/services/tts/piper_tts_service.dart`

### Module 5: `WalkieTalkieOrchestrator`
- **Responsibility:** Binds Transport, VAD, STT, and TTS into the full walkie-talkie transceiver loop:
  1. **PTT Pressed** $\rightarrow$ `ITantraVAD.startListening()`
  2. **User Speaks** $\rightarrow$ Audio buffer piped to memory
  3. **User Pauses (500ms silence) / PTT Released** $\rightarrow$ `onSpeechEnded`
  4. **STT Inference** $\rightarrow$ `ITantraSTT.transcribe()` processes buffer into text
  5. **Protobuf Creation** $\rightarrow$ `TransceiverPacket` encoded ($<80$ bytes)
  6. **Broadcast** $\rightarrow$ `ITantraTransport.sendPacket()` transmits over local link
  7. **Receiver Event** $\rightarrow$ `ITantraTransport.onPacketReceived` fires
  8. **Packet Decode** $\rightarrow$ Decodes Protobuf text & priority
  9. **Voice Playback** $\rightarrow$ `ITantraTTS.speak()` plays synthesized audio
- **Contract:** `lib/contracts/walkie_talkie_orchestrator.dart`
- **Implementation:** `lib/services/orchestrator/walkie_talkie_orchestrator.dart`

---

## 📡 4. Hybrid C2 Backend & API Integration

When internet or base-station connectivity is available, iTantra synchronizes with the central Command & Control (C2) portal:

| Endpoint | Method | Purpose |
| :--- | :--- | :--- |
| `/api/v1/auth/device-register` | `POST` | Registers hardware device ID, callsign, and specs fingerprint |
| `/api/v1/auth/token` | `POST` | Obtains signed JWT session token for authenticated requests |
| `/api/v1/transmissions/sync` | `POST` | Flushes offline-queued transmissions and SOS incident packets |
| `/api/v1/models` | `GET` | OTA AI Model Hub manifest for downloading on-device models |
| `/api/v1/channels` | `GET` | Discovers active tactical radio channels |
| `/api/v1/incidents/active` | `GET` | Real-time C2 emergency incident monitoring |
| `ws://<HOST>:3000/v1/transceiver/channel` | `WS` | Low-latency binary Protobuf streaming gateway |

---

## 📁 5. Project Directory Structure

```
lib/
├── contracts/                  # Feature contracts & interfaces
│   ├── contracts.dart          # Barrel export
│   ├── itantra_transport.dart  # Module 1 Contract
│   ├── itantra_vad.dart        # Module 2 Contract
│   ├── itantra_stt.dart        # Module 3 Contract
│   ├── itantra_tts.dart        # Module 4 Contract
│   ├── peer_device.dart        # P2P Peer Model
│   ├── transceiver_packet.dart # Protobuf Binary Serializer (<80B)
│   └── walkie_talkie_orchestrator.dart # Module 5 Contract
├── core/
│   ├── config/                 # API & Gateway configurations
│   ├── constants/              # Application constants & language maps
│   ├── theme/                  # Dark tactical theme tokens
│   └── utils/                  # Formatting & location utilities
├── models/                     # Channel, Device, Incident, Message models
├── providers/                  # StateNotifier & Riverpod providers
├── repositories/               # Message & Device discovery repositories
├── routes/                     # GoRouter application navigation
├── screens/                    # UI screens (Home, PTT, Emergency, etc.)
├── services/                   # Concrete service implementations
│   ├── api/                    # C2 REST client
│   ├── communication/          # P2P Mesh & Backend transport
│   ├── orchestrator/           # WalkieTalkieOrchestrator
│   ├── stt/                    # Vosk & platform STT services
│   ├── tts/                    # Piper ONNX & platform TTS services
│   ├── vad/                    # Silero TinyML VAD service
│   └── websocket/              # Protobuf WebSocket gateway client
└── widgets/                    # Modular tactical UI components
```

---

## 🚀 6. Getting Started

### Prerequisites
- **Flutter SDK:** `^3.13.0` or newer
- **Dart SDK:** `^3.13.2`
- **Android SDK:** API Level 26+ (Android 8.0+)
- **Microphone & Location Permissions:** Enabled for P2P radio discovery and voice capture.

### Setup & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/regondashiva/itantra_voice_transceiver.git
   cd itantra
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on connected Android device / emulator:**
   ```bash
   flutter run
   ```

### Running Tests
Execute the complete test suite (unit, feature contracts, widget, screen overflow):
```bash
flutter test
```

---

## 🛡️ 7. Emergency Protocol & Failsafe
- **Tactical SOS Trigger:** Holding the Emergency button triggers an un-cancellable high-priority broadcast with geographic coordinates.
- **Volume Override:** Emergency audio overrides system mute / DND using high-priority audio streams.
- **Offline Reliability:** If radio links or internet drop, all transmissions buffer into local offline memory and auto-sync when a peer or network is re-acquired.

---

## 📄 License
Developed for the **Indian Space Research Organisation (ISRO)** Smart India Hackathon (SIH26173).
