import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/app_date_picker.dart';

void main() {
  testWidgets('calendar respects date bounds on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async => result = await showAppDatePicker(
                    context: context,
                    title: '목표 종료일',
                    initialDate: DateTime(2026, 11, 7),
                    firstDate: DateTime(2026, 11, 10),
                    lastDate: DateTime(2026, 12, 31),
                  ),
                  child: const Text('달력 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('달력 열기'));
    await tester.pumpAndSettle();
    expect(find.text('목표 종료일'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('date-2026-11-9')))
          .onTap,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('date-2026-11-12')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('날짜 선택'));
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 12));
    expect(tester.takeException(), isNull);
  });
}
