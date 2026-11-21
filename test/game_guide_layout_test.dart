import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/game_guide_page.dart';

void main() {
  testWidgets('game guide fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(const MaterialApp(home: GameGuidePage()));
    expect(find.text('보상·기록 규칙'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('보상·기록 규칙'));
    await tester.pumpAndSettle();
    expect(find.textContaining('훈련에서 새 신수나 조각은 나오지 않습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
