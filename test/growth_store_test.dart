import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:growup/main.dart';
import 'package:growup/models/growth_goal.dart';
import 'package:growup/models/roadmap_draft.dart';
import 'package:growup/models/roadmap_plan.dart';
import 'package:growup/state/growth_store.dart';
import 'package:growup/state/growth_backup.dart';
import 'package:growup/state/game_store.dart';
import 'package:growup/state/auth_gateway.dart';
import 'package:growup/state/roadmap_generator.dart';
import 'package:growup/state/task_reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'same-day MINI can be updated to MAX without adding a second day',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.load();
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '균형 있게',
        milestones: ['첫 책'],
      );
      final goal = store.goals.single;

      await store.complete(goal, 'MINI');
      expect(goal.completionActions[store.today], '2쪽');
      await store.complete(goal, 'MAX');
      expect(goal.completions[store.today], 'MAX');
      expect(goal.completionActions[store.today], '40분');
      expect(store.todayDone, 1);
      expect(store.totalCompletedDays, 1);
      expect(store.maxCompletions, 1);

      await store.updateGoalActions(goal, mini: '3쪽', more: '20분', max: '1시간');
      expect(store.recentActivity(goal).single.action, '40분');
      await store.setGuardianName('별이');
      final restored = GrowthStore(SharedPreferencesAsync());
      await restored.load();
      expect(restored.goals.single.mini, '3쪽');
      expect(restored.goals.single.completions[restored.today], 'MAX');
      expect(restored.goals.single.completionActions[restored.today], '40분');
      expect(restored.guardianName, '별이');
    },
  );

  test('days since last practice uses the latest completed day', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final goal = store.goals.single;
    expect(
      store.daysSinceLastPractice(goal, on: DateTime(2026, 10, 31)),
      isNull,
    );
    goal.completions['2026-10-25'] = 'MINI';
    goal.completions['2026-10-28'] = 'MORE';
    expect(store.daysSinceLastPractice(goal, on: DateTime(2026, 10, 31)), 3);
  });

  test('editing roadmap steps keeps completed indices aligned', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: ['첫 단계', '둘째 단계', '셋째 단계'],
    );
    final goal = store.goals.single;
    await store.toggleMilestone(goal, 0);
    await store.toggleMilestone(goal, 2);
    expect(await store.updateMilestone(goal, 1, '중간 단계'), isTrue);
    expect(await store.addMilestone(goal, '넷째 단계'), isTrue);
    expect(await store.removeMilestone(goal, 1), isTrue);
    expect(goal.milestones, ['첫 단계', '셋째 단계', '넷째 단계']);
    expect(goal.completedMilestones, {0, 1});

    final restored = GrowthStore(SharedPreferencesAsync());
    await restored.load();
    expect(restored.goals.single.milestones, goal.milestones);
    expect(restored.goals.single.completedMilestones, {0, 1});
  });

  test(
    'weekly goal uses calendar weeks and persists edited settings',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '가볍게 시작',
        milestones: [],
      );
      final goal = store.goals.single;
      expect(goal.weeklyTarget, 2);
      final monday = startOfWeek(DateTime(2026, 10, 31));
      goal.completions[dayKey(monday.subtract(const Duration(days: 1)))] =
          'MINI';
      goal.completions[dayKey(monday)] = 'MINI';
      goal.completions[dayKey(monday.add(const Duration(days: 6)))] = 'MAX';
      goal.restDays.add(dayKey(monday.add(const Duration(days: 2))));
      expect(store.completedDaysThisWeek(goal, on: DateTime(2026, 10, 31)), 2);

      expect(
        await store.updateGoalSettings(
          goal,
          title: ' 매일 독서 ',
          path: '균형 있게',
          weeklyTarget: 4,
        ),
        isTrue,
      );
      final restored = GrowthStore(SharedPreferencesAsync());
      await restored.load();
      expect(restored.goals.single.title, '매일 독서');
      expect(restored.goals.single.path, '균형 있게');
      expect(restored.goals.single.weeklyTarget, 4);
      expect(
        restored.completedDaysThisWeek(
          restored.goals.single,
          on: DateTime(2026, 10, 31),
        ),
        2,
      );
    },
  );

  test('older saved goals get a suggested weekly target', () {
    final goal = GrowthGoal(
      id: 'old',
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '집중해서',
      weeklyTarget: 5,
      milestones: [],
      createdAt: DateTime(2026, 10, 1),
    );
    final previousData = goal.toJson()..remove('weeklyTarget');
    expect(GrowthGoal.fromJson(previousData).weeklyTarget, 5);
    expect(GrowthGoal.fromJson(previousData).currentLevel, '');
    expect(GrowthGoal.fromJson(previousData).targetDate, isNull);
    previousData.remove('startDate');
    expect(GrowthGoal.fromJson(previousData).startDay, '2026-10-01');
    expect(GrowthGoal.fromJson(previousData).weeklyMinutes, isNull);
    previousData['selectedPlan'] = {'source': 'ai'};
    expect(GrowthGoal.fromJson(previousData).selectedPlan, isNull);
  });

  test('roadmap brief survives creation, edits, and reload', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
      currentLevel: '한 달에 한 권',
      targetDate: '2027-01-31',
      weeklyMinutes: 120,
    );
    final goal = store.goals.single;
    expect(goal.currentLevel, '한 달에 한 권');
    expect(goal.targetDate, '2027-01-31');
    expect(goal.weeklyMinutes, 120);
    await store.updateGoalSettings(
      goal,
      title: '독서',
      path: goal.path,
      weeklyTarget: goal.weeklyTarget,
      currentLevel: '다시 시작',
      targetDate: '',
      weeklyMinutes: 0,
    );
    final restored = GrowthStore(SharedPreferencesAsync());
    await restored.load();
    expect(restored.goals.single.currentLevel, '다시 시작');
    expect(restored.goals.single.targetDate, isNull);
    expect(restored.goals.single.weeklyMinutes, isNull);
  });

  test('goal period survives backup and rejects reversed dates', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    expect(
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '균형 있게',
        milestones: [],
        startDate: '2026-11-10',
        targetDate: '2027-01-31',
      ),
      isTrue,
    );
    expect(store.goals.single.startDay, '2026-11-10');
    final restored = GrowthBackup.decode(store.createBackup().encode());
    expect(restored.goals.single.startDay, '2026-11-10');
    expect(
      await store.updateGoalSettings(
        store.goals.single,
        title: '독서',
        path: '균형 있게',
        weeklyTarget: 3,
        startDate: '2027-02-01',
      ),
      isFalse,
    );
    expect(store.goals.single.startDay, '2026-11-10');
  });

  test(
    'manual roadmap drafts use the entered actions and distinct weekly days',
    () {
      final drafts = manualRoadmapDrafts(mini: '2쪽', more: '15분', max: '40분');
      expect(drafts.map((draft) => draft.weeklyTarget), [2, 3, 5]);
      expect(drafts.first.firstWeekActions, contains('MINI · 2쪽'));
      expect(drafts.last.firstWeekActions, contains('여유 있는 날 MAX · 40분'));
    },
  );

  test('manual start plan has dated editable stages from entered actions', () {
    final drafts = manualRoadmapDrafts(
      mini: '2쪽',
      more: '15분',
      max: '40분',
      firstMilestone: '첫 책 끝내기',
      startDate: DateTime(2026, 11, 2),
      targetDate: DateTime(2026, 12, 14),
      weeklyMinutes: 90,
    );
    final balanced = drafts[1];
    expect(balanced.durationWeeks, 6);
    expect(balanced.weeklyMinutes, 90);
    expect(balanced.stages.length, 3);
    expect(balanced.stages.first.targetDate, '2026-11-09');
    expect(balanced.stages.last.targetDate, '2026-12-14');
    expect(balanced.stages.last.title, '첫 책 끝내기');
    expect(balanced.stages[1].detail.method, '15분');
    final plan = RoadmapPlan.fromManualDraft(
      balanced,
      firstMilestone: '첫 책 끝내기',
    );
    expect(plan.milestones, balanced.stages.map((stage) => stage.title));
    expect(plan.durationWeeks, 6);
  });

  test('manual plans match short deadlines instead of promising two weeks', () {
    final today = DateTime(2026, 11, 2);
    final sameDay = manualRoadmapDrafts(
      mini: '2쪽',
      more: '15분',
      max: '40분',
      startDate: today,
      targetDate: today,
    );
    expect(sameDay.every((draft) => draft.stages.length == 1), isTrue);
    expect(sameDay.first.stages.single.targetDate, '2026-11-02');
    final threeDay = manualRoadmapDrafts(
      mini: '2쪽',
      more: '15분',
      max: '40분',
      startDate: today,
      targetDate: DateTime(2026, 11, 5),
    );
    for (final draft in threeDay) {
      expect(draft.stages, hasLength(1));
      expect(draft.stages.single.targetDate, '2026-11-05');
      expect(
        () => RoadmapPlan.fromManualDraft(draft).validate(),
        returnsNormally,
      );
    }

    final tenDay = manualRoadmapDrafts(
      mini: '2쪽',
      more: '15분',
      max: '40분',
      startDate: today,
      targetDate: DateTime(2026, 11, 12),
    );
    for (final draft in tenDay) {
      expect(draft.stages, hasLength(2));
      expect(draft.stages.first.targetDate, '2026-11-07');
      expect(draft.stages.last.targetDate, '2026-11-12');
      expect(draft.stages.first.criteria, contains('1회'));
    }
  });

  test('manual plan accepts the full action length offered by the wizard', () {
    final drafts = manualRoadmapDrafts(
      mini: 'm' * 160,
      more: 'o' * 160,
      max: 'x' * 160,
    );
    for (final draft in drafts) {
      final plan = RoadmapPlan.fromManualDraft(draft);
      expect(() => plan.validate(), returnsNormally);
      expect(
        draft.stages.every((stage) => stage.detail.method.length <= 300),
        isTrue,
      );
    }
  });

  test('AI roadmap options require three complete feasible plans', () {
    Map<String, dynamic> option(String title, int days) => {
      'title': title,
      'summary': '실천 계획',
      'weeklyTarget': days,
      'durationWeeks': 8,
      'weeklyMinutes': 90,
      'milestones': ['첫 단계', '마무리'],
      'firstWeekActions': ['첫 주 행동'],
    };
    final valid = [option('가벼운 안', 2), option('균형 안', 3), option('집중 안', 5)];
    expect(parseAiRoadmapOptions(valid, availableMinutes: 120).length, 3);
    expect(
      () => parseAiRoadmapOptions(valid, availableMinutes: 60),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions(valid.take(2).toList()),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions([
        option('같은 안', 2),
        option('같은 안', 3),
        option('다른 안', 5),
      ]),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions([
        option('가벼운 안', 3),
        option('균형 안', 3),
        option('집중 안', 3),
      ]),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions([
        option('가벼운 안', 3)..['summary'] = '조금씩 시작',
        option('균형 안', 3)..['summary'] = '꾸준히 진행',
        option('집중 안', 3)..['summary'] = '빠르게 마무리',
      ]),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions([
        option('가벼운 안', 2),
        option('균형 안', 3)..['milestones'] = <String>[],
        option('집중 안', 5),
      ]),
      throwsFormatException,
    );
    expect(
      () => parseAiRoadmapOptions([
        option('가벼운 안', 2),
        option('균형 안', 3)..['durationWeeks'] = 8.5,
        option('집중 안', 5),
      ]),
      throwsFormatException,
    );
  });

  test(
    'HTTP roadmap request uses a user token and rejects bad responses',
    () async {
      const request = RoadmapRequest(
        goal: '독서',
        currentLevel: '시작 단계',
        targetDate: '2027-01-31',
        availableMinutes: 120,
        preferredPath: '균형 있게',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        firstMilestone: '첫 책',
      );
      Map<String, dynamic> option(String title, int days) => {
        'title': title,
        'summary': '읽는 양을 늘려요',
        'weeklyTarget': days,
        'durationWeeks': 8,
        'weeklyMinutes': 90,
        'milestones': ['첫 책', '두 번째 책'],
        'firstWeekActions': ['책 2쪽 읽기'],
      };
      var calls = 0;
      final client = MockClient((sent) async {
        calls++;
        String? header(String name) {
          for (final entry in sent.headers.entries) {
            if (entry.key.toLowerCase() == name) return entry.value;
          }
          return null;
        }

        expect(header('authorization'), 'Bearer user-jwt');
        expect(header('apikey'), 'public-key');
        expect(jsonDecode(sent.body)['goal'], '독서');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'plans': [
                option('가벼운 안', 2),
                option('균형 안', 3),
                option('집중 안', 5),
              ],
            }),
          ),
          200,
        );
      });
      final generator = HttpRoadmapGenerator(
        endpoint: Uri.parse(
          'https://example.test/functions/v1/generate-roadmap',
        ),
        accessToken: () async => 'user-jwt',
        publishableKey: 'public-key',
        client: client,
      );
      expect((await generator.generate(request)).length, 3);
      expect(calls, 1);

      final missingLogin = HttpRoadmapGenerator(
        endpoint: generator.endpoint,
        accessToken: () async => null,
        client: client,
      );
      await expectLater(
        missingLogin.generate(request),
        throwsA(isA<RoadmapGenerationException>()),
      );
      expect(calls, 1);

      final invalid = HttpRoadmapGenerator(
        endpoint: generator.endpoint,
        accessToken: () async => 'user-jwt',
        client: MockClient((_) async => http.Response('{"plans":[]}', 200)),
      );
      await expectLater(
        invalid.generate(request),
        throwsA(isA<RoadmapGenerationException>()),
      );

      final limited = HttpRoadmapGenerator(
        endpoint: generator.endpoint,
        accessToken: () async => 'user-jwt',
        client: MockClient(
          (_) async => http.Response('{"error":"monthly_limit_reached"}', 429),
        ),
      );
      await expectLater(
        limited.generate(request),
        throwsA(
          isA<RoadmapGenerationException>().having(
            (error) => error.message,
            'message',
            contains('이번 달'),
          ),
        ),
      );
    },
  );

  test('invalid roadmap brief is rejected before a network request', () async {
    var calls = 0;
    final generator = HttpRoadmapGenerator(
      endpoint: Uri.parse('https://example.test/functions/v1/generate-roadmap'),
      accessToken: () async => 'user-jwt',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    RoadmapRequest brief({
      String goal = '독서',
      String targetDate = '2027-01-31',
      String currentLevel = '시작',
      String preferredPath = '균형 있게',
      String mini = '2쪽',
      String more = '15분',
      String max = '40분',
      String firstMilestone = '첫 책',
    }) => RoadmapRequest(
      goal: goal,
      currentLevel: currentLevel,
      targetDate: targetDate,
      availableMinutes: 120,
      preferredPath: preferredPath,
      mini: mini,
      more: more,
      max: max,
      firstMilestone: firstMilestone,
    );

    for (final invalid in [
      brief(targetDate: '2027-02-30'),
      brief(goal: '가' * 121),
      brief(mini: '가' * 161),
    ]) {
      await expectLater(
        generator.generate(invalid),
        throwsA(isA<RoadmapGenerationException>()),
      );
    }
    final escaped = String.fromCharCode(1);
    await expectLater(
      generator.generate(
        brief(
          goal: escaped * 120,
          currentLevel: escaped * 160,
          preferredPath: escaped * 60,
          mini: escaped * 160,
          more: escaped * 160,
          max: escaped * 160,
          firstMilestone: escaped * 120,
        ),
      ),
      throwsA(isA<RoadmapGenerationException>()),
    );
    expect(calls, 0);
  });

  test(
    'history orders practice and rest while weekly counts exclude rest',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '균형 있게',
        milestones: [],
      );
      final goal = store.goals.single;
      final current = startOfWeek(DateTime(2026, 10, 31));
      final previous = current.subtract(const Duration(days: 7));
      goal.completions[dayKey(previous)] = 'MINI';
      goal.completions[dayKey(current.add(const Duration(days: 2)))] = 'MORE';
      goal.restDays.add(dayKey(current.add(const Duration(days: 3))));
      goal.restDays.add(dayKey(current.add(const Duration(days: 2))));

      final weeks = store.recentWeeks(
        goal,
        on: DateTime(2026, 10, 31),
        count: 2,
      );
      expect(weeks.map((week) => week.completedDays).toList(), [1, 1]);
      final activity = store.recentActivity(goal);
      expect(activity.map((event) => event.level).toList(), [
        '쉼',
        'MORE',
        'MINI',
      ]);
      expect(store.recentActivity(goal, limit: 2).length, 2);
    },
  );

  testWidgets('a reminder opens its task from cold start and game screen', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addTask(
      '독서 준비하기',
      scheduledDay: store.today,
      scheduledTime: '14:30',
      reminderEnabled: true,
    );
    final id = store.tasks.single.id;
    addTearDown(() => taskReminderService.tappedTaskId.value = null);
    taskReminderService.tappedTaskId.value = id;
    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('알림의 할 일'), findsOneWidget);
    expect(find.text('독서 준비하기'), findsWidgets);
    expect(find.textContaining('예정 시간 · 14:30'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('게임'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    taskReminderService.tappedTaskId.value = id;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('알림의 할 일'), findsOneWidget);
    expect(find.text('전설키우기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice tab collapses completed and rest states', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽 읽기',
      more: '15분 읽기',
      max: '40분 읽기',
      path: '균형 있게',
      milestones: [],
    );
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MINI').first);
    await tester.pumpAndSettle();
    expect(store.goals.single.completions[store.today], 'MINI');
    expect(find.text('오늘 MINI 완료!'), findsOneWidget);
    expect(find.text('MORE'), findsNothing);

    await tester.tap(find.text('더 했어요'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('MAX').first);
    await tester.tap(find.text('MAX').first);
    await tester.pumpAndSettle();
    expect(store.goals.single.completions[store.today], 'MAX');
    expect(store.todayDone, 1);

    await tester.tap(find.byTooltip('목표 수정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('MINI · MORE · MAX 행동 수정'));
    await tester.tap(find.text('MINI · MORE · MAX 행동 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '3쪽 읽기');
    await tester.ensureVisible(find.text('변경 저장'));
    await tester.tap(find.text('변경 저장'));
    await tester.pumpAndSettle();
    expect(store.goals.single.mini, '3쪽 읽기');

    await tester.ensureVisible(find.text('기록 수정'));
    await tester.tap(find.text('기록 수정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('오늘 기록 취소'));
    await tester.tap(find.text('오늘 기록 취소'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('오늘 쉬기'));
    await tester.tap(find.text('오늘 쉬기'));
    await tester.pumpAndSettle();
    expect(store.todayRest, 1);
    expect(store.todayDone, 0);
    expect(find.text('MINI'), findsNothing);
    expect(find.textContaining('쉬는 날로 기록했어요'), findsOneWidget);
    await tester.tap(find.text('오늘').last);
    await tester.pumpAndSettle();
    expect(find.text('오늘은 쉬는 날'), findsOneWidget);
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 실천하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('MINI').first);
    await tester.tap(find.text('MINI').first);
    await tester.pumpAndSettle();
    expect(store.todayRest, 0);
    expect(store.todayDone, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning after a gap shows a gentle MINI restart', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽 읽기',
      more: '15분 읽기',
      max: '40분 읽기',
      path: '균형 있게',
      milestones: [],
    );
    store.goals.single.completions[dayKey(
          DateTime.now().subtract(const Duration(days: 3)),
        )] =
        'MINI';

    await tester.pumpWidget(GrowUpApp(store: store));
    expect(find.text('다시 시작 · MINI: 2쪽 읽기'), findsOneWidget);
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    expect(find.text('며칠 비워도 괜찮아요. 오늘은 MINI만 해도 충분해요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice shows one create action until a goal exists', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    expect(find.text('첫 목표 만들기'), findsOneWidget);
    expect(find.text('새 목표 만들기'), findsNothing);

    await store.addGoal(
      title: '독서',
      mini: '2쪽 읽기',
      more: '15분 읽기',
      max: '40분 읽기',
      path: '균형 있게',
      milestones: [],
    );
    await tester.pumpAndSettle();
    expect(find.text('첫 목표 만들기'), findsNothing);
    await tester.scrollUntilVisible(find.text('새 목표 만들기'), 250);
    expect(find.text('새 목표 만들기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact toolbar keeps theme access at 300dp with large text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(GrowUpApp(store: store));
    final title = tester.renderObject<RenderParagraph>(find.text('전설키우기'));
    expect(
      title.size.width,
      greaterThanOrEqualTo(title.getMaxIntrinsicWidth(double.infinity)),
    );
    expect(find.byTooltip('설정 더 보기'), findsOneWidget);
    await tester.tap(find.byTooltip('설정 더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('어두운 테마'));
    await tester.pumpAndSettle();
    expect(store.darkTheme, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact toolbar keeps the app name visible at 300dp', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.load();
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    final title = tester.renderObject<RenderParagraph>(find.text('전설키우기'));
    expect(
      title.size.width,
      greaterThanOrEqualTo(title.getMaxIntrinsicWidth(double.infinity)),
    );
    expect(find.byTooltip('설정 더 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme switch changes the app and survives reload', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    expect(
      Theme.of(tester.element(find.byType(AppShell))).brightness,
      Brightness.light,
    );
    await tester.tap(find.byTooltip('어두운 테마'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AppShell))).brightness,
      Brightness.dark,
    );
    expect(find.byTooltip('밝은 테마'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final restored = GrowthStore(SharedPreferencesAsync());
    await restored.load();
    expect(restored.darkTheme, isTrue);
  });

  testWidgets('archive dialog is compact and cancelling keeps the goal', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    expect(find.text('보관'), findsNothing);
    await tester.tap(find.byTooltip('목표 수정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('이 목표 보관하기'));
    await tester.tap(find.text('이 목표 보관하기'));
    await tester.pumpAndSettle();
    expect(find.text('목표 보관'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('archive-dialog-content')))
          .height,
      lessThan(210),
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(store.goals.single.title, '독서');
    expect(tester.takeException(), isNull);
  });

  testWidgets('roadmap steps can be added, edited, and deleted in practice', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('로드맵 0/0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('단계 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '이정표'), '한 장 완성');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.goals.single.milestones, ['한 장 완성']);

    await tester.tap(find.byTooltip('로드맵 단계 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '이정표'), '두 장 완성');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.goals.single.milestones, ['두 장 완성']);

    await tester.tap(find.byTooltip('로드맵 단계 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('단계 삭제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('완료 표시도 함께'), findsOneWidget);
    await tester.tap(find.text('삭제 확인'));
    await tester.pumpAndSettle();
    expect(store.goals.single.milestones, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal settings can be changed after creation', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('실천').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('목표 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '목표 이름'), '책 읽기');
    await tester.ensureVisible(find.widgetWithText(TextField, '현재 수준 (선택)'));
    await tester.enterText(
      find.widgetWithText(TextField, '현재 수준 (선택)'),
      '한 달에 한 권',
    );
    await tester.ensureVisible(
      find.widgetWithText(TextField, '일주일에 쓸 수 있는 시간 · 분 (선택)'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '일주일에 쓸 수 있는 시간 · 분 (선택)'),
      '120',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('집중해서'));
    await tester.tap(find.text('집중해서'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('6일'));
    await tester.tap(find.text('6일'));
    await tester.ensureVisible(find.text('변경 저장'));
    await tester.tap(find.text('변경 저장'));
    await tester.pumpAndSettle();

    expect(store.goals.single.title, '책 읽기');
    expect(store.goals.single.path, '집중해서');
    expect(store.goals.single.weeklyTarget, 6);
    expect(store.goals.single.currentLevel, '한 달에 한 권');
    expect(store.goals.single.weeklyMinutes, 120);
    await tester.tap(find.text('목표 상세보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이번 주 0/6일'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new goal accepts roadmap context on a phone width', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('목표 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '독서');
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('균형 있게').last);
    await tester.pumpAndSettle();
    for (final action in ['2쪽', '15분', '40분']) {
      await tester.enterText(find.byType(TextField).last, action);
      await tester.tap(find.text('다음').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    expect(find.text('지금 상황은?'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '현재 수준'), '시작 단계');
    await tester.enterText(
      find.widgetWithText(TextField, '일주일에 쓸 수 있는 시간 · 분'),
      '90',
    );
    await tester.ensureVisible(find.text('종료일 선택'));
    await tester.tap(find.text('종료일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pump();
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    final later = DateTime(DateTime.now().year, DateTime.now().month + 2, 15);
    await tester.tap(
      find.byKey(ValueKey('date-${later.year}-${later.month}-15')),
    );
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    expect(find.text('시작 방법은?'), findsOneWidget);
    final focusedDraft = find.text('집중해서 · 주 5일');
    await tester.ensureVisible(focusedDraft);
    await tester.tap(focusedDraft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('목표 시작하기'));
    await tester.pumpAndSettle();
    expect(store.goals.single.currentLevel, '시작 단계');
    expect(store.goals.single.weeklyMinutes, 90);
    expect(store.goals.single.path, '집중해서');
    expect(store.goals.single.weeklyTarget, 5);
    expect(store.goals.single.selectedPlan?.title, '집중해서');
    expect(store.goals.single.milestones.length, 3);
    expect(store.goals.single.milestoneDetails[1].criteria, contains('주 5일'));
    expect(
      store.goals.single.selectedPlan?.firstWeekActions,
      contains('여유 있는 날 MAX · 40분'),
    );
    final reloaded = GrowthStore(SharedPreferencesAsync());
    await reloaded.load();
    expect(reloaded.goals.single.selectedPlan?.title, '집중해서');
    await tester.tap(find.text('기록').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('독서'), 250);
    await tester.tap(find.text('독서'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('처음 선택한 계획'), 300);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처음 선택한 계획'));
    await tester.pumpAndSettle();
    expect(find.text('• 여유 있는 날 MAX · 40분'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal can start without creating a roadmap', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('목표 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '독서');
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('균형 있게').last);
    await tester.pumpAndSettle();
    for (final action in ['2쪽', '15분', '40분']) {
      await tester.enterText(find.byType(TextField).last, action);
      await tester.tap(find.text('다음').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('로드맵은 나중에 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('목표 시작하기'));
    await tester.pumpAndSettle();
    expect(store.goals.single.milestones, isEmpty);
    expect(store.goals.single.selectedPlan, isNull);
    expect(store.goals.single.mini, '2쪽');
    expect(store.goals.single.targetDate, isNull);
  });

  testWidgets('goal wizard keeps its header readable at 300dp large text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('목표 만들기'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('목표 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('새 목표'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an AI plan can be selected and saved from the goal wizard', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _FakeAuthGateway()..currentUserEmail = 'reader@example.com';
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      GrowUpApp(
        store: store,
        authGateway: auth,
        roadmapGenerator: _FakeRoadmapGenerator(),
      ),
    );
    await tester.tap(find.text('목표 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('책 읽는 습관 만들기').last);
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('균형 있게').last);
    await tester.pumpAndSettle();
    for (var step = 0; step < 4; step++) {
      await tester.tap(find.text('다음').last);
      await tester.pumpAndSettle();
    }
    expect(find.text('지금 상황은?'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '현재 수준'), '시작 단계');
    await tester.enterText(
      find.widgetWithText(TextField, '일주일에 쓸 수 있는 시간 · 분'),
      '120',
    );
    await tester.tap(find.text('종료일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('날짜 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 계획 3안 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('임시 오류'), findsOneWidget);
    expect(find.textContaining('입력한 행동으로 만든 시작 템플릿'), findsOneWidget);
    await tester.tap(find.text('AI 계획 3안 만들기'));
    await tester.pumpAndSettle();
    final chosen = find.text('균형 안');
    await tester.ensureVisible(chosen);
    await tester.tap(chosen);
    await tester.pumpAndSettle();
    await tester.tap(find.text('목표 시작하기'));
    await tester.pumpAndSettle();
    expect(store.goals.single.selectedPlan?.source, 'ai');
    expect(store.goals.single.selectedPlan?.title, '균형 안');
    expect(store.goals.single.milestones, ['첫 책', '두 번째 책']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email code login and logout leave local goals intact', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final auth = _FakeAuthGateway();
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();
    expect(find.text('이메일로 로그인'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'reader@example.com');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pumpAndSettle();
    expect(auth.lastCodeEmail, 'reader@example.com');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('코드 확인'));
    await tester.pumpAndSettle();
    expect(find.text('전설키우기 사용자'), findsOneWidget);
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('이메일로 로그인'), findsOneWidget);
    expect(store.goals.single.title, '독서');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email link sign-in updates the account without changing goals', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final auth = _FakeAuthGateway();
    addTearDown(auth.dispose);
    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'reader@example.com');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('메일의 인증번호를 아래에 입력해 주세요'), findsOneWidget);
    auth.simulateLinkSignIn('reader@example.com');
    await tester.pumpAndSettle();
    expect(find.text('전설키우기 사용자'), findsOneWidget);
    expect(store.goals.single.title, '독서');
  });

  testWidgets('email server failure shows SMTP guidance on the account page', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    final auth = _FakeAuthGateway()
      ..sendError = const AuthException(
        'Error sending email',
        statusCode: '500',
        code: 'unexpected_failure',
      );
    addTearDown(auth.dispose);

    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'reader@example.com');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SMTP 발송 설정을 확인해 주세요'), findsOneWidget);
    expect(find.text('인증번호 받기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account settings and data guide open from the signed-in hub', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    final auth = _FakeAuthGateway()..currentUserEmail = 'reader@example.com';
    addTearDown(auth.dispose);
    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();

    expect(find.text('전설키우기 사용자'), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
    await tester.ensureVisible(find.text('앱 설정'));
    await tester.tap(find.text('앱 설정'));
    await tester.pumpAndSettle();
    expect(find.text('어두운 테마'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('내 데이터'));
    await tester.tap(find.text('내 데이터'));
    await tester.pumpAndSettle();
    expect(find.text('내 정보가 저장되는 곳'), findsOneWidget);
    expect(find.textContaining('서버 계정 삭제 기능은 준비 중'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('회원탈퇴'));
    expect(find.text('서버 삭제 기능 준비 중'), findsOneWidget);
    final deleteTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('회원탈퇴'), matching: find.byType(ListTile)),
    );
    expect(deleteTile.onTap, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account and settings fit a narrow screen with large text', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final store = GrowthStore(SharedPreferencesAsync());
    final auth = _FakeAuthGateway()
      ..currentUserEmail = 'long.account@example.com';
    addTearDown(auth.dispose);
    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('설정 더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계정'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('앱 설정'));
    await tester.tap(find.text('앱 설정'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('내 데이터'));
    await tester.tap(find.text('내 데이터'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('삭제 방법'));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('기록 백업·가져오기'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('display name can be changed from the account profile', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    final auth = _FakeAuthGateway()..currentUserEmail = 'reader@example.com';
    addTearDown(auth.dispose);
    await tester.pumpWidget(GrowUpApp(store: store, authGateway: auth));
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 이름 변경'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '민기');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(auth.currentDisplayName, '민기');
    expect(find.text('민기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account deletion needs a typed confirmation and keeps device data',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = GrowthStore(SharedPreferencesAsync());
      await store.addGoal(
        title: '독서',
        mini: '2쪽',
        more: '15분',
        max: '40분',
        path: '균형 있게',
        milestones: [],
      );
      final auth = _FakeAuthGateway()..currentUserEmail = 'reader@example.com';
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        GrowUpApp(
          store: store,
          authGateway: auth,
          accountDeletionEnabled: true,
        ),
      );
      await tester.tap(find.byTooltip('계정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('회원탈퇴'));
      await tester.tap(find.text('회원탈퇴'));
      await tester.pumpAndSettle();

      final deleteButton = find.widgetWithText(FilledButton, '계정 삭제');
      expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
      expect(auth.deleteCalls, 0);
      await tester.enterText(find.byType(TextField).last, '탈퇴');
      await tester.pump();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(auth.deleteCalls, 1);
      expect(find.text('이메일로 로그인'), findsOneWidget);
      expect(store.goals.single.title, '독서');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device data deletion leaves the signed-in account intact', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = SharedPreferencesAsync();
    final store = GrowthStore(prefs);
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final gameStore = GameStore(prefs);
    await gameStore.chooseStarter('pine_fox');
    final auth = _FakeAuthGateway()..currentUserEmail = 'reader@example.com';
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      GrowUpApp(store: store, gameStore: gameStore, authGateway: auth),
    );
    await tester.tap(find.byTooltip('계정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('기기 기록 삭제'));
    await tester.tap(find.text('기기 기록 삭제').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '기록 삭제');
    await tester.pump();
    await tester.tap(find.text('기기 기록 삭제').last);
    await tester.pumpAndSettle();

    expect(store.goals, isEmpty);
    expect(gameStore.hasStarter, isFalse);
    expect(auth.currentUserEmail, 'reader@example.com');
    final reloadedStore = GrowthStore(SharedPreferencesAsync());
    final reloadedGame = GameStore(SharedPreferencesAsync());
    await reloadedStore.load();
    await reloadedGame.load();
    expect(reloadedStore.goals, isEmpty);
    expect(reloadedGame.hasStarter, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal history opens from records and shows real dated activity', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: ['첫 책'],
    );
    await store.complete(store.goals.single, 'MINI');
    await store.updateGoalActions(
      store.goals.single,
      mini: '3쪽',
      more: '20분',
      max: '1시간',
    );
    store.goals.single.restDays.add(
      dayKey(DateTime.now().subtract(const Duration(days: 1))),
    );
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('기록').last);
    await tester.pumpAndSettle();
    final historyCard = find.byKey(
      ValueKey('goal-history-${store.goals.single.id}'),
    );
    await tester.scrollUntilVisible(historyCard, 250);
    await tester.tap(historyCard);
    await tester.pumpAndSettle();
    expect(find.text('목표 기록'), findsOneWidget);
    expect(find.text('최근 4주'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('최근 활동'), 300);
    await tester.scrollUntilVisible(find.text('쉼'), 150);
    expect(find.text('쉼'), findsOneWidget);
    expect(find.text('MINI'), findsWidgets);
    expect(find.text('2쪽'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived goals keep an accessible history', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await store.addGoal(
      title: '독서',
      mini: '2쪽',
      more: '15분',
      max: '40분',
      path: '균형 있게',
      milestones: [],
    );
    final goal = store.goals.single;
    await store.complete(goal, 'MORE');
    await store.archiveGoal(goal);
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GrowUpApp(store: store));
    await tester.tap(find.text('기록').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('독서'), 250);
    expect(find.text('보관한 목표의 기록'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('독서')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('독서'));
    await tester.pumpAndSettle();
    expect(find.textContaining('보관 중'), findsOneWidget);
    expect(find.text('목표 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling guardian rename closes without a framework error', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final store = GrowthStore(SharedPreferencesAsync());
    await tester.pumpWidget(
      MaterialApp(home: GuardianDetailPage(store: store)),
    );
    await tester.tap(find.byTooltip('이름 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('이름 바꾸기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '별이');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(store.guardianName, '별이');
    expect(tester.takeException(), isNull);
  });
}

class _FakeRoadmapGenerator implements RoadmapGenerator {
  int calls = 0;

  @override
  Future<List<RoadmapPlan>> generate(RoadmapRequest request) async {
    if (++calls == 1) {
      throw const RoadmapGenerationException('임시 오류');
    }
    return [
      for (final (title, days, minutes) in [
        ('가벼운 안', 2, 60),
        ('균형 안', 3, 90),
        ('집중 안', 5, 120),
      ])
        RoadmapPlan(
          source: 'ai',
          title: title,
          summary: '첫 주부터 독서 습관을 만들어요.',
          durationWeeks: 8,
          weeklyTarget: days,
          weeklyMinutes: minutes,
          milestones: ['첫 책', '두 번째 책'],
          firstWeekActions: ['책 2쪽 읽기'],
        ),
    ];
  }
}

class _FakeAuthGateway implements AuthGateway {
  final _changes = StreamController<String?>.broadcast();
  @override
  String? get currentUserId => currentUserEmail == null ? null : 'test-user';
  @override
  String? currentUserEmail;
  @override
  String? currentDisplayName;
  @override
  DateTime? get currentUserCreatedAt => DateTime.utc(2026, 11, 5);
  String? lastCodeEmail;
  Object? sendError;
  int deleteCalls = 0;

  @override
  Stream<String?> get authChanges => _changes.stream;

  @override
  Future<String?> accessToken() async =>
      currentUserEmail == null ? null : 'jwt';

  @override
  Future<void> sendEmailCode(String email) async {
    if (sendError != null) throw sendError!;
    lastCodeEmail = email;
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    if (code != '123456') throw StateError('Bad code');
    currentUserEmail = email;
    _changes.add(email);
  }

  @override
  Future<bool> signUpWithPassword(String email, String password) async => false;
  @override
  Future<void> confirmSignUp(String email, String code) async {}
  @override
  Future<void> signInWithPassword(String email, String password) async {}
  @override
  Future<void> signInWithSocial(SocialProvider provider) async {}
  @override
  Future<Set<SocialProvider>> availableSocialProviders() async => {};

  @override
  Future<void> updateDisplayName(String name) async {
    currentDisplayName = name;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    currentUserEmail = null;
    _changes.add(null);
  }

  void simulateLinkSignIn(String email) {
    currentUserEmail = email;
    _changes.add(email);
  }

  @override
  Future<void> signOut() async {
    currentUserEmail = null;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
