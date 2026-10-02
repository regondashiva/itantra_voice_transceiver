import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_voice_transceiver/core/theme/app_theme.dart';
import 'package:itantra_voice_transceiver/screens/communication/communication_screen.dart';
import 'package:itantra_voice_transceiver/screens/connection/connection_screen.dart';
import 'package:itantra_voice_transceiver/screens/emergency/emergency_screen.dart';
import 'package:itantra_voice_transceiver/screens/history/history_screen.dart';
import 'package:itantra_voice_transceiver/screens/home/home_screen.dart';
import 'package:itantra_voice_transceiver/screens/secondary/about/about_screen.dart';
import 'package:itantra_voice_transceiver/screens/secondary/ai_info/ai_info_screen.dart';
import 'package:itantra_voice_transceiver/screens/secondary/diagnostics/diagnostics_screen.dart';
import 'package:itantra_voice_transceiver/screens/secondary/languages/language_screen.dart';
import 'package:itantra_voice_transceiver/screens/settings/settings_screen.dart';
import 'package:itantra_voice_transceiver/screens/setup/setup_screen.dart';
import 'package:itantra_voice_transceiver/screens/splash/splash_screen.dart';

void main() {
  Widget buildTestScreen(Widget screen, {Size size = const Size(360, 640)}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(1.15), // Test with 1.15x font scaling
          ),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: screen,
          ),
        ),
      ),
    );
  }

  group('Screen Overflow & Visibility Verification on Small Displays', () {
    testWidgets('HomeScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CommunicationScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const CommunicationScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CommunicationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmergencyScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('HOLD FOR EMERGENCY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ConnectionScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const ConnectionScreen()));
      // Allow the 600ms mock scan timer to finish
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Connect Device'), findsOneWidget);
      expect(find.text('Wi-Fi Direct'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HistoryScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const HistoryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('EMERGENCY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SetupScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const SetupScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Set up your communication'), findsOneWidget);
      expect(find.text('Walkie-Talkie'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LanguageScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const LanguageScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Communication Languages'), findsOneWidget);
      expect(find.text('YOUR LANGUAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AiInfoScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const AiInfoScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('On-Device AI Engine'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });


    testWidgets('DiagnosticsScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const DiagnosticsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Connection Diagnostics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AboutScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const AboutScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('About iTantra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SplashScreen renders without overflow on 360x640 with font scaling', (tester) async {
      await tester.pumpWidget(buildTestScreen(const SplashScreen()));
      // Allow the 2200ms splash nav timer to elapse
      await tester.pump(const Duration(milliseconds: 2300));
      expect(find.text('iTantra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
