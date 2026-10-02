import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_voice_transceiver/core/theme/app_theme.dart';
import 'package:itantra_voice_transceiver/models/connection_model.dart';
import 'package:itantra_voice_transceiver/models/device_model.dart';
import 'package:itantra_voice_transceiver/models/message_model.dart';
import 'package:itantra_voice_transceiver/widgets/connection_card.dart';
import 'package:itantra_voice_transceiver/widgets/emergency_button.dart';
import 'package:itantra_voice_transceiver/widgets/message_card.dart';
import 'package:itantra_voice_transceiver/widgets/push_to_talk_button.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('PushToTalkButton renders idle state and triggers callbacks', (tester) async {
    bool holdStarted = false;
    bool holdEnded = false;

    await tester.pumpWidget(
      createTestWidget(
        PushToTalkButton(
          state: CommunicationState.idle,
          onHoldStart: () => holdStarted = true,
          onHoldEnd: () => holdEnded = true,
        ),
      ),
    );

    expect(find.text('HOLD TO SPEAK'), findsOneWidget);
    expect(find.text('Hold to record'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PushToTalkButton)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(holdStarted, isTrue);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(holdEnded, isTrue);
  });


  testWidgets('EmergencyButton renders and triggers confirmation', (tester) async {
    bool triggered = false;

    await tester.pumpWidget(
      createTestWidget(
        EmergencyButton(
          label: 'HOLD FOR EMERGENCY',
          onTrigger: () => triggered = true,
        ),
      ),
    );

    expect(find.text('HOLD FOR EMERGENCY'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(EmergencyButton)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(triggered, isTrue);
  });

  testWidgets('ConnectionCard displays connected peer info', (tester) async {
    const device = DeviceModel(
      id: 'dev-1',
      name: 'iTantra-Rescue-01',
      connectionType: ConnectionType.wifiDirect,
      signalStrength: 0.95,
      isConnected: true,
    );

    await tester.pumpWidget(
      createTestWidget(
        const ConnectionCard(
          status: ConnectionStatus.connected,
          device: device,
        ),
      ),
    );

    expect(find.text('Connected to'), findsOneWidget);
    expect(find.text('iTantra-Rescue-01'), findsOneWidget);
    expect(find.text('Wi-Fi Direct'), findsOneWidget);
  });

  testWidgets('MessageCard displays text, sender, and status', (tester) async {
    final msg = MessageModel(
      id: 'm-1',
      text: 'Send the location to the rescue team.',
      sender: 'You',
      receiver: 'iTantra-Rescue-01',
      timestamp: DateTime.now(),
      language: 'English → Telugu',
      status: MessageStatus.delivered,
    );

    await tester.pumpWidget(
      createTestWidget(
        MessageCard(message: msg),
      ),
    );

    expect(find.text('"Send the location to the rescue team."'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
  });
}
