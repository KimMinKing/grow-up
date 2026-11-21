import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/focus_page.dart';
import 'package:growup/state/focus_session.dart';
import 'package:growup/main.dart';
import 'package:growup/state/growth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('saved paused focus restores and reset clears the snapshot', (
    tester,
  ) async {
    final prefs = SharedPreferencesAsync();
    final session = FocusSession()..start(DateTime.now());
    session.pause(DateTime.now().add(const Duration(seconds: 30)));
    await FocusSessionRepository(prefs).write('reading', session);
    await tester.pumpWidget(
      const MaterialApp(
        home: FocusPage(goalId: 'reading', title: '책 읽기', action: '한 쪽'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('이어 하기'), findsOneWidget);
    await tester.ensureVisible(find.text('타이머 다시 정하기'));
    await tester.tap(find.text('타이머 다시 정하기'));
    await tester.pumpAndSettle();
    expect(await FocusSessionRepository(prefs).read('reading'), isNull);
    expect(find.text('집중 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'focus hands off to explicit intensity selection without auto completion',
    (tester) async {
      final store = GrowthStore(SharedPreferencesAsync());
      await store.load();
      await store.addGoal(
        title: '독서',
        mini: '한 쪽',
        more: '열 쪽',
        max: '한 장',
        path: '작게',
        milestones: [],
      );
      await tester.pumpWidget(GrowUpApp(store: store));
      await tester.tap(find.text('실천').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2분부터 집중하기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('여기까지 하고 실천 기록하기'));
      await tester.tap(find.text('여기까지 하고 실천 기록하기'));
      await tester.pumpAndSettle();
      expect(store.todayDone, 0);
      expect(find.text('MINI'), findsOneWidget);
      await tester.tap(find.text('MINI'));
      await tester.pumpAndSettle();
      expect(store.todayDone, 1);
      expect(store.goals.single.completions[store.today], 'MINI');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'focus survives a fresh repository and stays isolated by goal',
    () async {
      final prefs = SharedPreferencesAsync();
      final now = DateTime(2026, 11, 11, 10);
      final session = FocusSession()..start(now);
      await FocusSessionRepository(prefs).write('reading', session);
      final restored = await FocusSessionRepository(prefs).read('reading');
      expect(
        restored!.remainingAt(now.add(const Duration(seconds: 40))),
        const Duration(seconds: 80),
      );
      expect(await FocusSessionRepository(prefs).read('walking'), isNull);
      await FocusSessionRepository(prefs).clearForGoal('walking');
      expect(await FocusSessionRepository(prefs).read('reading'), isNotNull);
      restored.pause(now.add(const Duration(seconds: 40)));
      await FocusSessionRepository(prefs).write('reading', restored);
      expect(
        (await FocusSessionRepository(prefs).read('reading'))!
            .remainingAt(now.add(const Duration(days: 1))),
        const Duration(seconds: 80),
      );
      await FocusSessionRepository(prefs).clear();
      expect(await FocusSessionRepository(prefs).read('reading'), isNull);
      expect(
        () => FocusSession.fromJson({'durationMs': -1}),
        throwsFormatException,
      );
    },
  );
  test(
    'focus deadline includes background time and freezes only while paused',
    () {
      final now = DateTime(2026, 11, 11, 10);
      final session = FocusSession();
      session.start(now);
      session.start(now.add(const Duration(seconds: 30)));
      expect(
        session.remainingAt(now.add(const Duration(seconds: 50))),
        const Duration(seconds: 70),
      );
      session.pause(now.add(const Duration(seconds: 50)));
      expect(
        session.remainingAt(now.add(const Duration(minutes: 8))),
        const Duration(seconds: 70),
      );
      session.start(now.add(const Duration(minutes: 8)));
      expect(
        session.remainingAt(now.add(const Duration(minutes: 10))),
        Duration.zero,
      );
      session.pause(now.add(const Duration(minutes: 10)));
      session.start(now.add(const Duration(minutes: 11)));
      expect(session.running, isFalse);
      session.reset();
      session.selectMinutes(5);
      expect(session.remaining, const Duration(minutes: 5));
      expect(session.started, isFalse);
    },
  );

  testWidgets(
    'focus fits large text, protects exit and records only on explicit request',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('열기'),
                onPressed: () async {
                  result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FocusPage(
                        goalId: 'reading',
                        title: '책 읽는 습관',
                        action: '책 한 쪽 펼치기',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('집중 시작'), 200);
      await tester.tap(find.text('집중 시작'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('집중을 마칠까요?'), findsOneWidget);
      await tester.tap(find.text('이어 하기'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.scrollUntilVisible(find.text('여기까지 하고 실천 기록하기'), 200);
      await tester.tap(find.text('여기까지 하고 실천 기록하기'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
