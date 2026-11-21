import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/account_settings_page.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets(
    'account settings control saved battle effects on a narrow screen',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final growth = GrowthStore(SharedPreferencesAsync());
      final game = GameStore(SharedPreferencesAsync());
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSettingsPage(store: growth, gameStore: game),
        ),
      );
      await tester.ensureVisible(find.text('전투 효과 줄이기'));
      await tester.tap(find.text('전투 효과 줄이기'));
      await tester.pump();
      expect(game.reduceBattleEffects, isTrue);
      await tester.ensureVisible(find.text('전투 진동'));
      await tester.tap(find.text('전투 진동'));
      await tester.pump();
      expect(game.battleHaptics, isTrue);
      expect(tester.takeException(), isNull);
      final restored = GameStore(SharedPreferencesAsync());
      await restored.load();
      expect(restored.reduceBattleEffects, isTrue);
      expect(restored.battleHaptics, isTrue);
    debugDefaultTargetPlatformOverride = null;
    },
  );
}
