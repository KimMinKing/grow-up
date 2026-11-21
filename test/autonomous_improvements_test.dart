import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/daily_content_widgets.dart';
import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/game_creature.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/models/squad_readiness.dart';
import 'package:growup/state/growth_store.dart';
import 'package:growup/state/weekly_statistics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'routine example remains editable and cancellation creates nothing',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = GrowthStore(prefs);
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TodayChecklist(store: store)),
          ),
        ),
      );
      await tester.tap(find.text('할 일 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('작은 루틴 예시에서 시작'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('책상 한 곳 정리하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('책상 한 곳 정리하기'));
      await tester.pumpAndSettle();
      expect(store.tasks, isEmpty);
      await tester.enterText(find.byType(TextField).first, '책상 오른쪽 정리하기');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, '책상 오른쪽 정리하기');
      expect(store.tasks.single.repeatPattern, 'weekly');
      expect(store.tasks.single.repeatWeekdays, [1, 2, 3, 4, 5]);
      expect(store.tasks.single.tags, ['정리']);
      expect(store.tasks.single.completedOccurrences, isEmpty);
      final restored = GrowthStore(prefs);
      await restored.load();
      expect(restored.tasks.single.repeatWeekdays, [1, 2, 3, 4, 5]);
      await tester.tap(find.text('할 일 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('작은 루틴 예시에서 시작'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('책 한 쪽 읽기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(store.tasks, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy menu adds an unchecked task on a narrow screen', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await store.addTask('정리');
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TodayChecklist(store: store)),
        ),
      ),
    );
    await tester.ensureVisible(find.byTooltip('할 일 메뉴'));
    await tester.tap(find.byTooltip('할 일 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 할 일로 복사'));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(2));
    expect(store.tasks.last.completedDay, isNull);
    expect(tester.takeException(), isNull);
  });

  test('weekly review respects boundaries, rest and archived history', () {
    GrowthGoal goal(String id, {bool archived = false, String? start}) =>
        GrowthGoal(
          id: id,
          title: id,
          mini: '작게',
          more: '보통',
          max: '크게',
          path: '작게',
          weeklyTarget: 3,
          milestones: [],
          createdAt: DateTime(2026, 11, 1),
          startDate: start,
          archived: archived,
          completions: {
            '2026-11-08': 'MINI',
            '2026-11-09': 'MINI',
            '2026-11-15': 'MAX',
            '2026-11-16': 'MORE',
          },
          restDays: {'2026-11-10', '2026-11-16'},
        );
    final reviews = WeeklyGoalReview.calculate(DateTime(2026, 11, 11), [
      goal('active'),
      goal('archived', archived: true),
      goal('future', start: '2026-11-16'),
    ]);
    expect(reviews, hasLength(2));
    expect(reviews.first.practiceDays, ['2026-11-09', '2026-11-15']);
    expect(reviews.first.restDays, 1);
    expect(reviews.first.levels, {'MINI': 1, 'MORE': 0, 'MAX': 1});
    reviews.first.goal.completions['2026-11-12'] = '보통';
    expect(
      WeeklyGoalReview.calculate(DateTime(2026, 11, 11), [
        reviews.first.goal,
      ]).single.levels['MORE'],
      1,
    );
  });

  test('squad review distinguishes owned and actually deployed creatures', () {
    const fox = CreatureInstance(id: 'fox', speciesId: 'pine_fox', level: 1);
    const crow = CreatureInstance(id: 'crow', speciesId: 'star_crow', level: 1);
    final review = SquadReadiness.evaluate(
      firstForestStages.last,
      [null, null, 'fox', null, null],
      [fox, crow],
    );
    expect(review.members, [fox]);
    expect(review.advice.join(), contains('편성하지 않은 동료가 1마리'));
    expect(review.advice.join(), contains('전열이 비어'));
    expect(review.advice.join(), contains('권장 전투력보다 낮아요'));
    final empty = SquadReadiness.evaluate(
      firstForestStages.first,
      List.filled(5, null),
      [fox],
    );
    expect(empty.power, 0);
    expect(empty.advice.first, contains('한 마리 이상'));
  });
}
