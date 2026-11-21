import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GrowthStore> makeStore() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    return store;
  }

  testWidgets('two-minute first action becomes a separate, editable step', (
    tester,
  ) async {
    final store = await makeStore();
    await store.addTask('책 읽기');
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.ensureVisible(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2분 첫 행동 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('2분 첫 행동 정하기'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '2분만 책 읽기 시작하기',
    );
    await tester.enterText(find.byType(TextField).first, '책 첫 페이지 펼치기');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(store.tasks.single.steps.single.title, '책 첫 페이지 펼치기');
    expect(store.tasks.single.completedDay, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enough for today moves one-off task to tomorrow', (
    tester,
  ) async {
    final store = await makeStore();
    await store.addTask('정리하기');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오늘은 여기까지'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(
      store.tasks.single.scheduledDay,
      dayKey(DateTime(now.year, now.month, now.day + 1)),
    );
    expect(
      store.tasks.single.movedOccurrences[store.today],
      store.tasks.single.scheduledDay,
    );
    expect(store.tasks.single.completedDay, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enough for today skips only this repeat occurrence', (
    tester,
  ) async {
    final store = await makeStore();
    await store.addTask('매일 산책', repeatPattern: 'daily');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오늘은 여기까지'));
    await tester.pumpAndSettle();

    expect(store.tasks.single.skippedOccurrences, contains(store.today));
    expect(store.tasks.single.repeatPattern, 'daily');
    expect(store.tasks.single.completedOccurrences, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
