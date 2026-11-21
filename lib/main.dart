import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_page.dart';
import 'app_date_picker.dart';
import 'activity_calendar.dart';
import 'backup_page.dart';
import 'daily_content_widgets.dart';
import 'game_page.dart';
import 'game_guide_page.dart';
import 'login_page.dart';
import 'models/growth_goal.dart';
import 'models/roadmap_draft.dart';
import 'models/roadmap_plan.dart';
import 'state/growth_store.dart';
import 'state/game_store.dart';
import 'state/auth_gateway.dart';
import 'state/goal_sync_service.dart';
import 'state/daily_sync_service.dart';
import 'state/roadmap_generator.dart';
import 'state/task_reminders.dart';
import 'state/weekly_statistics.dart';
import 'theme/app_palette.dart';
import 'focus_page.dart';

const softRadius = 10.0;

String _perPracticeDay(int minutes, int days) =>
    minutes < days ? '1분 미만' : '${(minutes / days).round()}분';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const aiEnabled = bool.fromEnvironment('ROADMAP_AI_ENABLED');
  const goalSyncEnabled = bool.fromEnvironment('GOAL_SYNC_ENABLED');
  const dailySyncEnabled = bool.fromEnvironment('DAILY_SYNC_ENABLED');
  const gameRemoteEnabled = bool.fromEnvironment('GAME_REMOTE_ENABLED');
  const gameDrawEnabled = bool.fromEnvironment('GAME_DRAW_ENABLED');
  const gameStageRewardsEnabled = bool.fromEnvironment(
    'GAME_STAGE_REWARDS_ENABLED',
  );
  const accountDeletionEnabled = bool.fromEnvironment(
    'ACCOUNT_DELETION_ENABLED',
  );
  AuthGateway? authGateway;
  RoadmapGenerator? roadmapGenerator;
  final prefs = SharedPreferencesAsync();
  if (supabaseUrl.isNotEmpty && publishableKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);
    authGateway = SupabaseAuthGateway(
      Supabase.instance.client,
      supabaseUrl: supabaseUrl,
      publishableKey: publishableKey,
    );
    if (aiEnabled) {
      roadmapGenerator = HttpRoadmapGenerator(
        endpoint: Uri.parse('$supabaseUrl/functions/v1/generate-roadmap'),
        accessToken: authGateway.accessToken,
        publishableKey: publishableKey,
        client: http.Client(),
      );
    }
  }
  final store = GrowthStore(prefs);
  await store.load();
  try {
    await taskReminderService.start(store);
  } catch (error) {
    debugPrint('Could not start task reminders: $error');
  }
  final gameStore = GameStore(prefs);
  await gameStore.load();
  final goalSyncService = authGateway == null || !goalSyncEnabled
      ? null
      : GoalSyncService(
          store: store,
          remote: SupabaseGoalSyncRemote(Supabase.instance.client),
          checkpoints: GoalSyncCheckpointStore(prefs),
          userId: () => authGateway?.currentUserId,
        );
  final dailySyncService = authGateway == null || !dailySyncEnabled
      ? null
      : DailySyncService(
          store: store,
          remote: SupabaseDailySyncRemote(Supabase.instance.client),
          checkpoints: DailySyncCheckpointStore(prefs),
          ownerBinding: GoalSyncCheckpointStore(prefs),
          userId: () => authGateway?.currentUserId,
        );
  final gameRemoteClient = authGateway == null || !gameRemoteEnabled
      ? null
      : Supabase.instance.client;
  runApp(
    GrowUpApp(
      store: store,
      gameStore: gameStore,
      authGateway: authGateway,
      goalSyncService: goalSyncService,
      dailySyncService: dailySyncService,
      gameRemoteClient: gameRemoteClient,
      gameDrawEnabled: gameDrawEnabled,
      gameStageRewardsEnabled: gameStageRewardsEnabled,
      accountDeletionEnabled: accountDeletionEnabled,
      roadmapGenerator: roadmapGenerator,
      showAuthOnLaunch: true,
    ),
  );
}

class GrowUpApp extends StatelessWidget {
  GrowUpApp({
    super.key,
    required this.store,
    GameStore? gameStore,
    this.authGateway,
    this.goalSyncService,
    this.dailySyncService,
    this.gameRemoteClient,
    this.gameDrawEnabled = false,
    this.gameStageRewardsEnabled = false,
    this.accountDeletionEnabled = false,
    this.roadmapGenerator,
    this.showAuthOnLaunch = false,
  }) : gameStore = gameStore ?? GameStore(SharedPreferencesAsync());
  final GrowthStore store;
  final GameStore gameStore;
  final AuthGateway? authGateway;
  final GoalSyncService? goalSyncService;
  final DailySyncService? dailySyncService;
  final SupabaseClient? gameRemoteClient;
  final bool gameDrawEnabled;
  final bool gameStageRewardsEnabled;
  final bool accountDeletionEnabled;
  final RoadmapGenerator? roadmapGenerator;
  final bool showAuthOnLaunch;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: '전설키우기',
      debugShowCheckedModeBanner: false,
      themeMode: store.darkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: _appTheme(AppPalette.light, Brightness.light),
      darkTheme: _appTheme(AppPalette.dark, Brightness.dark),
      home: StartupGate(
        showAuthOnLaunch: showAuthOnLaunch,
        auth: authGateway,
        child: AppShell(
          store: store,
          gameStore: gameStore,
          authGateway: authGateway,
          goalSyncService: goalSyncService,
          dailySyncService: dailySyncService,
          gameRemoteClient: gameRemoteClient,
          gameDrawEnabled: gameDrawEnabled,
          gameStageRewardsEnabled: gameStageRewardsEnabled,
          accountDeletionEnabled: accountDeletionEnabled,
          roadmapGenerator: roadmapGenerator,
        ),
      ),
    ),
  );
}

class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.showAuthOnLaunch,
    required this.auth,
    required this.child,
  });

  final bool showAuthOnLaunch;
  final AuthGateway? auth;
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool entered = false;

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    if (widget.showAuthOnLaunch &&
        !entered &&
        auth != null &&
        auth.currentUserId == null) {
      return LoginPage(
        auth: auth,
        onComplete: () => setState(() => entered = true),
        onGuest: () => setState(() => entered = true),
      );
    }
    return widget.child;
  }
}

ThemeData _appTheme(AppPalette colors, Brightness brightness) => ThemeData(
  useMaterial3: true,
  brightness: brightness,
  scaffoldBackgroundColor: colors.paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: colors.pine,
    brightness: brightness,
    surface: colors.card,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: colors.paper,
    foregroundColor: colors.ink,
    surfaceTintColor: Colors.transparent,
  ),
  cardTheme: CardThemeData(
    color: colors.card,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(softRadius),
      side: BorderSide(color: colors.line),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: colors.card,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: colors.nav,
    indicatorColor: colors.selected,
    indicatorShape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(softRadius)),
    ),
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontWeight: FontWeight.w700),
    ),
  ),
  navigationRailTheme: NavigationRailThemeData(backgroundColor: colors.nav),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(softRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(softRadius),
      ),
      side: BorderSide(color: colors.line),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(softRadius)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(softRadius)),
      borderSide: BorderSide(color: colors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(softRadius)),
      borderSide: BorderSide(color: colors.pine, width: 2),
    ),
    filled: true,
    fillColor: colors.card,
  ),
  textTheme: TextTheme(
    headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: colors.ink),
    titleLarge: TextStyle(fontWeight: FontWeight.w800, color: colors.ink),
    titleMedium: TextStyle(fontWeight: FontWeight.w700, color: colors.ink),
  ),
);

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.gameStore,
    this.authGateway,
    this.goalSyncService,
    this.dailySyncService,
    this.gameRemoteClient,
    this.gameDrawEnabled = false,
    this.gameStageRewardsEnabled = false,
    this.accountDeletionEnabled = false,
    this.roadmapGenerator,
  });
  final GrowthStore store;
  final GameStore gameStore;
  final AuthGateway? authGateway;
  final GoalSyncService? goalSyncService;
  final DailySyncService? dailySyncService;
  final SupabaseClient? gameRemoteClient;
  final bool gameDrawEnabled;
  final bool gameStageRewardsEnabled;
  final bool accountDeletionEnabled;
  final RoadmapGenerator? roadmapGenerator;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int section = 0;
  bool gameMode = false;
  Timer? _dayTimer;

  void _scheduleDayRefresh() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(
      next.difference(now) + const Duration(milliseconds: 100),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleDayRefresh();
      },
    );
  }

  void _openAccount() {
    final auth = widget.authGateway;
    if (auth == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(
          auth: auth,
          store: widget.store,
          gameStore: widget.gameStore,
          goalSyncService: widget.goalSyncService,
          dailySyncService: widget.dailySyncService,
          serverGameAvailable: widget.gameRemoteClient != null,
          accountDeletionEnabled: widget.accountDeletionEnabled,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    taskReminderService.tappedTaskId.addListener(_handleReminderTap);
    _scheduleDayRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleReminderTap());
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    taskReminderService.tappedTaskId.removeListener(_handleReminderTap);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleReminderTap() {
    final taskId = taskReminderService.tappedTaskId.value;
    if (!mounted || taskId == null) return;
    taskReminderService.tappedTaskId.value = null;
    setState(() {
      section = 0;
      gameMode = false;
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showReminderTask(taskId),
    );
  }

  Future<void> _showReminderTask(String taskId) async {
    if (!mounted) return;
    final task = widget.store.tasks
        .where((entry) => entry.id == taskId)
        .firstOrNull;
    if (task == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('알림의 할 일을 찾을 수 없어요.')));
      return;
    }
    final details = [
      if (task.scheduledDay != null) '예정 날짜 · ${task.scheduledDay}',
      if (task.scheduledTime != null) '예정 시간 · ${task.scheduledTime}',
      if (task.repeats) '반복 할 일',
      if (task.archived) '보관한 할 일',
      if (task.completedDay != null) '완료 날짜 · ${task.completedDay}',
    ];
    final edit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림의 할 일'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleMedium),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(details.join('\n')),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('할 일 수정'),
          ),
        ],
      ),
    );
    if (edit == true && mounted) {
      await editChecklistTask(context, widget.store, task);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleDayRefresh();
    }
  }

  Future<void> addGoal() async {
    if (widget.store.goals.length >= 5) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('진행 중인 목표는 최대 5개예요.')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: AppPalette.of(context).paper,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: GoalForm(
          store: widget.store,
          authGateway: widget.authGateway,
          roadmapGenerator: widget.roadmapGenerator,
        ),
      ),
    );
  }

  Future<int> _awardTraining(String sourceId) async {
    try {
      return await widget.gameStore.creditRewards(
        widget.store.rewardCandidates.where(
          (candidate) => candidate.sourceId == sourceId,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('훈련권을 저장하지 못했어요. 게임 화면을 다시 열어 주세요.')),
        );
      }
      return -1;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 820;
      final compactToolbar =
          !wide &&
          (MediaQuery.sizeOf(context).width < 340 ||
              MediaQuery.textScalerOf(context).scale(20) >= 30);
      final content = gameMode
          ? GamePage(
              gameStore: widget.gameStore,
              growthStore: widget.store,
              gameRemoteClient: widget.gameRemoteClient,
              onOpenAccount: _openAccount,
              gameDrawEnabled: widget.gameDrawEnabled,
              gameStageRewardsEnabled: widget.gameStageRewardsEnabled,
            )
          : switch (section) {
              0 => TodayPage(
                store: widget.store,
                onAdd: addGoal,
                onPractice: () => setState(() => section = 1),
                onAwardTraining: _awardTraining,
                onOpenGame: () => setState(() => gameMode = true),
              ),
              1 => GoalsPage(
                store: widget.store,
                onAdd: addGoal,
                onAwardTraining: _awardTraining,
                onOpenGame: () => setState(() => gameMode = true),
              ),
              _ => GrowthPage(store: widget.store, gameStore: widget.gameStore),
            };
      return Scaffold(
        appBar: AppBar(
          titleSpacing: compactToolbar ? 8 : 12,
          backgroundColor: gameMode
              ? AppPalette.light.guardian
              : AppPalette.of(context).paper,
          foregroundColor: gameMode ? Colors.white : AppPalette.of(context).ink,
          title: Text(
            gameMode ? '신수의 영역' : '전설키우기',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compactToolbar ? 17 : null,
            ),
          ),
          actions: [
            if (gameMode)
              IconButton(
                tooltip: '게임 즐기는 법',
                icon: const Icon(Icons.help_outline),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GameGuidePage(),
                  ),
                ),
              ),
            if (!gameMode && compactToolbar)
              PopupMenuButton<String>(
                tooltip: '설정 더 보기',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'account') {
                    _openAccount();
                  } else if (value == 'theme') {
                    widget.store.setDarkTheme(!widget.store.darkTheme);
                  }
                },
                itemBuilder: (context) => [
                  if (widget.authGateway != null)
                    const PopupMenuItem(value: 'account', child: Text('계정')),
                  PopupMenuItem(
                    value: 'theme',
                    child: Text(widget.store.darkTheme ? '밝은 테마' : '어두운 테마'),
                  ),
                ],
              ),
            if (!gameMode && !compactToolbar && widget.authGateway != null)
              IconButton(
                onPressed: _openAccount,
                icon: const Icon(Icons.person_outline),
                tooltip: '계정',
              ),
            if (!gameMode && !compactToolbar)
              IconButton(
                onPressed: () =>
                    widget.store.setDarkTheme(!widget.store.darkTheme),
                icon: Icon(
                  widget.store.darkTheme
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                tooltip: widget.store.darkTheme ? '밝은 테마' : '어두운 테마',
              ),
            Padding(
              padding: EdgeInsets.only(right: compactToolbar ? 8 : 12),
              child: FilledButton.icon(
                onPressed: () => setState(() => gameMode = !gameMode),
                icon: Icon(gameMode ? Icons.arrow_back : Icons.sports_esports),
                label: Text(gameMode ? '성장' : '게임'),
                style: FilledButton.styleFrom(
                  backgroundColor: gameMode
                      ? Colors.white
                      : AppPalette.of(context).guardian,
                  foregroundColor: gameMode
                      ? AppPalette.light.guardian
                      : Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: compactToolbar ? 8 : 12,
                    vertical: 9,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: wide && !gameMode
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: section,
                    onDestinationSelected: (index) =>
                        setState(() => section = index),
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.today_outlined),
                        selectedIcon: Icon(Icons.today),
                        label: Text('오늘'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.flag_outlined),
                        selectedIcon: Icon(Icons.flag),
                        label: Text('실천'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.insights_outlined),
                        selectedIcon: Icon(Icons.insights),
                        label: Text('기록'),
                      ),
                    ],
                  ),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: wide || gameMode
            ? null
            : GrowthBottomBar(
                selected: section,
                onSelected: (index) => setState(() => section = index),
              ),
      );
    },
  );
}

class GrowthBottomBar extends StatelessWidget {
  const GrowthBottomBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.today_outlined, '오늘'),
      (Icons.flag_outlined, '실천'),
      (Icons.insights_outlined, '기록'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 5),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppPalette.of(context).nav,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppPalette.of(context).line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final active = index == selected;
            return Expanded(
              child: Material(
                color: active
                    ? AppPalette.of(context).guardian
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onSelected(index),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            items[index].$1,
                            size: 20,
                            color: active
                                ? Colors.white
                                : AppPalette.of(context).muted,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items[index].$2,
                            style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : AppPalette.of(context).muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

Widget pageFrame(List<Widget> children) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 940),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: children,
    ),
  ),
);

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppPalette.of(context).card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(softRadius),
      side: BorderSide(color: AppPalette.of(context).line),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.onAdd,
    required this.onPractice,
    this.onAwardTraining,
    this.onOpenGame,
  });
  final GrowthStore store;
  final VoidCallback onAdd;
  final VoidCallback onPractice;
  final Future<int> Function(String sourceId)? onAwardTraining;
  final VoidCallback? onOpenGame;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final largeText = MediaQuery.textScalerOf(context).scale(18) >= 27;
    final questCount =
        '${store.todayDone}/${store.goals.length} 완료${store.todayRest > 0 ? ' · ${store.todayRest} 휴식' : ''}';
    return pageFrame([
      Text(
        '${now.month}월 ${now.day}일 · 오늘',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      GuardianCard(store: store),
      const SizedBox(height: 22),
      if (largeText) ...[
        Text('오늘의 퀘스트', style: Theme.of(context).textTheme.titleLarge),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            questCount,
            style: TextStyle(
              color: AppPalette.of(context).pine,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ] else
        Row(
          children: [
            Expanded(
              child: Text(
                '오늘의 퀘스트',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              questCount,
              style: TextStyle(
                color: AppPalette.of(context).pine,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      const SizedBox(height: 12),
      if (store.goals.isEmpty)
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.flag_circle_outlined,
                color: AppPalette.of(context).pine,
                size: 35,
              ),
              const SizedBox(height: 12),
              Text(
                '첫 목표를 정해 볼까요?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 7),
              const Text('지금 키우고 싶은 것을 적고 아주 작게 시작해 보세요.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('목표 만들기'),
              ),
            ],
          ),
        )
      else
        ...store.goals.map(
          (goal) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TodayGoalSummary(
              goal: goal,
              store: store,
              onTap: onPractice,
            ),
          ),
        ),
      if (store.goals.isNotEmpty)
        OutlinedButton.icon(
          onPressed: onPractice,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('실천 화면에서 선택하기'),
        ),
      const SizedBox(height: 24),
      TodayChecklist(
        store: store,
        onAwardTraining: onAwardTraining,
        onOpenGame: onOpenGame,
      ),
      if (store.goals.isNotEmpty) ...[
        const SizedBox(height: 20),
        WeeklyPulse(store: store),
      ],
    ]);
  }
}

class WeeklyPulse extends StatelessWidget {
  const WeeklyPulse({super.key, required this.store});

  final GrowthStore store;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final today = DateTime.now();
    final weekStart = startOfWeek(today);
    final goals = [...store.goals, ...store.archivedGoals];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이번 주의 걸음', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 3),
          Text(
            '쉰 날도 기록이에요. 월별 달력은 기록 탭에 있어요.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(7, (index) {
              final date = weekStart.add(Duration(days: index));
              final key = dayKey(date);
              final done = goals.where((goal) => goal.isDoneOn(key)).length;
              final rested = goals.any((goal) => goal.restDays.contains(key));
              final future = date.isAfter(
                DateTime(today.year, today.month, today.day),
              );
              final todayCell =
                  date.day == today.day && date.month == today.month;
              return Expanded(
                child: Semantics(
                  label: future
                      ? '${date.month}월 ${date.day}일, 아직 오지 않은 날'
                      : '${date.month}월 ${date.day}일, 실천 $done개${rested ? ', 쉼' : ''}',
                  child: Column(
                    children: [
                      Text(
                        const ['월', '화', '수', '목', '금', '토', '일'][index],
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: done > 0
                              ? palette.pine
                              : future
                              ? palette.subtle.withValues(alpha: .45)
                              : palette.subtle,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: todayCell
                                ? palette.more
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: done > 0
                                ? Colors.white
                                : future
                                ? palette.muted.withValues(alpha: .55)
                                : palette.ink,
                            fontSize: 11,
                            fontWeight: todayCell
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        done > 0
                            ? Icons.check
                            : rested
                            ? Icons.remove
                            : Icons.circle,
                        size: done > 0 || rested ? 12 : 4,
                        color: future
                            ? Colors.transparent
                            : done > 0
                            ? palette.pine
                            : palette.muted,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class TodayGoalSummary extends StatelessWidget {
  const TodayGoalSummary({
    super.key,
    required this.goal,
    required this.store,
    required this.onTap,
  });
  final GrowthGoal goal;
  final GrowthStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = goal.completions[store.today];
    final resting = goal.restDays.contains(store.today);
    final restart = (store.daysSinceLastPractice(goal) ?? 0) >= 2;
    final label = resting
        ? '오늘은 쉬는 날'
        : level == null
        ? '${restart ? '다시 시작 · ' : '아직 실천 전 · '}MINI: ${goal.mini}'
        : '${switch (level) {
            '쉬움' => 'MINI',
            '보통' => 'MORE',
            '도전' => 'MAX',
            _ => level,
          }} 완료';
    return Material(
      color: AppPalette.of(context).card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(softRadius),
        side: BorderSide(color: AppPalette.of(context).line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(softRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(
                resting
                    ? Icons.bedtime_outlined
                    : level == null
                    ? Icons.radio_button_unchecked
                    : Icons.check_circle,
                color: resting
                    ? AppPalette.of(context).muted
                    : AppPalette.of(context).pine,
                size: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppPalette.of(context).pine),
            ],
          ),
        ),
      ),
    );
  }
}

class GuardianCard extends StatelessWidget {
  const GuardianCard({super.key, required this.store});
  final GrowthStore store;

  @override
  Widget build(BuildContext context) {
    const names = ['태동', '각성', '초월'];
    final largeText = MediaQuery.textScalerOf(context).scale(12) >= 18;
    const images = [
      'assets/concept/guardian-taedong-v2.png',
      'assets/concept/guardian-gakseong-v2.png',
      'assets/concept/guardian-chowol-v2.png',
    ];
    return Material(
      color: AppPalette.of(context).guardian,
      borderRadius: BorderRadius.circular(softRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(softRadius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GuardianDetailPage(store: store),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            children: [
              Container(
                width: largeText ? 82 : 130,
                height: largeText ? 96 : 128,
                decoration: BoxDecoration(
                  color: AppPalette.of(context).guardianInset,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    images[store.guardianStage],
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              ),
              SizedBox(width: largeText ? 10 : 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'LV ${store.level} · ${names[store.guardianStage]}',
                      style: TextStyle(
                        color: AppPalette.of(context).aqua,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      store.guardianName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        store.guardianReaction,
                        key: ValueKey(store.guardianReaction),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppPalette.of(context).guardianText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value:
                          store.experienceInLevel /
                          GrowthStore.experiencePerLevel,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      color: AppPalette.of(context).aqua,
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Text(
                          '상태 보기',
                          style: TextStyle(
                            color: AppPalette.of(context).guardianText,
                            fontSize: 12,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppPalette.of(context).aqua,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GuardianDetailPage extends StatelessWidget {
  const GuardianDetailPage({super.key, required this.store});
  final GrowthStore store;

  Future<void> _rename(BuildContext context) async {
    var draftName = store.guardianName;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('동료 이름 바꾸기'),
        content: TextFormField(
          initialValue: store.guardianName,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(labelText: '새 이름'),
          onChanged: (text) => draftName = text,
          onFieldSubmitted: (text) => Navigator.pop(dialogContext, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draftName),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (value != null) await store.setGuardianName(value);
  }

  @override
  Widget build(BuildContext context) {
    const stages = ['태동', '각성', '초월'];
    const images = [
      'assets/concept/guardian-taedong-v2.png',
      'assets/concept/guardian-gakseong-v2.png',
      'assets/concept/guardian-chowol-v2.png',
    ];
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('동료 상태')),
        body: pageFrame([
          Container(
            decoration: BoxDecoration(
              color: AppPalette.of(context).guardian,
              borderRadius: BorderRadius.circular(softRadius),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Image.asset(
                  images[store.guardianStage],
                  height: 250,
                  filterQuality: FilterQuality.none,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        store.guardianName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _rename(context),
                      tooltip: '이름 바꾸기',
                      icon: Icon(
                        Icons.edit_outlined,
                        color: AppPalette.of(context).aqua,
                        size: 19,
                      ),
                    ),
                  ],
                ),
                Text(
                  '별여우 · ${stages[store.guardianStage]} · LV ${store.level}',
                  style: TextStyle(color: AppPalette.of(context).guardianText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '성장 상태',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      'LV ${store.level}',
                      style: TextStyle(
                        color: AppPalette.of(context).pine,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value:
                      store.experienceInLevel / GrowthStore.experiencePerLevel,
                  minHeight: 7,
                  color: AppPalette.of(context).pine,
                  backgroundColor: AppPalette.of(context).subtle,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 8),
                Text(
                  'XP ${store.experienceInLevel}/${GrowthStore.experiencePerLevel} · MINI +10 / MORE +20 / MAX +30',
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        '지속력',
                        '${store.activeDays}',
                        '실천한 날',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _stat(
                        context,
                        '실행력',
                        '${store.totalCompletedDays}',
                        '완료한 행동',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        '도전력',
                        '${store.maxCompletions}',
                        'MAX 완료',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _stat(
                        context,
                        '개척력',
                        '${store.completedMilestoneCount}',
                        '로드맵 단계',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '능력치는 실제 실천 기록을 보여줍니다. 레벨과 진화 조건은 시제품 규칙입니다.',
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('진화의 길', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _stageRow(context, '태동', '처음부터 함께', true),
                _stageRow(context, '각성', '실천한 날 5일', store.activeDays >= 5),
                _stageRow(context, '초월', '실천한 날 15일', store.activeDays >= 15),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '함께할 신수',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                SizedBox(height: 8),
                Text(
                  '현재는 별여우 한 종만 준비되어 있어요. 다른 신수가 추가되면 여기서 변경할 수 있습니다.',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value,
    String explanation,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppPalette.of(context).subtle,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppPalette.of(context).line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: AppPalette.of(context).ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          explanation,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _stageRow(
    BuildContext context,
    String stage,
    String condition,
    bool unlocked,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Icon(
          unlocked ? Icons.auto_awesome : Icons.lock_outline,
          size: 18,
          color: unlocked
              ? AppPalette.of(context).pine
              : AppPalette.of(context).muted,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            stage,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          condition,
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class QuestCard extends StatelessWidget {
  const QuestCard({
    super.key,
    required this.goal,
    required this.store,
    this.showPlan = false,
    this.onAwardTraining,
    this.onOpenGame,
  });
  final GrowthGoal goal;
  final GrowthStore store;
  final bool showPlan;
  final Future<int> Function(String sourceId)? onAwardTraining;
  final VoidCallback? onOpenGame;

  @override
  Widget build(BuildContext context) {
    final selected = goal.completions[store.today];
    final resting = goal.restDays.contains(store.today);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (showPlan)
                IconButton(
                  onPressed: () => _editSettings(context),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '목표 수정',
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (resting) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppPalette.of(context).subtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bedtime_outlined,
                    color: AppPalette.of(context).muted,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '오늘은 쉬는 날로 기록했어요. 편하게 쉬어도 돼요.',
                      style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => store.clearRest(goal),
                child: const Text('다시 실천하기'),
              ),
            ),
          ] else if (selected != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppPalette.of(context).completed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: AppPalette.of(context).pine),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '오늘 ${_displayLevel(selected)} 완료!',
                      style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _changeLevel(context),
                  child: const Text('기록 수정'),
                ),
                if (_displayLevel(selected) != 'MAX')
                  FilledButton.tonal(
                    onPressed: () => _changeLevel(context, upgradeOnly: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.of(context).mini,
                      foregroundColor: AppPalette.of(context).pine,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: const Text('더 했어요'),
                  ),
              ],
            ),
          ] else ...[
            if ((store.daysSinceLastPractice(goal) ?? 0) >= 2)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).mini,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '며칠 비워도 괜찮아요. 오늘은 MINI만 해도 충분해요.',
                  style: TextStyle(
                    color: AppPalette.of(context).ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Text(
                '오늘 할 수 있는 만큼 선택해요. 작은 행동도 완료예요.',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _chooseCompletion(context),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('완료하기'),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final record = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => FocusPage(
                      goalId: goal.id,
                      title: goal.title,
                      action: goal.mini,
                    ),
                  ),
                );
                if (record == true &&
                    context.mounted &&
                    !goal.isDoneOn(store.today)) {
                  await _chooseCompletion(context);
                }
              },
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('2분부터 집중하기'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => store.rest(goal),
                icon: const Icon(Icons.bedtime_outlined, size: 17),
                label: const Text('오늘 쉬기'),
              ),
            ),
          ],
          if (showPlan) ...[
            const Divider(height: 22),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => GoalHistoryPage(goal: goal, store: store),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('목표 상세보기'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => GoalRoadmapPage(goal: goal, store: store),
                ),
              ),
              icon: const Icon(Icons.route_outlined, size: 17),
              label: Text(
                '로드맵 ${goal.completedMilestones.length}/${goal.milestones.length} · 관리',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _displayLevel(String value) => switch (value) {
    '쉬움' => 'MINI',
    '보통' => 'MORE',
    '도전' => 'MAX',
    _ => value,
  };

  Future<void> _chooseCompletion(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘은 얼마나 했나요?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '한 가지만 고르면 오늘의 실천으로 기록돼요.',
                    style: TextStyle(color: AppPalette.of(context).muted),
                  ),
                  const SizedBox(height: 16),
                  _level(
                    context,
                    'MINI',
                    '가볍게 · XP +10',
                    goal.mini,
                    AppPalette.of(context).mini,
                    () => Navigator.pop(sheetContext),
                  ),
                  _level(
                    context,
                    'MORE',
                    '평소처럼 · XP +20',
                    goal.more,
                    AppPalette.of(context).more,
                    () => Navigator.pop(sheetContext),
                  ),
                  _level(
                    context,
                    'MAX',
                    '여유 있게 · XP +30',
                    goal.max,
                    AppPalette.of(context).max,
                    () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _level(
    BuildContext context,
    String code,
    String caption,
    String action,
    Color color,
    VoidCallback closeSheet,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final beforeXp = store.experience;
          await store.complete(goal, code);
          closeSheet();
          if (onAwardTraining == null) return;
          final passes = await onAwardTraining!(
            'goal:${goal.id}:${store.today}',
          );
          if (passes < 0) return;
          final xp = store.experience - beforeXp;
          if (context.mounted &&
              store.showGameRewards &&
              (passes > 0 || xp != 0)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '실천 기록 · XP ${xp >= 0 ? '+' : ''}$xp · 훈련 +$passes',
                ),
                persist: false,
                action: onOpenGame == null
                    ? null
                    : SnackBarAction(label: '게임으로', onPressed: onOpenGame!),
              ),
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppPalette.of(context).line, width: 1),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code,
                      style: TextStyle(
                        color: AppPalette.of(context).pine,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      caption,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  action,
                  style: TextStyle(
                    color: AppPalette.of(context).ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.add_circle_outline,
                color: AppPalette.of(context).pine,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _changeLevel(BuildContext context, {bool upgradeOnly = false}) {
    final levels = [
      ('MINI', goal.mini),
      ('MORE', goal.more),
      ('MAX', goal.max),
    ];
    final current = _displayLevel(goal.completions[store.today] ?? '');
    final currentIndex = levels.indexWhere((item) => item.$1 == current);
    final options = upgradeOnly ? levels.skip(currentIndex + 1) : levels;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              upgradeOnly ? '오늘 조금 더 했나요?' : '오늘의 기록 수정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (final (level, action) in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  level,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(action),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await store.complete(goal, level);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            if (!upgradeOnly)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '기록을 취소하면 XP는 다시 계산돼요. 이미 받은 훈련권은 유지되고 같은 날 다시 실천해도 중복 지급되지 않아요.',
                ),
              ),
            if (!upgradeOnly)
              TextButton(
                onPressed: () async {
                  await store.undo(goal);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('오늘 기록 취소'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => GoalActionEditor(goal: goal, store: store),
  );

  Future<void> _editSettings(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: AppPalette.of(context).paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) => GoalSettingsEditor(
          goal: goal,
          store: store,
          onEditActions: () {
            Navigator.of(sheetContext).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) _edit(context);
            });
          },
          onArchive: () async {
            final archived = await _archive(sheetContext);
            if (archived && sheetContext.mounted) Navigator.pop(sheetContext);
          },
        ),
      );

  Future<bool> _archive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppPalette.of(dialogContext).card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            key: const ValueKey('archive-dialog-content'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '목표 보관',
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '목록에서 숨겨요. 기록은 남아요.',
                  style: TextStyle(
                    color: AppPalette.of(dialogContext).muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('보관'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return false;
    await store.archiveGoal(goal);
    return true;
  }
}

class GoalSettingsEditor extends StatefulWidget {
  const GoalSettingsEditor({
    super.key,
    required this.goal,
    required this.store,
    required this.onEditActions,
    required this.onArchive,
  });

  final GrowthGoal goal;
  final GrowthStore store;
  final VoidCallback onEditActions;
  final Future<void> Function() onArchive;

  @override
  State<GoalSettingsEditor> createState() => _GoalSettingsEditorState();
}

class _GoalSettingsEditorState extends State<GoalSettingsEditor> {
  late final title = TextEditingController(text: widget.goal.title);
  late final currentLevel = TextEditingController(
    text: widget.goal.currentLevel,
  );
  late final weeklyMinutes = TextEditingController(
    text: widget.goal.weeklyMinutes?.toString() ?? '',
  );
  late DateTime startDate = DateTime.parse(widget.goal.startDay);
  late DateTime? targetDate = DateTime.tryParse(widget.goal.targetDate ?? '');
  late String path = widget.goal.path;
  late int weeklyTarget = widget.goal.weeklyTarget;
  String? error;
  String? minutesError;

  @override
  void dispose() {
    title.dispose();
    currentLevel.dispose();
    weeklyMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showAppDatePicker(
      context: context,
      title: '목표 시작일',
      initialDate: startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        startDate = picked;
        if (targetDate != null && targetDate!.isBefore(picked)) {
          targetDate = null;
        }
      });
    }
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      title: '목표 종료일',
      initialDate: targetDate ?? (startDate.isAfter(now) ? startDate : now),
      firstDate: startDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null) setState(() => targetDate = picked);
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = '목표 이름을 적어 주세요.');
      return;
    }
    final minutes = weeklyMinutes.text.trim().isEmpty
        ? 0
        : int.tryParse(weeklyMinutes.text.trim());
    if (minutes == null || minutes < 0 || minutes > 10080) {
      setState(() => minutesError = '분 단위 숫자로 적어 주세요.');
      return;
    }
    final saved = await widget.store.updateGoalSettings(
      widget.goal,
      title: title.text,
      path: path,
      weeklyTarget: weeklyTarget,
      currentLevel: currentLevel.text,
      startDate: dayKey(startDate),
      targetDate: targetDate == null ? '' : dayKey(targetDate!),
      weeklyMinutes: minutes,
    );
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('목표와 주간 계획', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: title,
            maxLength: 60,
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            decoration: InputDecoration(labelText: '목표 이름', errorText: error),
          ),
          const SizedBox(height: 8),
          Text('진행 속도', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in ['가볍게 시작', '균형 있게', '집중해서'])
                ChoiceChip(
                  label: Text(option),
                  selected: path == option,
                  showCheckmark: false,
                  selectedColor: AppPalette.of(context).selected,
                  backgroundColor: AppPalette.of(context).card,
                  side: BorderSide(color: AppPalette.of(context).line),
                  onSelected: (_) => setState(() {
                    path = option;
                    weeklyTarget = suggestedWeeklyTarget(option);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '일주일에 몇 번 실천할까요?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'MINI도 하루 실천으로 셉니다. 못한 날에 벌점은 없어요.',
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var count = 1; count <= 7; count++)
                ChoiceChip(
                  label: Text('$count일'),
                  selected: weeklyTarget == count,
                  showCheckmark: false,
                  selectedColor: AppPalette.of(context).selected,
                  backgroundColor: AppPalette.of(context).card,
                  side: BorderSide(color: AppPalette.of(context).line),
                  onSelected: (_) => setState(() => weeklyTarget = count),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('로드맵을 위한 정보', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: currentLevel,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: '현재 수준 (선택)',
              hintText: '예: 이제 막 시작했어요',
            ),
          ),
          TextField(
            controller: weeklyMinutes,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (minutesError != null) setState(() => minutesError = null);
            },
            decoration: InputDecoration(
              labelText: '일주일에 쓸 수 있는 시간 · 분 (선택)',
              hintText: '예: 120',
              errorText: minutesError,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickStartDate,
            icon: const Icon(Icons.event_available_outlined),
            label: Text('시작일 · ${dayKey(startDate)}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickTargetDate,
            icon: const Icon(Icons.flag_outlined),
            label: Text(
              targetDate == null ? '종료일 선택' : '종료일 · ${dayKey(targetDate!)}',
            ),
          ),
          if (targetDate != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => targetDate = null),
                child: const Text('종료일 지우기'),
              ),
            ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: widget.onEditActions,
            icon: const Icon(Icons.tune_outlined),
            label: const Text('MINI · MORE · MAX 행동 수정'),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _save, child: const Text('변경 저장')),
          ),
          const Divider(height: 32),
          TextButton.icon(
            onPressed: widget.onArchive,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('이 목표 보관하기'),
          ),
        ],
      ),
    ),
  );
}

class GoalActionEditor extends StatefulWidget {
  const GoalActionEditor({super.key, required this.goal, required this.store});
  final GrowthGoal goal;
  final GrowthStore store;

  @override
  State<GoalActionEditor> createState() => _GoalActionEditorState();
}

class _GoalActionEditorState extends State<GoalActionEditor> {
  late final mini = TextEditingController(text: widget.goal.mini);
  late final more = TextEditingController(text: widget.goal.more);
  late final max = TextEditingController(text: widget.goal.max);

  @override
  void dispose() {
    mini.dispose();
    more.dispose();
    max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if ([mini, more, max].any((controller) => controller.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('세 가지 행동을 모두 적어 주세요.')));
      return;
    }
    await widget.store.updateGoalActions(
      widget.goal,
      mini: mini.text,
      more: more.text,
      max: max.text,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('실천 단계 바꾸기', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(
            '상황에 맞춰 양을 조절해도 이미 쌓인 기록은 유지돼요.',
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: mini,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'MINI · 힘든 날에도 할 수 있는 양',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: more,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'MORE · 평소에 할 양'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: max,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'MAX · 여유 있는 날의 양'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('변경 저장')),
          ),
        ],
      ),
    ),
  );
}

class _MilestoneDetailText extends StatelessWidget {
  const _MilestoneDetailText({required this.detail, this.achieved = false});

  final MilestoneDetail detail;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    final lines = [
      if (detail.targetDate != null) '예상 완료 ${detail.targetDate}',
      if (detail.criteria.isNotEmpty) '완료 기준 · ${detail.criteria}',
      if (detail.method.isNotEmpty) '실천 방법 · ${detail.method}',
      if (detail.rewardIdea.isNotEmpty)
        achieved
            ? '달성한 나에게 주는 보상 · ${detail.rewardIdea}'
            : '달성하면 즐길 보상 · ${detail.rewardIdea}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).muted,
              ),
            ),
        ],
      ),
    );
  }
}

class MilestoneEditor extends StatefulWidget {
  const MilestoneEditor({
    super.key,
    required this.goal,
    required this.store,
    this.index,
  });

  final GrowthGoal goal;
  final GrowthStore store;
  final int? index;

  @override
  State<MilestoneEditor> createState() => _MilestoneEditorState();
}

class _MilestoneEditorState extends State<MilestoneEditor> {
  late final controller = TextEditingController(
    text: widget.index == null ? '' : widget.goal.milestones[widget.index!],
  );
  late final criteria = TextEditingController(
    text: widget.index == null
        ? ''
        : widget.goal.milestoneDetails[widget.index!].criteria,
  );
  late final method = TextEditingController(
    text: widget.index == null
        ? ''
        : widget.goal.milestoneDetails[widget.index!].method,
  );
  late final rewardIdea = TextEditingController(
    text: widget.index == null
        ? ''
        : widget.goal.milestoneDetails[widget.index!].rewardIdea,
  );
  late DateTime? targetDate = widget.index == null
      ? null
      : DateTime.tryParse(
          widget.goal.milestoneDetails[widget.index!].targetDate ?? '',
        );
  String? error;
  bool confirmDelete = false;

  @override
  void dispose() {
    controller.dispose();
    criteria.dispose();
    method.dispose();
    rewardIdea.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final defaultFirst = DateTime(now.year - 1);
    final defaultLast = DateTime(now.year + 10);
    final chosen = await showAppDatePicker(
      context: context,
      title: '이정표 예상 완료일',
      initialDate: targetDate ?? now,
      firstDate: targetDate != null && targetDate!.isBefore(defaultFirst)
          ? targetDate!
          : defaultFirst,
      lastDate: targetDate != null && targetDate!.isAfter(defaultLast)
          ? targetDate!
          : defaultLast,
    );
    if (chosen != null) setState(() => targetDate = chosen);
  }

  Future<void> _save() async {
    if (controller.text.trim().isEmpty) {
      setState(() => error = '단계 내용을 적어 주세요.');
      return;
    }
    final detail = MilestoneDetail(
      targetDate: targetDate == null ? null : dayKey(targetDate!),
      criteria: criteria.text.trim(),
      method: method.text.trim(),
      rewardIdea: rewardIdea.text.trim(),
    );
    final saved = widget.index == null
        ? await widget.store.addMilestone(
            widget.goal,
            controller.text,
            detail: detail,
          )
        : await widget.store.updateMilestone(
            widget.goal,
            widget.index!,
            controller.text,
            detail: detail,
          );
    if (mounted && saved) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final removed = await widget.store.removeMilestone(
      widget.goal,
      widget.index!,
    );
    if (mounted && removed) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.index == null ? '로드맵 단계 추가' : '로드맵 단계 수정',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            decoration: InputDecoration(
              labelText: '이정표',
              hintText: '예: 첫 책 한 권 끝내기',
              errorText: error,
            ),
          ),
          TextField(
            controller: criteria,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: '완료 기준 (선택)',
              hintText: '예: 책 한 권을 끝까지 읽고 한 문장으로 정리',
            ),
          ),
          TextField(
            controller: method,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '실천 방법 (선택)',
              hintText: '예: 평일에는 MINI, 주말에는 MORE로 이어가기',
            ),
          ),
          TextField(
            controller: rewardIdea,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: '달성 후 나에게 줄 보상 (선택)',
              hintText: '예: 좋아하는 음악 들으며 30분 쉬기',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickDate,
                  child: Text(
                    targetDate == null
                        ? '예상 완료일 선택 (선택)'
                        : '예상 완료일 ${dayKey(targetDate!)}',
                  ),
                ),
              ),
              if (targetDate != null)
                IconButton(
                  tooltip: '예상 완료일 지우기',
                  onPressed: () => setState(() => targetDate = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (confirmDelete)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.of(context).subtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('이 단계를 삭제할까요? 완료 표시도 함께 지워집니다.'),
            ),
          Row(
            children: [
              if (widget.index != null)
                TextButton(
                  onPressed: confirmDelete
                      ? _delete
                      : () => setState(() => confirmDelete = true),
                  child: Text(confirmDelete ? '삭제 확인' : '단계 삭제'),
                ),
              const Spacer(),
              if (confirmDelete)
                TextButton(
                  onPressed: () => setState(() => confirmDelete = false),
                  child: const Text('취소'),
                ),
              FilledButton(onPressed: _save, child: const Text('저장')),
            ],
          ),
        ],
      ),
    ),
  );
}

class GoalsPage extends StatelessWidget {
  const GoalsPage({
    super.key,
    required this.store,
    required this.onAdd,
    this.onAwardTraining,
    this.onOpenGame,
  });
  final GrowthStore store;
  final VoidCallback onAdd;
  final Future<int> Function(String sourceId)? onAwardTraining;
  final VoidCallback? onOpenGame;

  @override
  Widget build(BuildContext context) => pageFrame([
    Text('오늘의 실천', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 5),
    Text(
      '목표마다 MINI · MORE · MAX 중 오늘 가능한 만큼을 고르세요.',
      style: TextStyle(color: AppPalette.of(context).muted),
    ),
    const SizedBox(height: 20),
    if (store.goals.isEmpty)
      SurfaceCard(
        child: Column(
          children: [
            const Text('아직 진행 중인 목표가 없어요.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAdd, child: const Text('첫 목표 만들기')),
          ],
        ),
      )
    else
      ...store.goals.map(
        (goal) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: QuestCard(
            goal: goal,
            store: store,
            showPlan: true,
            onAwardTraining: onAwardTraining,
            onOpenGame: onOpenGame,
          ),
        ),
      ),
    if (store.goals.isNotEmpty && store.goals.length < 5)
      FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('새 목표 만들기'),
      ),
    if (store.archivedGoals.isNotEmpty) ...[
      const SizedBox(height: 24),
      Text('보관한 목표', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      ...store.archivedGoals.map(
        (goal) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SurfaceCard(
            child: Row(
              children: [
                Expanded(child: Text(goal.title)),
                TextButton(
                  onPressed: () async {
                    final restored = await store.restoreGoal(goal);
                    if (!restored && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('진행 중인 목표는 최대 5개예요. 먼저 하나를 보관해 주세요.'),
                        ),
                      );
                    }
                  },
                  child: const Text('다시 시작'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ]);
}

class WeeklyStatisticsPanel extends StatefulWidget {
  const WeeklyStatisticsPanel({super.key, required this.store});
  final GrowthStore store;

  @override
  State<WeeklyStatisticsPanel> createState() => _WeeklyStatisticsPanelState();
}

class _WeeklyStatisticsPanelState extends State<WeeklyStatisticsPanel> {
  int weekOffset = 0;

  Widget _statLine(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final start = WeeklyStatistics.mondayOf(DateTime.now())
          .add(Duration(days: weekOffset * 7));
      final stats = WeeklyStatistics.calculate(
        week: start,
        goals: widget.store.allGoals,
        tasks: widget.store.tasks,
      );
      final end = start.add(const Duration(days: 6));
      final reviews = WeeklyGoalReview.calculate(start, widget.store.allGoals);
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('주간 기록', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '실제로 남긴 기록만 셉니다.',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: '이전 주',
                  onPressed: () => setState(() => weekOffset--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${start.month}/${start.day}~${end.month}/${end.day}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '다음 주',
                  onPressed: weekOffset >= 0
                      ? null
                      : () => setState(() => weekOffset++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const Divider(height: 12),
            _statLine(context, '일회성 할 일', '${stats.oneOffDone}개'),
            _statLine(context, '반복 할 일', '${stats.repeatDone}회'),
            _statLine(context, '목표 실천', '${stats.goalPractices}회'),
            _statLine(context, '미룬 일정', '${stats.postponed}회'),
            _statLine(context, '다시 시작한 날', '${stats.restartDays.length}일'),
            if (stats.restartDays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '다시 시작한 날짜: ${stats.restartDays.join(', ')}',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '빈 날은 실패로 표시하지 않아요.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('목표별 돌아보기'),
              subtitle: const Text('내게 맞는 실천 크기와 다음 걸음 찾기'),
              children: [
                for (final review in reviews)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${review.goal.title} · 돌아보기'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '실천 ${review.practiceDays.length}일 · 쉼 ${review.restDays}일 · 현재 기준 주 ${review.goal.weeklyTarget}일',
                        ),
                        Text(
                          'MINI ${review.levels['MINI']} · MORE ${review.levels['MORE']} · MAX ${review.levels['MAX']}',
                        ),
                        Text(
                          review.practiceDays.isEmpty
                              ? '다음에는 MINI 한 번으로 시작해도 좋아요.'
                              : review.practiceDays.length >=
                                    review.goal.weeklyTarget
                              ? '내가 정한 주간 기준만큼 걸었어요.'
                              : '남긴 작은 실천도 성장 기록이에요.',
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GoalHistoryPage(
                          goal: review.goal,
                          store: widget.store,
                        ),
                      ),
                    ),
                  ),
                if (reviews.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('이 주에 돌아볼 목표가 없어요.'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class GrowthPage extends StatelessWidget {
  const GrowthPage({super.key, required this.store, this.gameStore});
  final GrowthStore store;
  final GameStore? gameStore;

  @override
  Widget build(BuildContext context) => pageFrame([
    Text('나의 기록', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 5),
    Text(
      '실천, 할 일, 생각을 날짜별로 돌아보세요.',
      style: TextStyle(color: AppPalette.of(context).muted),
    ),
    const SizedBox(height: 20),
    SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 260;
          if (compact) {
            return Column(
              children: [
                statRow(context, '${store.totalCompletedDays}', '실천 기록'),
                const Divider(height: 24),
                statRow(context, '${store.goals.length}', '진행 목표'),
                const Divider(height: 24),
                statRow(context, '${store.todayDone}', '오늘 완료'),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: stat(context, '${store.totalCompletedDays}', '실천 기록'),
              ),
              Expanded(child: stat(context, '${store.goals.length}', '진행 목표')),
              Expanded(child: stat(context, '${store.todayDone}', '오늘 완료')),
            ],
          );
        },
      ),
    ),
    const SizedBox(height: 22),
    WeeklyStatisticsPanel(store: store),
    const SizedBox(height: 22),
    DailyNotesPanel(store: store),
    const SizedBox(height: 22),
    Text('실천 단계', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    SurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: _tierStat(
              context,
              'MINI',
              store.countIntensity('MINI'),
              AppPalette.of(context).mini,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _tierStat(
              context,
              'MORE',
              store.countIntensity('MORE'),
              AppPalette.of(context).more,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _tierStat(
              context,
              'MAX',
              store.countIntensity('MAX'),
              AppPalette.of(context).max,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 22),
    Text('목표별 발자취', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    if (store.goals.isEmpty && store.archivedGoals.isEmpty)
      const SurfaceCard(child: Text('목표를 만들면 이곳에 기록이 쌓여요.'))
    else
      ...store.goals.map(
        (goal) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            child: InkWell(
              key: ValueKey('goal-history-${goal.id}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GoalHistoryPage(goal: goal, store: store),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_graph, color: AppPalette.of(context).pine),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '이번 주 ${store.completedDaysThisWeek(goal)}/${goal.weeklyTarget}일 · 누적 ${goal.completedDays}일',
                          style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value:
                              (store.completedDaysThisWeek(goal) /
                                      goal.weeklyTarget)
                                  .clamp(0.0, 1.0),
                          minHeight: 5,
                          color: AppPalette.of(context).pine,
                          backgroundColor: AppPalette.of(context).subtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: AppPalette.of(context).pine),
                ],
              ),
            ),
          ),
        ),
      ),
    if (store.archivedGoals.isNotEmpty) ...[
      const SizedBox(height: 16),
      Text('보관한 목표의 기록', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      ...store.archivedGoals.map(
        (goal) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GoalHistoryPage(goal: goal, store: store),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: AppPalette.of(context).muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '누적 실천 ${goal.completedDays}일 · 로드맵 ${goal.completedMilestones.length}/${goal.milestones.length}',
                          style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppPalette.of(context).pine),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    const SizedBox(height: 28),
    Text('실천 달력', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    SurfaceCard(child: ActivityCalendar(store: store)),
    const SizedBox(height: 28),
    OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BackupPage(store: store, gameStore: gameStore),
        ),
      ),
      icon: const Icon(Icons.save_alt),
      label: const Text('기록 백업·가져오기'),
    ),
  ]);

  Widget stat(BuildContext context, String value, String label) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(fontSize: 12, color: AppPalette.of(context).muted),
      ),
    ],
  );

  Widget statRow(BuildContext context, String value, String label) => Row(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: AppPalette.of(context).muted),
        ),
      ),
    ],
  );

  Widget _tierStat(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppPalette.of(context).pine,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            color: AppPalette.of(context).ink,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class GoalRoadmapPage extends StatelessWidget {
  const GoalRoadmapPage({super.key, required this.goal, required this.store});

  final GrowthGoal goal;
  final GrowthStore store;

  Future<void> _edit(BuildContext context, [int? index]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: AppPalette.of(context).paper,
        builder: (_) => MilestoneEditor(goal: goal, store: store, index: index),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final next = goal.milestones
          .asMap()
          .entries
          .where((entry) => !goal.completedMilestones.contains(entry.key))
          .firstOrNull;
      final linkedToday = store.tasks.any(
        (task) =>
            task.roadmapLinked &&
            !task.archived &&
            task.goalId == goal.id &&
            task.scheduledDay == store.today,
      );
      final practicedToday =
          goal.isDoneOn(store.today) || goal.restDays.contains(store.today);
      return Scaffold(
        appBar: AppBar(title: const Text('로드맵 관리')),
        body: pageFrame([
          Text(goal.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '로드맵은 매일 할 일이 아니라 목표까지 확인할 결과예요. '
            '예: 책 고르기 → 절반 읽기 → 완독. 필요 없으면 비워 두고 매일 실천만 해도 돼요.',
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${goal.completedMilestones.length}/${goal.milestones.length} 단계 완료',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: goal.milestones.isEmpty
                      ? 0
                      : goal.completedMilestones.length /
                            goal.milestones.length,
                  minHeight: 6,
                ),
                if (goal.milestones.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('아직 이정표가 없어요. 달성 여부를 확인할 수 있는 결과부터 적어 보세요.'),
                ],
                for (final entry in goal.milestones.asMap().entries)
                  CheckboxListTile(
                    key: ValueKey('milestone-${goal.id}-${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${entry.key + 1}. ${entry.value}'),
                    subtitle: _MilestoneDetailText(
                      detail: goal.milestoneDetails[entry.key],
                      achieved: goal.completedMilestones.contains(entry.key),
                    ),
                    value: goal.completedMilestones.contains(entry.key),
                    onChanged: (_) => store.toggleMilestone(goal, entry.key),
                    secondary: IconButton(
                      tooltip: '로드맵 단계 수정',
                      onPressed: () => _edit(context, entry.key),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add),
                  label: const Text('단계 추가'),
                ),
              ],
            ),
          ),
          if (next != null && !goal.archived) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '다음 이정표 · ${next.value}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('실천할 행동을 오늘 할 일로 가져올 수 있어요.'),
                  TextButton.icon(
                    onPressed: practicedToday || linkedToday
                        ? null
                        : () async {
                            final added = await store.addRoadmapAction(
                              goal,
                              next.key,
                            );
                            if (context.mounted && added) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('다음 단계 행동을 오늘 할 일에 넣었어요.'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.playlist_add_check_outlined),
                    label: Text(
                      linkedToday ? '오늘 행동을 가져왔어요' : '다음 단계 행동을 오늘 할 일로',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (store.tasks.any((task) => task.goalId == goal.id)) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              child: GoalLinkedTasks(store: store, goalId: goal.id),
            ),
          ],
        ]),
      );
    },
  );
}

class GoalHistoryPage extends StatelessWidget {
  const GoalHistoryPage({super.key, required this.goal, required this.store});

  final GrowthGoal goal;
  final GrowthStore store;

  String _shortDate(DateTime date) => '${date.month}/${date.day}';

  String _fullDate(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} (${weekdays[date.weekday - 1]})';
  }

  String _levelName(String value) => switch (value) {
    '쉬움' => 'MINI',
    '보통' => 'MORE',
    '도전' => 'MAX',
    _ => value,
  };

  Color _levelColor(BuildContext context, String level) => switch (level) {
    'MINI' => AppPalette.of(context).mini,
    'MORE' => AppPalette.of(context).more,
    'MAX' => AppPalette.of(context).max,
    _ => AppPalette.of(context).subtle,
  };

  Future<void> _editPractice(BuildContext context, DateTime? selected) async {
    final todayDate = DateTime.now();
    final first = DateTime.parse(goal.startDay);
    final date =
        selected ??
        await showAppDatePicker(
          context: context,
          title: '기록할 날짜 선택',
          initialDate: todayDate,
          firstDate: first,
          lastDate: todayDate,
        );
    if (date == null || !context.mounted) return;
    final day = dayKey(date);
    final current = goal.completions[day];
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fullDate(date)} 실천 기록',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('강도를 바꾸면 XP는 기록에 맞춰 다시 계산돼요.'),
                const SizedBox(height: 8),
                for (final (level, action) in [
                  ('MINI', goal.mini),
                  ('MORE', goal.more),
                  ('MAX', goal.max),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(level),
                    subtitle: Text(action),
                    trailing: _levelName(current ?? '') == level
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, level),
                  ),
                if (current != null) ...[
                  const Text('이미 받은 훈련권은 유지되며, 같은 날짜에 다시 지급되지 않아요.'),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, 'DELETE'),
                    child: const Text('이날 실천 기록 취소'),
                  ),
                ] else
                  const Text('최근 14일 기록의 훈련권은 게임을 열 때 반영돼요.'),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final saved = await store.setPracticeOn(
      goal,
      day,
      choice == 'DELETE' ? null : choice,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '실천 기록을 수정했어요.' : '이 날짜의 기록을 수정할 수 없어요.'),
        persist: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final activity = store.recentActivity(goal);
      final weeks = store.recentWeeks(goal);
      final recordedLevels = goal.completions.values.map(_levelName).toList();
      final nextMilestoneIndex = goal.milestones
          .asMap()
          .keys
          .where((index) => !goal.completedMilestones.contains(index))
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(title: const Text('목표 기록')),
        body: pageFrame([
          Text(goal.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 5),
          Text(
            '${goal.archived ? '보관 중 · ' : ''}${goal.path} · 주 ${goal.weeklyTarget}일 기준',
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          Text(
            '이번 주 ${store.completedDaysThisWeek(goal)}/${goal.weeklyTarget}일 · ${goal.startDay} → ${goal.targetDate ?? '종료일 미정'}',
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Row(
              children: [
                Expanded(
                  child: _summary(context, '${goal.completedDays}', '실천한 날'),
                ),
                Expanded(
                  child: _summary(context, '${goal.restDays.length}', '쉬어 간 날'),
                ),
                Expanded(
                  child: _summary(
                    context,
                    '${goal.completedMilestones.length}/${goal.milestones.length}',
                    '로드맵',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: goal.startDay.compareTo(store.today) <= 0
                ? () => _editPractice(context, null)
                : null,
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('날짜별 실천 기록 수정'),
          ),
          const SizedBox(height: 12),
          Text('최근 4주', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            '월요일부터 일요일까지의 실천일이에요. 쉬기는 제외해요.',
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                for (final week in weeks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 87,
                          child: Text(
                            '${_shortDate(week.start)}~${_shortDate(week.start.add(const Duration(days: 6)))}',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: week.completedDays / 7,
                            minHeight: 10,
                            color: AppPalette.of(context).pine,
                            backgroundColor: AppPalette.of(context).subtle,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${week.completedDays}일',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('어떤 강도로 했나요?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final level in ['MINI', 'MORE', 'MAX']) ...[
                if (level != 'MINI') const SizedBox(width: 7),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _levelColor(context, level),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          level,
                          style: TextStyle(
                            color: AppPalette.of(context).pine,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${recordedLevels.where((value) => value == level).length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Text('로드맵', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            '목표까지 확인할 이정표예요. 예: 책 고르기 → 절반 읽기 → 완독. '
            '매일의 MINI·MORE·MAX 실천과 별개이며, 필요할 때만 사용해도 돼요.',
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: goal.milestones.isEmpty
                ? const Text('아직 이정표가 없어요. 필요할 때 아래에서 단계를 추가할 수 있어요.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${goal.completedMilestones.length}/${goal.milestones.length} 단계 완료 · 주 ${goal.weeklyTarget}일 실천',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value:
                            goal.completedMilestones.length /
                            goal.milestones.length,
                        minHeight: 7,
                      ),
                      const SizedBox(height: 16),
                      for (final entry in goal.milestones.asMap().entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    goal.completedMilestones.contains(entry.key)
                                    ? AppPalette.of(context).pine
                                    : AppPalette.of(context).subtle,
                                child: Text(
                                  '${entry.key + 1}',
                                  style: TextStyle(
                                    color:
                                        goal.completedMilestones.contains(
                                          entry.key,
                                        )
                                        ? Colors.white
                                        : AppPalette.of(context).ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.value,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      goal.completedMilestones.contains(
                                            entry.key,
                                          )
                                          ? '완료한 단계'
                                          : entry.key == nextMilestoneIndex
                                          ? '다음에 확인할 결과'
                                          : '진행할 단계',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppPalette.of(context).muted,
                                      ),
                                    ),
                                    _MilestoneDetailText(
                                      detail: goal.milestoneDetails[entry.key],
                                      achieved: goal.completedMilestones
                                          .contains(entry.key),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => GoalRoadmapPage(goal: goal, store: store),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('로드맵 단계 관리'),
          ),
          if (store.tasks.any((task) => task.goalId == goal.id)) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              child: GoalLinkedTasks(store: store, goalId: goal.id),
            ),
          ],
          const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 주 실행 방법',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '이번 주 ${store.completedDaysThisWeek(goal)}/${goal.weeklyTarget}일 · '
                  '힘든 날에도 MINI로 이어갈 수 있어요.',
                ),
                if (goal.weeklyMinutes != null)
                  Text(
                    '쓸 수 있는 시간 주 ${goal.weeklyMinutes}분 · '
                    '실천일당 약 ${_perPracticeDay(goal.weeklyMinutes!, goal.weeklyTarget)}',
                  ),
                if (nextMilestoneIndex != null)
                  Text('다음 이정표  ${goal.milestones[nextMilestoneIndex]}'),
                const SizedBox(height: 8),
                Text('MINI  ${goal.mini}'),
                Text('MORE  ${goal.more}'),
                Text('MAX  ${goal.max}'),
                if (goal.selectedPlan != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '처음 선택한 계획의 첫 주',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).pine,
                    ),
                  ),
                  Text('첫 주 핵심  ${goal.selectedPlan!.firstWeekActions.first}'),
                ],
                if (goal.currentLevel.isNotEmpty)
                  Text('시작 수준  ${goal.currentLevel}'),
                Text(
                  '목표 기간  ${goal.startDay} → ${goal.targetDate ?? '종료일 미정'}',
                ),
              ],
            ),
          ),
          if (goal.selectedPlan != null) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('처음 선택한 계획'),
                subtitle: Text(
                  '${goal.selectedPlan!.title} · 주 ${goal.selectedPlan!.weeklyTarget}일'
                  '${goal.selectedPlan!.durationWeeks == null ? ' · 기간 미정' : ' · ${goal.selectedPlan!.durationWeeks}주'}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(goal.selectedPlan!.summary),
                  ),
                  const SizedBox(height: 8),
                  for (final action in goal.selectedPlan!.firstWeekActions)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('• $action'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '현재 로드맵은 위에서 따로 수정할 수 있어요.',
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('최근 활동', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(
            '최근 ${activity.length}건의 실천과 쉼 기록',
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: activity.isEmpty
                ? Text(
                    '아직 기록이 없어요. MINI부터 시작해 보세요.',
                    style: TextStyle(color: AppPalette.of(context).muted),
                  )
                : Column(
                    children: [
                      for (final event in activity)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_fullDate(event.date)),
                                    if (event.action != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        event.action!,
                                        style: TextStyle(
                                          color: AppPalette.of(context).muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _levelColor(
                                    context,
                                    _levelName(event.level),
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  _levelName(event.level),
                                  style: TextStyle(
                                    color: AppPalette.of(context).ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '이날 기록 수정',
                                onPressed: () =>
                                    _editPractice(context, event.date),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ]),
      );
    },
  );

  Widget _summary(BuildContext context, String value, String label) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(color: AppPalette.of(context).muted, fontSize: 11),
      ),
    ],
  );
}

class GoalForm extends StatefulWidget {
  const GoalForm({
    super.key,
    required this.store,
    this.authGateway,
    this.roadmapGenerator,
  });
  final GrowthStore store;
  final AuthGateway? authGateway;
  final RoadmapGenerator? roadmapGenerator;

  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  final wizardScroll = ScrollController();
  final title = TextEditingController();
  final mini = TextEditingController();
  final more = TextEditingController();
  final max = TextEditingController();
  final milestone = TextEditingController();
  bool roadmapLater = false;
  final currentLevel = TextEditingController();
  final weeklyMinutes = TextEditingController();
  DateTime startDate = DateTime.now();
  DateTime? targetDate;
  String? minutesError;
  String? generationError;
  bool generating = false;
  List<RoadmapPlan> aiPlans = const [];
  RoadmapPlan? selectedAiPlan;
  int step = 0;
  String path = '균형 있게';
  static const questions = [
    '무엇을 키울까요?',
    '주 몇 번 해볼까요?',
    '바쁜 날엔 무엇을?',
    '보통 날엔 무엇을?',
    '여유 있는 날엔?',
    '첫 이정표는?',
    '지금 상황은?',
    '시작 방법은?',
  ];
  static const presets =
      <
        ({String title, String mini, String more, String max, String milestone})
      >[
        (
          title: '책 읽는 습관 만들기',
          mini: '책 2쪽 읽기',
          more: '책 15분 읽기',
          max: '책 40분 읽기',
          milestone: '첫 책 한 권 끝내기',
        ),
        (
          title: '운동 습관 만들기',
          mini: '스트레칭 3분',
          more: '운동 20분',
          max: '운동 45분',
          milestone: '한 달 동안 주 3회 운동하기',
        ),
        (
          title: '영어 공부 시작하기',
          mini: '단어 3개 보기',
          more: '영어 20분 공부',
          max: '영어 45분 공부',
          milestone: '첫 학습 주제 마치기',
        ),
        (
          title: '취업 준비하기',
          mini: '채용 공고 1개 보기',
          more: '포트폴리오 20분 작업',
          max: '포트폴리오 1시간 작업',
          milestone: '첫 포트폴리오 초안 만들기',
        ),
        (
          title: '새 취미 찾기',
          mini: '관심 있는 취미 1개 찾아보기',
          more: '취미 20분 해보기',
          max: '취미 1시간 즐기기',
          milestone: '마음에 드는 취미 하나 정하기',
        ),
      ];

  @override
  void dispose() {
    wizardScroll.dispose();
    title.dispose();
    mini.dispose();
    more.dispose();
    max.dispose();
    milestone.dispose();
    currentLevel.dispose();
    weeklyMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      title: '목표 시작일',
      initialDate: startDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        startDate = picked;
        if (targetDate != null && targetDate!.isBefore(picked)) {
          targetDate = null;
        }
      });
    }
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      title: '목표 종료일',
      initialDate: targetDate ?? (startDate.isAfter(now) ? startDate : now),
      firstDate: startDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null) setState(() => targetDate = picked);
  }

  void choosePreset(
    ({String title, String mini, String more, String max, String milestone})
    preset,
  ) {
    title.text = preset.title;
    mini.text = preset.mini;
    more.text = preset.more;
    max.text = preset.max;
    milestone.text = preset.milestone;
    setState(() {});
  }

  void next() {
    final current = switch (step) {
      0 => title.text,
      2 => mini.text,
      3 => more.text,
      4 => max.text,
      _ => 'ok',
    };
    if (current.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('한 가지를 적거나 예시를 선택해 주세요.')));
      return;
    }
    if (step == 6) {
      final minutes = weeklyMinutes.text.trim().isEmpty
          ? null
          : int.tryParse(weeklyMinutes.text.trim());
      if (weeklyMinutes.text.trim().isNotEmpty &&
          (minutes == null || minutes < 1 || minutes > 10080)) {
        setState(() => minutesError = '분 단위 숫자로 적어 주세요.');
        return;
      }
      if (targetDate == null && !roadmapLater) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('목표 종료일을 골라 주세요.')));
        return;
      }
    }
    if (step == questions.length - 1 || (step == 6 && roadmapLater)) {
      save();
    } else {
      FocusScope.of(context).unfocus();
      setState(() {
        if (step == 6) {
          aiPlans = const [];
          selectedAiPlan = null;
          generationError = null;
        }
        step++;
      });
      if (wizardScroll.hasClients) wizardScroll.jumpTo(0);
    }
  }

  Future<void> _generateAiPlans() async {
    final generator = widget.roadmapGenerator;
    final minutes = int.tryParse(weeklyMinutes.text.trim());
    if (generator == null ||
        currentLevel.text.trim().isEmpty ||
        targetDate == null ||
        minutes == null ||
        minutes < 1) {
      setState(() => generationError = '현재 수준·종료일·주당 가능 시간을 먼저 적어 주세요.');
      return;
    }
    setState(() {
      generating = true;
      generationError = null;
    });
    try {
      final plans = await generator.generate(
        RoadmapRequest(
          goal: title.text,
          currentLevel: currentLevel.text,
          targetDate: dayKey(targetDate!),
          availableMinutes: minutes,
          preferredPath: path,
          mini: mini.text,
          more: more.text,
          max: max.text,
          firstMilestone: milestone.text,
        ),
      );
      final validated = parseAiRoadmapOptions(
        plans.map((plan) => plan.toJson()).toList(),
        availableMinutes: minutes,
      );
      if (!mounted) return;
      setState(() {
        aiPlans = validated;
        selectedAiPlan = validated.first;
      });
    } on RoadmapGenerationException catch (error) {
      if (mounted) setState(() => generationError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => generationError = 'AI 계획을 확인하지 못했어요. 수동 시작안으로 계속할 수 있어요.',
        );
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> save() async {
    final draft = manualRoadmapDrafts(
      mini: mini.text.trim(),
      more: more.text.trim(),
      max: max.text.trim(),
      firstMilestone: milestone.text,
      startDate: startDate,
      targetDate: targetDate,
      weeklyMinutes: weeklyMinutes.text.trim().isEmpty
          ? null
          : int.parse(weeklyMinutes.text.trim()),
    ).firstWhere((item) => item.path == path);
    final manualPlan = RoadmapPlan.fromManualDraft(
      draft,
      firstMilestone: milestone.text,
    );
    final selectedPlan = selectedAiPlan ?? manualPlan;
    final skipRoadmap = roadmapLater;
    final chosenPath = selectedAiPlan == null
        ? path
        : selectedPlan.weeklyTarget <= 2
        ? '가볍게 시작'
        : selectedPlan.weeklyTarget >= 5
        ? '집중해서'
        : '균형 있게';
    final saved = await widget.store.addGoal(
      title: title.text,
      mini: mini.text,
      more: more.text,
      max: max.text,
      path: chosenPath,
      weeklyTarget: selectedPlan.weeklyTarget,
      milestones: skipRoadmap ? const [] : selectedPlan.milestones,
      milestoneDetails: skipRoadmap
          ? const []
          : selectedAiPlan == null
          ? draft.stages.map((stage) => stage.detail).toList()
          : null,
      currentLevel: currentLevel.text,
      startDate: dayKey(startDate),
      targetDate: targetDate == null ? null : dayKey(targetDate!),
      weeklyMinutes: weeklyMinutes.text.trim().isEmpty
          ? null
          : int.parse(weeklyMinutes.text.trim()),
      selectedPlan: skipRoadmap ? null : selectedPlan,
    );
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    MediaQuery.sizeOf(context).width < 340 ||
                            MediaQuery.textScalerOf(context).scale(12) > 18
                        ? '새 목표'
                        : '새 목표 만들기',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${step + 1} / ${questions.length}',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '취소',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (step + 1) / questions.length,
              minHeight: 4,
              color: AppPalette.of(context).pine,
              backgroundColor: AppPalette.of(context).line,
            ),
            const SizedBox(height: 27),
            Expanded(
              child: SingleChildScrollView(
                controller: wizardScroll,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.12, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(step),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questions[step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _hint,
                          style: TextStyle(color: AppPalette.of(context).muted),
                        ),
                        const SizedBox(height: 25),
                        _stepContent(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (step > 0) ...[
                  OutlinedButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => step--);
                      if (wizardScroll.hasClients) wizardScroll.jumpTo(0);
                    },
                    child: const Text('이전'),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: generating ? null : next,
                    child: Text(
                      step == questions.length - 1 ||
                              (step == 6 && roadmapLater)
                          ? '목표 시작하기'
                          : '다음',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String get _hint => switch (step) {
    0 => '내 목표를 자유롭게 적어 주세요. 아래 예시는 입력을 돕는 참고 자료예요.',
    1 => '내 생활에 맞는 속도를 고르세요. 주간 횟수는 나중에 바꿀 수 있어요.',
    2 => '아주 작은 행동도 성공으로 기록돼요.',
    3 => '대부분의 날에 무리 없이 할 수 있는 양이면 좋아요.',
    4 => '할 수 있는 날에만 선택하는 추가 도전이에요.',
    5 => '선택 사항이에요. 첫 번째로 도달하고 싶은 지점을 적어 주세요.',
    6 => '모두 선택 사항이에요. 나중에 목표 설정에서 바꿀 수 있어요.',
    _ => '입력한 행동으로 구성한 시작안 3개를 비교하세요. 선택 후에도 바꿀 수 있어요.',
  };

  Widget _stepContent() => switch (step) {
    0 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _input(title, '직접 적기', '예: 매주 그림 한 장 완성하기'),
        const SizedBox(height: 24),
        Text(
          '참고 예시',
          style: TextStyle(
            color: AppPalette.of(context).muted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '누르면 위 입력칸에 채워져요. 그대로 사용하거나 바꿀 수 있어요.',
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: presets
              .map(
                (preset) => ActionChip(
                  label: Text(
                    preset.title,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => choosePreset(preset),
                  backgroundColor: AppPalette.of(context).subtle,
                  side: BorderSide(color: AppPalette.of(context).line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
    1 => Column(
      children: [
        _choiceCard(
          '가볍게 시작',
          '주 2일 추천 · 작은 성공부터',
          () => _choosePath('가볍게 시작'),
          selected: path == '가볍게 시작',
        ),
        _choiceCard(
          '균형 있게',
          '주 3일 추천 · 꾸준함과 진도를 함께',
          () => _choosePath('균형 있게'),
          selected: path == '균형 있게',
        ),
        _choiceCard(
          '집중해서',
          '주 5일 추천 · 시간을 더 써서 빠르게',
          () => _choosePath('집중해서'),
          selected: path == '집중해서',
        ),
      ],
    ),
    2 => _actionInput(mini, 'MINI · 아주 작은 행동', '예: 2분만 시작하기'),
    3 => _actionInput(more, 'MORE · 평소 행동', '예: 20분 집중하기'),
    4 => _actionInput(max, 'MAX · 여유 있는 날의 행동', '예: 40분 몰입하기'),
    5 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!roadmapLater) _input(milestone, '첫 이정표 · 선택', '예: 첫 책 절반 읽기'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('로드맵은 나중에 만들기'),
          value: roadmapLater,
          onChanged: (value) => setState(() => roadmapLater = value ?? false),
        ),
        const SizedBox(height: 12),
        Text(
          '로드맵은 목표까지의 큰 단계예요. 비워 두고 나중에 만들어도 매일 실천할 수 있어요.',
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
      ],
    ),
    6 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: currentLevel,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: '현재 수준',
            hintText: '예: 이제 막 시작했어요',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: weeklyMinutes,
          keyboardType: TextInputType.number,
          onChanged: (_) {
            if (minutesError != null) setState(() => minutesError = null);
          },
          decoration: InputDecoration(
            labelText: '일주일에 쓸 수 있는 시간 · 분',
            hintText: '예: 120',
            errorText: minutesError,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _pickStartDate,
          icon: const Icon(Icons.event_available_outlined),
          label: Text('시작일 · ${dayKey(startDate)}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickTargetDate,
          icon: const Icon(Icons.flag_outlined),
          label: Text(
            targetDate == null ? '종료일 선택' : '종료일 · ${dayKey(targetDate!)}',
          ),
        ),
      ],
    ),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.roadmapGenerator != null &&
            widget.authGateway?.currentUserId != null) ...[
          FilledButton.icon(
            onPressed: generating ? null : _generateAiPlans,
            icon: generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(generating ? '계획을 만들고 있어요' : 'AI 계획 3안 만들기'),
          ),
          const SizedBox(height: 10),
        ] else if (widget.roadmapGenerator != null) ...[
          const Text('AI 계획은 계정에서 로그인한 뒤 요청할 수 있어요.'),
          const SizedBox(height: 10),
        ],
        if (generationError != null) ...[
          Text(
            generationError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          aiPlans.isEmpty
              ? '아래 세 안은 입력한 행동으로 만든 시작 템플릿이에요. 단계와 기준은 목표를 만든 뒤 로드맵에서 고칠 수 있어요.'
              : '기간·주당 시간·이정표·첫 주 행동을 비교해 선택하세요.',
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
        if (weeklyMinutes.text.trim().isNotEmpty || targetDate != null) ...[
          const SizedBox(height: 8),
          Text(
            [
              if (weeklyMinutes.text.trim().isNotEmpty)
                '주당 가능 ${weeklyMinutes.text.trim()}분',
              '시작일 ${dayKey(startDate)}',
              if (targetDate != null) '종료일 ${dayKey(targetDate!)}',
            ].join(' · '),
            style: TextStyle(color: AppPalette.of(context).ink, fontSize: 12),
          ),
        ],
        if (currentLevel.text.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            '현재 수준 ${currentLevel.text.trim()}',
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        if (aiPlans.isEmpty)
          for (final draft in manualRoadmapDrafts(
            mini: mini.text.trim(),
            more: more.text.trim(),
            max: max.text.trim(),
            firstMilestone: milestone.text,
            startDate: startDate,
            targetDate: targetDate,
            weeklyMinutes: weeklyMinutes.text.trim().isEmpty
                ? null
                : int.tryParse(weeklyMinutes.text.trim()),
          ))
            _draftCard(draft)
        else ...[
          for (final plan in aiPlans) _aiPlanCard(plan),
          TextButton(
            onPressed: () => setState(() {
              aiPlans = const [];
              selectedAiPlan = null;
            }),
            child: const Text('수동 시작안으로 돌아가기'),
          ),
        ],
      ],
    ),
  };

  Widget _aiPlanCard(RoadmapPlan plan) {
    final selected = identical(selectedAiPlan, plan);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? AppPalette.of(context).selected
            : AppPalette.of(context).card,
        borderRadius: BorderRadius.circular(softRadius),
        child: InkWell(
          onTap: () => setState(() => selectedAiPlan = plan),
          borderRadius: BorderRadius.circular(softRadius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(softRadius),
              border: Border.all(
                color: selected
                    ? AppPalette.of(context).pine
                    : AppPalette.of(context).line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: TextStyle(
                          color: AppPalette.of(context).ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: AppPalette.of(context).pine,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(plan.summary),
                const SizedBox(height: 5),
                Text(
                  '${plan.durationWeeks}주 · 주 ${plan.weeklyTarget}일 · ${plan.weeklyMinutes}분',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                const SizedBox(height: 8),
                Text('이정표: ${plan.milestones.join(' → ')}'),
                const SizedBox(height: 5),
                for (final action in plan.firstWeekActions) Text('• $action'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _draftCard(RoadmapDraft draft) {
    final selected = path == draft.path;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? AppPalette.of(context).selected
            : AppPalette.of(context).card,
        borderRadius: BorderRadius.circular(softRadius),
        child: InkWell(
          onTap: () => setState(() => path = draft.path),
          borderRadius: BorderRadius.circular(softRadius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(softRadius),
              border: Border.all(
                color: selected
                    ? AppPalette.of(context).pine
                    : AppPalette.of(context).line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${draft.path} · 주 ${draft.weeklyTarget}일',
                        style: TextStyle(
                          color: AppPalette.of(context).ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: AppPalette.of(context).pine,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  draft.summary,
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                const SizedBox(height: 8),
                for (final action in draft.firstWeekActions)
                  Text(
                    '• $action',
                    style: TextStyle(
                      color: AppPalette.of(context).ink,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 10),
                if (draft.durationWeeks != null)
                  Text(
                    '목표 종료일까지 약 ${draft.durationWeeks}주',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (draft.weeklyMinutes != null)
                  Text(
                    '주 ${draft.weeklyMinutes}분 · 실천일당 약 ${_perPracticeDay(draft.weeklyMinutes!, draft.weeklyTarget)}',
                  ),
                for (final entry in draft.stages.asMap().entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key + 1}. ${entry.value.title}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '확인 · ${entry.value.criteria}',
                          style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontSize: 12,
                          ),
                        ),
                        if (entry.value.targetDate != null)
                          Text(
                            '예상 완료 ${entry.value.targetDate}',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _choosePath(String value) {
    setState(() => path = value);
    next();
  }

  Widget _actionInput(
    TextEditingController controller,
    String label,
    String example,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _input(controller, label, example, maxLength: 160),
      const SizedBox(height: 18),
      _choiceCard(example.replaceFirst('예: ', ''), '예시 선택', () {
        controller.text = example.replaceFirst('예: ', '');
        next();
      }),
    ],
  );

  Widget _input(
    TextEditingController controller,
    String label,
    String hint, {
    int? maxLength,
  }) => TextField(
    controller: controller,
    maxLength: maxLength,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => next(),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _choiceCard(
    String title,
    String detail,
    VoidCallback onTap, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: selected
          ? AppPalette.of(context).selected
          : AppPalette.of(context).card,
      borderRadius: BorderRadius.circular(softRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(softRadius),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(softRadius),
            border: Border.all(
              color: selected
                  ? AppPalette.of(context).pine
                  : AppPalette.of(context).line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward,
                size: 18,
                color: AppPalette.of(context).pine,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
