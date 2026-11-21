import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/game_creature.dart';
import 'models/battle_engine.dart';
import 'models/adventure_stage.dart';
import 'models/reward_grant.dart';
import 'game_motion_sprite.dart';
import 'enemy_sprite.dart';
import 'battle_page.dart';
import 'game_reward_ledger_page.dart';
import 'state/game_store.dart';
import 'state/game_expedition_remote.dart';
import 'state/growth_store.dart';
import 'server_expedition_panel.dart';

const _background = Color(0xFF202330);
const _card = Color(0xFF303544);
const _muted = Color(0xFFC2D5D1);

String _rewardSourceTitle(RewardGrant grant, GrowthStore? growth) {
  if (grant.kind == 'task' || grant.kind == 'routine') {
    final id = grant.kind == 'routine'
        ? grant.sourceId.replaceFirst(RegExp(r':\d{4}-\d{2}-\d{2}$'), '')
        : grant.sourceId;
    return growth?.tasks.where((task) => task.id == id).firstOrNull?.title ??
        '할 일';
  }
  final lastColon = grant.sourceId.lastIndexOf(':');
  final goalId = grant.sourceId.startsWith('goal:') && lastColon > 5
      ? grant.sourceId.substring(5, lastColon)
      : '';
  return growth?.allGoals
          .where((goal) => goal.id == goalId)
          .firstOrNull
          ?.title ??
      '목표 실천';
}

String _rewardKindLabel(String kind) => switch (kind) {
  'routine' => '반복 할 일',
  'mini' => 'MINI 실천',
  'more' => 'MORE 실천',
  'max' => 'MAX 실천',
  _ => '할 일',
};

String _rewardCapReason(RewardGrant grant) {
  if (!grant.capped) return '';
  final day = DateTime.tryParse('${grant.activityDay ?? ''}T00:00:00Z');
  if (day != null) {
    final grantedKorea = grant.grantedAt.toUtc().add(const Duration(hours: 9));
    final grantedDay = DateTime.utc(
      grantedKorea.year,
      grantedKorea.month,
      grantedKorea.day,
    );
    if (day.isBefore(grantedDay.subtract(const Duration(days: 14)))) {
      return '최근 14일 범위 밖';
    }
  }
  return '하루 할 일 보상 5개 한도';
}

String _dexAcquisitionHint(
  CreatureSpecies species,
  String? starterSpeciesId,
  bool firstBattleWon,
  bool drawAvailable,
) {
  if (species.id == 'pebble_newt') {
    return '물안개 여울 첫 전투 승리에서 확정 합류해요.';
  }
  if (!firstBattleWon &&
      starterSpeciesId != null &&
      firstForestCompanionSpeciesId(starterSpeciesId) == species.id) {
    return '이끼 문턱 첫 전투 승리에서 확정 합류해요.';
  }
  return drawAvailable
      ? '정식 파견 귀환으로 조각 3개를 모아 무료 뽑기에 도전해 보세요.'
      : '정식 파견·무료 뽑기 기능이 열리면 만날 수 있어요.';
}

class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    required this.gameStore,
    this.growthStore,
    this.gameRemoteClient,
    this.onOpenAccount,
    this.gameDrawEnabled = false,
    this.gameStageRewardsEnabled = false,
  });

  final GameStore gameStore;
  final GrowthStore? growthStore;
  final SupabaseClient? gameRemoteClient;
  final VoidCallback? onOpenAccount;
  final bool gameDrawEnabled;
  final bool gameStageRewardsEnabled;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  bool changingStarter = false;
  int _section = 0;
  bool _foreground = true;
  ServerGameState? _serverGame;
  String? _serverUserId;
  List<ServerStageFirstClear>? _mapServerFirstClears;
  Map<String, ServerStageRecord>? _mapServerStageRecords;
  String? _mapServerUserId;
  int _mapFetchSerial = 0;
  int _serverFetchSerial = 0;
  StreamSubscription<AuthState>? _authSubscription;
  late final Timer _trainingTicker;

  ServerGameState? get _currentServerGame {
    final activeUserId = widget.gameRemoteClient?.auth.currentUser?.id;
    return activeUserId != null && activeUserId == _serverUserId
        ? _serverGame
        : null;
  }

  List<ServerStageFirstClear>? get _currentMapServerFirstClears {
    final activeUserId = widget.gameRemoteClient?.auth.currentUser?.id;
    if (activeUserId == null) return null;
    final serverGame = _currentServerGame;
    if (serverGame != null) return serverGame.stageFirstClears;
    return activeUserId == _mapServerUserId ? _mapServerFirstClears : null;
  }

  Map<String, ServerStageRecord>? get _currentMapServerStageRecords {
    final activeUserId = widget.gameRemoteClient?.auth.currentUser?.id;
    if (activeUserId == null) return null;
    final serverGame = _currentServerGame;
    if (serverGame != null) return serverGame.stageRecords;
    return activeUserId == _mapServerUserId ? _mapServerStageRecords : null;
  }

  void _receiveServerGame(ServerGameState? game) {
    if (!mounted) return;
    _serverFetchSerial++;
    setState(() {
      _serverGame = game;
      _serverUserId = game == null
          ? null
          : widget.gameRemoteClient?.auth.currentUser?.id;
      if (game != null) {
        _mapFetchSerial++;
        _mapServerFirstClears = game.stageFirstClears;
        _mapServerStageRecords = game.stageRecords;
        _mapServerUserId = _serverUserId;
      }
    });
  }

  Future<void> _loadServerGame() async {
    final client = widget.gameRemoteClient;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    final serial = ++_serverFetchSerial;
    try {
      final game = await SupabaseGameExpeditionRemote(
        client,
        drawEnabled: widget.gameDrawEnabled,
        stageRewardsEnabled: widget.gameStageRewardsEnabled,
      ).load();
      if (!mounted ||
          serial != _serverFetchSerial ||
          client.auth.currentUser?.id != userId) {
        return;
      }
      _receiveServerGame(game);
    } catch (_) {
      // The mission tab offers a retryable account-game panel.
    }
  }

  void _switchSection(int section) {
    setState(() => _section = section);
    if (section >= 2 && _currentServerGame == null) {
      unawaited(_loadServerGame());
    }
  }

  Future<void> _loadServerMapProgress() async {
    final client = widget.gameRemoteClient;
    final userId = client?.auth.currentUser?.id;
    if (!widget.gameStageRewardsEnabled || client == null || userId == null) {
      return;
    }
    final serial = ++_mapFetchSerial;
    try {
      final response = await client.rpc('get_game_stage_reward_status');
      final status = Map<String, dynamic>.from(response as Map);
      final clears = (status['first_clears'] as List<dynamic>? ?? [])
          .map(
            (item) => ServerStageFirstClear.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      final records = await loadServerStageRecords(client);
      if (!mounted ||
          serial != _mapFetchSerial ||
          client.auth.currentUser?.id != userId) {
        return;
      }
      setState(() {
        _mapServerFirstClears = clears;
        _mapServerStageRecords = records;
        _mapServerUserId = userId;
      });
    } catch (_) {
      // The server panel shows the actionable error and can retry separately.
    }
  }

  void _openServerGame({String? stageId}) {
    final client = widget.gameRemoteClient;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: _background,
          appBar: AppBar(title: const Text('정식 파견·전투')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ServerExpeditionPanel(
                    client: client,
                    gameStore: widget.gameStore,
                    initialStageId: stageId,
                    onOpenAccount: widget.onOpenAccount,
                    drawEnabled: widget.gameDrawEnabled,
                    stageRewardsEnabled: widget.gameStageRewardsEnabled,
                    onStateChanged: _receiveServerGame,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = widget.gameRemoteClient?.auth.onAuthStateChange.listen((
      _,
    ) {
      if (!mounted) return;
      final activeUserId = widget.gameRemoteClient?.auth.currentUser?.id;
      if (activeUserId != _serverUserId || activeUserId != _mapServerUserId) {
        _serverFetchSerial++;
        setState(() {
          _serverGame = null;
          _serverUserId = null;
          _mapFetchSerial++;
          _mapServerFirstClears = null;
          _mapServerStageRecords = null;
          _mapServerUserId = null;
        });
      }
      if (activeUserId != null) unawaited(_loadServerMapProgress());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_creditCompletedTasks());
        unawaited(_loadServerMapProgress());
      }
    });
    _trainingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _foreground && widget.gameStore.trainingEndsAt != null) {
        setState(() {});
      }
    });
  }

  Future<void> _creditCompletedTasks() async {
    final growth = widget.growthStore;
    if (growth == null) return;
    try {
      await widget.gameStore.creditRewards(growth.rewardCandidates);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('훈련 횟수를 저장하지 못했어요. 게임을 다시 열어 주세요.')),
      );
    }
  }

  Widget _journeyPrompt(GameStore store) {
    final nextBattle = firstForestStages.indexWhere(
      (stage) => (store.stageProgress[stage.id]?.stars ?? 0) == 0,
    );
    final remaining = store.trainingRemaining();
    String title;
    String detail;
    String? actionLabel;
    VoidCallback? action;
    String? growthHint;
    VoidCallback? growthAction;
    if (remaining != null) {
      if (remaining > Duration.zero) {
        title = '훈련 중이에요';
        detail = '귀환까지 ${remaining.inSeconds + 1}초 남았어요.';
      } else {
        title = '귀환 확인';
        detail = '동료가 돌아왔어요. 귀환을 확인하면 숲길 기록이 쌓여요.';
        actionLabel = '귀환 확인';
        action = () => _trainingAction(finish: true);
      }
    } else if (nextBattle < 0) {
      final nextRiver = riverStages
          .where((stage) => (store.stageProgress[stage.id]?.stars ?? 0) == 0)
          .firstOrNull;
      title = nextRiver == null ? '안개 강가를 완주했어요' : '첫 숲길을 완주했어요';
      detail = nextRiver == null
          ? '달빛 나루까지 기기 전투를 마쳤어요. 강가 기록을 확인해 보세요.'
          : '${nextRiver.place}가 다음 여정이에요. 모험 지도에서 이야기를 읽고 전투를 준비해 보세요.';
      actionLabel = nextRiver == null ? '강가 기록 보기' : '${nextRiver.place} 보기';
      action = () => _switchSection(1);
    } else if (nextBattle > 0 &&
        store.owned.any(
          (creature) => creature.id == GameStore.firstForestCompanionId,
        ) &&
        !store.squad.contains(GameStore.firstForestCompanionId)) {
      title = '새 동료를 스쿼드에 편성해요';
      detail = '첫 전투에서 합류한 신수를 스쿼드에 넣고 함께 도전하세요.';
      actionLabel = '편성하기';
      final emptySlot = store.squad.indexOf(null);
      action = () => _editSquadSlot(emptySlot < 0 ? 1 : emptySlot);
    } else {
      final stage = firstForestStages[nextBattle];
      if (stage.boss &&
          store.owned.any(
            (creature) =>
                store.squad.contains(creature.id) && creature.level < 4,
          )) {
        final remainingExperience = store.remainingStageExperienceWins(
          firstForestStages[1].id,
        );
        growthHint = remainingExperience == 0
            ? '오늘은 전투 경험을 모두 받았어요. 내일 오솔길에서 성장하세요.'
            : '오솔길에서 다시 이겨 신수를 Lv4까지 키워 보세요.';
        growthAction = () => _showStageDetails(1);
      }
      if (store.trainingCompletions < stage.at) {
        title = '훈련 ${stage.at - store.trainingCompletions}회 남음';
        detail = store.trainingPasses > 0
            ? '${stage.place} · 귀환 ${store.trainingCompletions}/${stage.at}회 · 훈련권 ${store.trainingPasses}회'
            : '${stage.place} · 오늘의 할 일이나 목표 실천을 마치면 훈련권을 얻어요.';
        if (store.trainingPasses > 0) {
          actionLabel = '훈련 출발';
          action = () => _trainingAction(finish: false);
        }
      } else if (store.trainingPasses == 0) {
        title = '${stage.place} 전투 준비';
        detail = '훈련권 1회가 필요해요. 오늘의 할 일이나 목표 실천을 마쳐 보세요.';
      } else {
        title = '다음 전투 · ${stage.place}';
        detail = '훈련 조건 완료 · 편성을 확인하고 도전하세요.';
        actionLabel = '전투 정보';
        action = () => _showStageDetails(nextBattle);
      }
    }
    return _GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '다음 걸음',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(color: _muted)),
          if (growthHint != null) ...[
            const SizedBox(height: 6),
            Text(growthHint, style: const TextStyle(color: _muted)),
          ],
          if (actionLabel != null && action != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: action,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAAD7F3),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: Text(actionLabel),
            ),
          ],
          if (growthAction != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: growthAction,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAAD7F3),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('오솔길 전투 정보'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_loadServerMapProgress());
    if (_foreground && mounted && widget.gameStore.trainingEndsAt != null) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _trainingTicker.cancel();
    super.dispose();
  }

  Future<void> _trainingAction({required bool finish}) async {
    try {
      final saved = finish
          ? await widget.gameStore.finishTraining()
          : await widget.gameStore.startTraining();
      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파견 상태를 확인한 뒤 다시 시도해 주세요.')),
        );
      } else if (finish) {
        final unlocked = TrainingJournal.entries
            .where((entry) => entry.at == widget.gameStore.trainingCompletions)
            .firstOrNull;
        if (unlocked != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('숲길 지도 「${unlocked.title}」를 탐험할 수 있어요.')),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('훈련 파견을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _exploreStage(int index) async {
    final stage = TrainingJournal.entries[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${index + 1} · ${stage.place}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/game/pine-forest-bg.png',
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(stage.mission),
              const SizedBox(height: 8),
              Text('준비 팁 · ${stage.strategy}'),
              const SizedBox(height: 8),
              Text('훈련 ${stage.at}회 귀환 조건을 달성했어요.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(stage.action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final cleared = await widget.gameStore.clearAdventureStage(index);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared
                ? '「${stage.title}」 이야기를 열었어요. 장소 정보에서 전투에 도전하세요.'
                : '탐험 조건을 다시 확인해 주세요.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탐험 기록을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _exploreRiverStage(AdventureStage stage) async {
    final scene = switch (stage.id) {
      'river_mist_entry' => '숲의 마지막 발자국을 따라 내려오자 물안개가 강둑을 가렸어요. 수면에 비친 작은 돌무늬가 건널 길을 가리키지만, 물안개 수호자가 그 앞에 서 있습니다.',
      'river_shallow_crossing' => '여울의 얕은 돌길은 갈대 사이에서 끊겼다가 다시 나타납니다. 돌게가 앞길을 막는 동안 뒤쪽 물결에서도 소리가 들려요. 모두가 서로의 자리를 살펴야 건널 수 있습니다.',
      _ => '달빛 아래 빈 나룻배가 물결에 맞춰 움직입니다. 사공의 장막 너머로 맞은편 강둑이 보이고, 지금까지 함께 온 동료들의 발자국이 배 안에 이어집니다.',
    };
    final asset = switch (stage.id) {
      'river_shallow_crossing' => 'assets/game/river-shallow-bg.png',
      'river_moon_ferry' => 'assets/game/river-ferry-bg.png',
      _ => 'assets/game/river-mist-bg.png',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('안개 강가 · ${stage.place}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  asset,
                  height: 110,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(scene),
              const SizedBox(height: 12),
              Text('다음 목표 · ${stage.mission}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탐색 기록하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final opened = await widget.gameStore.exploreRiverStage(stage.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? '「${stage.title}」 이야기를 기록했어요. 전투 준비는 언제든 할 수 있어요.'
                : '이미 기록한 장소예요. 이야기를 다시 확인했어요.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탐색 기록을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _showStageDetails(int index) async {
    final stage = firstForestStages[index];
    final progress = widget.gameStore.stageProgress[stage.id];
    final serverClear = _currentMapServerFirstClears
        ?.where((item) => item.stageId == stage.id)
        .firstOrNull;
    final serverRecord = _currentMapServerStageRecords?[stage.id];
    final unlocked =
        widget.gameStore.trainingCompletions >= stage.at &&
        (stage.prerequisiteStageId == null ||
            widget
                    .gameStore
                    .stageProgress[stage.prerequisiteStageId]
                    ?.clearCount !=
                null);
    final battleChoice = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(stage.place),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ForestStageBanner(index: index),
                const SizedBox(height: 12),
                if (stage.boss) ...[
                  const Text(
                    '지역 보스 · 최종 장소',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(stage.mission),
                const SizedBox(height: 12),
                const Text(
                  '이 기기 이야기 전투',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '상태 · ${progress != null
                      ? progress.stars > 0
                            ? '전투 클리어'
                            : '이야기 해금 · 전투 미승리'
                      : unlocked
                      ? '탐험 가능'
                      : '잠김'}',
                ),
                Text(
                  '전투 해금 · 훈련 귀환 ${stage.at}회${stage.prerequisiteStageId == null ? '' : ' · 이전 장소 전투 승리'}',
                ),
                Text('권장 전투력 · ${stage.recommendedPower}'),
                const SizedBox(height: 8),
                for (final wave in stage.waves.asMap().entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(disableAnimations: true),
                          child: EnemySprite(
                            enemyId: wave.value.enemies.first.id,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${wave.key + 1}웨이브 · ${wave.value.enemies.map((enemy) => '${enemy.name} Lv.${enemy.level}').join(', ')}',
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '기록 · 별 ${progress?.stars ?? 0}/3 · 최고 턴 ${progress?.bestTurns ?? '—'}',
                ),
                if ((progress?.stars ?? 0) > 0)
                  Text('전투 기록 칭호 · ${stage.firstClearReward.badge}'),
                const SizedBox(height: 8),
                Text('입장 훈련권 · ${stage.entryTrainingPasses}회'),
                const Text('서버 보상 계획'),
                Text('첫 승리 · 배지 ${stage.firstClearReward.badge}'),
                Text('첫 승리 · 조각 ${stage.firstClearReward.fragments}개'),
                Text('반복 승리 · 조각 ${stage.repeatReward.fragments}개'),
                if (index == 0) const Text('첫 전투 승리 확정 동료 · 시작 신수와 다른 종 1마리'),
                const SizedBox(height: 8),
                const Text('지도 탐험 · 이야기 해금'),
                if (widget.gameStageRewardsEnabled &&
                    widget.gameRemoteClient?.auth.currentUser != null) ...[
                  Text(
                    _currentMapServerFirstClears == null
                        ? '계정 정식 첫 승리 · 정식 파견에서 기록을 확인해 주세요.'
                        : serverClear == null
                        ? '서버 첫 승리 · 아직 미지급'
                        : '계정 정식 첫 승리 · ${stage.firstClearReward.badge} · 조각 ${serverClear.awardedShards}개 지급',
                  ),
                  const Text('정식 서버 전투는 계정 전투권을 사용하며 기기 별점과 별도로 기록돼요.'),
                  Text(
                    serverRecord == null
                        ? '계정 전투 기록 · 아직 승리 기록 없음'
                        : '계정 전투 기록 · 최고 별 ${serverRecord.stars}/3 · 최저 ${serverRecord.bestTurns}턴',
                  ),
                ] else
                  const Text('서버 조각·배지 · 준비 중'),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, 1),
            child: const Text('전투 준비'),
          ),
          if (widget.gameStageRewardsEnabled && widget.gameRemoteClient != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 2),
              child: const Text('계정 정식 전투 준비'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    if (battleChoice == 1 && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BattlePreparationPage(store: widget.gameStore, stage: stage),
        ),
      );
    } else if (battleChoice == 2 && mounted) {
      _openServerGame(stageId: stage.id);
    }
  }

  Future<void> _editSquadSlot(int slot) async {
    final store = widget.gameStore;
    if (store.trainingEndsAt != null) return;
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      MediaQuery.textScalerOf(context).scale(20) >= 30
                          ? '편성할 신수'
                          : '스쿼드에 편성할 신수',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text('${slot + 1}번 자리 · 카드를 눌러 편성하거나 자리를 바꿔요.'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: store.owned.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.maxWidth < 290 ? 1 : 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent:
                          MediaQuery.textScalerOf(context).scale(12) >= 18
                          ? 198
                          : 166,
                    ),
                    itemBuilder: (context, index) {
                      final creature = store.owned[index];
                      final species = speciesById(creature.speciesId)!;
                      final assigned = store.squad.indexOf(creature.id);
                      final selected = assigned == slot;
                      return Material(
                        color: selected
                            ? const Color(0xFFE8F5FF)
                            : const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: ValueKey('squad-choice-${creature.id}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, creature.id),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF236B99)
                                    : const Color(0xFFCAD6E3),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: _SpeciesEmblem(
                                    species: species,
                                    size: 58,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${species.name} · #${index + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Lv ${creature.level} · ${creature.evolutionStage.label} · ${species.role}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                Text(
                                  assigned < 0
                                      ? '기기 보유 · 대기'
                                      : selected
                                      ? '현재 자리'
                                      : '편성 ${assigned + 1}번 · 선택하면 자리 교체',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF236B99),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (store.squad[slot] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context, ''),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('이 자리 비우기'),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selectedId == null || !mounted) return;
    try {
      final moved = selectedId.isEmpty
          ? await store.clearSquadSlot(slot)
          : await store.moveCreatureToSlot(selectedId, slot);
      if (!mounted) return;
      if (moved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedId.isEmpty
                  ? '${slot + 1}번 자리를 비웠어요.'
                  : '${slot + 1}번 자리에 편성했어요.',
            ),
          ),
        );
      }
      if (!moved && store.squad[slot] != selectedId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('편성을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('편성을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _assignCreature(CreatureInstance creature) async {
    final store = widget.gameStore;
    if (store.trainingEndsAt != null) return;
    final slot = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Text(
                '${speciesById(creature.speciesId)!.name}를 어디에 편성할까요?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (var index = 0; index < 5; index++)
              ListTile(
                leading: Icon(
                  index < 2
                      ? Icons.shield_outlined
                      : Icons.auto_awesome_outlined,
                ),
                title: Text('${index + 1}번 · ${index < 2 ? '전열' : '후열'}'),
                subtitle: Text(
                  store.squad[index] == null
                      ? '빈 자리'
                      : speciesById(
                          store.owned
                              .firstWhere(
                                (member) => member.id == store.squad[index],
                              )
                              .speciesId,
                        )!.name,
                ),
                trailing: store.squad[index] == creature.id
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => Navigator.pop(sheetContext, index),
              ),
          ],
        ),
      ),
    );
    if (slot == null || !mounted || store.squad[slot] == creature.id) return;
    final moved = await store.moveCreatureToSlot(creature.id, slot);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(moved ? '${slot + 1}번 자리에 편성했어요.' : '편성을 저장하지 못했어요.'),
      ),
    );
  }

  Future<void> _select(CreatureSpecies species) async {
    final change = widget.gameStore.hasStarter;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${species.name}와 함께할까요?'),
        content: Text(
          change
              ? '현재 시작 동료를 바꿉니다. 편성된 자리의 동료도 함께 바뀝니다.'
              : '첫 신수로 ${species.name}를 맞이하고 스쿼드의 첫 칸에 편성합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('선택하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final saved = change
          ? await widget.gameStore.changeStarter(species.id)
          : await widget.gameStore.chooseStarter(species.id);
      if (!mounted) return;
      if (saved) {
        setState(() {
          changingStarter = false;
          _section = 2;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  void _showDexDetail(CreatureSpecies species) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StreamBuilder<AuthState>(
        stream: widget.gameRemoteClient?.auth.onAuthStateChange,
        builder: (context, _) {
          final serverGame = _currentServerGame;
          if (!widget.gameStore.discoveredSpeciesIds.contains(species.id) &&
              !(serverGame?.discoveredSpeciesIds.contains(species.id) ??
                  false)) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '미발견 신수',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF12202D),
                          BlendMode.srcIn,
                        ),
                        child: GameStaticSprite(
                          speciesId: species.id,
                          size: 154,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '아직 만나지 못한 동료예요.',
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dexAcquisitionHint(
                          species,
                          widget.gameStore.starterSpeciesId,
                          (widget
                                      .gameStore
                                      .stageProgress[firstForestStages.first.id]
                                      ?.stars ??
                                  0) >
                              0,
                          widget.gameDrawEnabled &&
                              widget.gameRemoteClient != null,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF8DCCA9)),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final serverOwned =
              serverGame?.owned
                  .where((creature) => creature.speciesId == species.id)
                  .toList() ??
              const <ServerCreature>[];
          final owned = widget.gameStore.owned
              .where((creature) => creature.speciesId == species.id)
              .toList();
          final ownedCount = owned.length;
          final highestLocalLevel = owned.fold<int>(
            0,
            (highest, creature) =>
                creature.level > highest ? creature.level : highest,
          );
          final highestServerLevel = serverOwned.fold<int>(
            0,
            (highest, creature) =>
                creature.level > highest ? creature.level : highest,
          );
          final displayLevel = highestLocalLevel > 0
              ? highestLocalLevel
              : highestServerLevel;
          final displayStage = evolutionStageForLevel(displayLevel);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '도감 기록',
                                  style: TextStyle(color: _muted),
                                ),
                                Center(
                                  child: SizedBox.square(
                                    dimension: 154,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        GameAmbientBackdrop(
                                          speciesId: species.id,
                                          size: 150,
                                          evolutionStage: displayStage,
                                        ),
                                        GameStaticSprite(
                                          speciesId: species.id,
                                          size: 150,
                                          evolutionStage: displayStage,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  species.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${species.rarity} · ${species.element} · ${species.role}',
                                  style: const TextStyle(color: _muted),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      '기기 보유 $ownedCount마리',
                                      style: const TextStyle(color: _muted),
                                    ),
                                    if (serverGame != null)
                                      Text(
                                        '계정 보유 ${serverOwned.length}마리',
                                        style: const TextStyle(color: _muted),
                                      ),
                                  ],
                                ),
                                if (highestLocalLevel == 0 &&
                                    highestServerLevel > 0 &&
                                    species.id == 'pebble_newt') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '계정 보유 외형 · ${displayStage.label} (Lv $highestServerLevel)',
                                    style: const TextStyle(
                                      color: Color(0xFF8DCCA9),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Text(
                                  species.description,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                ),
                                if (owned.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  const Text(
                                    '기기 보유 개체',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final (index, creature) in owned.indexed)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${index + 1}번 · ${creature.evolutionStage.label} · Lv ${creature.level} · '
                                            '${!widget.gameStore.squad.contains(creature.id) ? '대기' : '편성 ${widget.gameStore.squad.indexOf(creature.id) + 1}번'}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            '체력 ${BattleEngine.allyStatsFor(creature).hp} · 공격 ${BattleEngine.allyStatsFor(creature).attack} · '
                                            '${creature.level >= 6 ? '전투 성장 완료' : '전투 경험 ${creature.battleExperience}/3'}',
                                            style: const TextStyle(
                                              color: _muted,
                                            ),
                                          ),
                                          if (creature.nextEvolutionStage !=
                                              null)
                                            Text(
                                              '${creature.nextEvolutionStage!.label}까지 전투 경험 ${creature.experienceToNextEvolution} 더',
                                              style: const TextStyle(
                                                color: Color(0xFFFFD991),
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 12),
                                const Text(
                                  '성장 단계 비교',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '전투 경험 3마다 Lv 1 상승. 단계 보너스는 레벨 능력에 더해져요.',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                for (final stage
                                    in CreatureEvolutionStage.values)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color:
                                            highestLocalLevel > 0 &&
                                                evolutionStageForLevel(
                                                      highestLocalLevel,
                                                    ) ==
                                                    stage
                                            ? const Color(0xFF465370)
                                            : const Color(0xFF383E50),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Text(
                                          '${stage.label} · Lv ${stage.firstLevel}부터 · '
                                          '${stage == CreatureEvolutionStage.seed ? '기본 능력' : '체력 +${stage.bonusHp} · 공격 +${stage.bonusAttack}'}'
                                          '${highestLocalLevel > 0 && evolutionStageForLevel(highestLocalLevel) == stage ? ' · 현재 단계' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (serverOwned.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  const Text(
                                    '계정 정식 파견 동료',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final (index, creature)
                                      in serverOwned.indexed)
                                    Builder(
                                      builder: (_) {
                                        final stats = BattleEngine.allyStatsFor(
                                          CreatureInstance(
                                            id: creature.id,
                                            speciesId: creature.speciesId,
                                            level: creature.level,
                                            battleExperience:
                                                creature.battleExperience,
                                          ),
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${index + 1}번 · ${evolutionStageForLevel(creature.level).label} · Lv ${creature.level} · '
                                                '${serverGame!.squad.contains(creature.id) ? '편성 ${serverGame.squad.indexOf(creature.id) + 1}번' : '대기'}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              Text(
                                                '체력 ${stats.hp} · 공격 ${stats.attack} · '
                                                '${creature.level >= 6 ? '전투 성장 완료' : '전투 경험 ${creature.battleExperience}/3 · 다음 레벨까지 ${creature.experienceToNextLevel}'}',
                                                style: const TextStyle(
                                                  color: _muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFAAD7F3),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.gameStore,
    builder: (context, _) {
      final store = widget.gameStore;
      final chosen = store.owned.isEmpty
          ? null
          : speciesById(store.owned.first.speciesId);
      final serverGame = _currentServerGame;
      final mapServerFirstClears = _currentMapServerFirstClears;
      final discoveredIds = {
        ...store.discoveredSpeciesIds,
        ...?serverGame?.discoveredSpeciesIds,
      }.where((id) => speciesById(id) != null).toSet();
      final firstBattleWon =
          (store.stageProgress[firstForestStages.first.id]?.stars ?? 0) > 0;
      final dexSpecies = [
        ...allCreatureSpecies.where(
          (species) => discoveredIds.contains(species.id),
        ),
        ...allCreatureSpecies.where(
          (species) => !discoveredIds.contains(species.id),
        ),
      ];
      return Scaffold(
        backgroundColor: _background,
        bottomNavigationBar:
            chosen == null || changingStarter || store.loadFailed
            ? null
            : BottomNavigationBar(
                backgroundColor: const Color(0xFF283243),
                selectedItemColor: const Color(0xFFBCE6CF),
                unselectedItemColor: _muted,
                type: BottomNavigationBarType.fixed,
                selectedFontSize: 11,
                unselectedFontSize: 10,
                currentIndex: _section,
                onTap: _switchSection,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.flag_outlined),
                    label: '임무',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.map_outlined),
                    label: '모험',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.pets_outlined),
                    label: '신수',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.card_giftcard_outlined),
                    label: '보상',
                  ),
                ],
              ),
        body: ColoredBox(
          color: _background,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                key: ValueKey('game-section-$_section'),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                children: [
                  if (_section == 0 ||
                      chosen == null ||
                      changingStarter ||
                      store.loadFailed) ...[
                    const Text(
                      '탐험 기지',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '동료를 모으고, 숲으로 파견해 보세요.',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_section == 0 &&
                      chosen != null &&
                      !changingStarter &&
                      !store.loadFailed) ...[
                    _journeyPrompt(store),
                    const SizedBox(height: 16),
                  ],
                  if (store.loadFailed)
                    const _GamePanel(
                      child: Text(
                        '저장된 게임 자료를 읽지 못했습니다. 기존 자료를 덮어쓰지 않았어요.',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  else if (chosen == null || changingStarter) ...[
                    Text(
                      chosen == null ? '첫 신수 선택' : '다른 시작 신수 선택',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '마음에 드는 동료를 고르세요. 나중에 바꿀 수 있어요.',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 16),
                    ...starterSpecies.map(
                      (species) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StarterCard(
                          species: species,
                          selected: chosen?.id == species.id,
                          onSelect: () => _select(species),
                        ),
                      ),
                    ),
                    if (chosen != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFAAD7F3),
                        ),
                        onPressed: () =>
                            setState(() => changingStarter = false),
                        child: const Text('스쿼드로 돌아가기'),
                      ),
                  ] else ...[
                    if (_section == 2) ...[
                      const Text(
                        '나의 신수',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF35405E), Color(0xFF242D40)],
                          ),
                          border: Border.all(color: const Color(0xFF5B6D91)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 270;
                            final spriteSize = compact ? 108.0 : 128.0;
                            final stacked =
                                constraints.maxWidth < 230 ||
                                MediaQuery.textScalerOf(context).scale(24) >=
                                    40;
                            final sprite = SizedBox(
                              width: stacked ? 128 : spriteSize,
                              height: stacked ? 138 : (compact ? 122 : 138),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  GameAmbientBackdrop(
                                    speciesId: chosen.id,
                                    size: stacked ? 128 : spriteSize,
                                    evolutionStage:
                                        store.owned.first.evolutionStage,
                                  ),
                                  GameStaticSprite(
                                    speciesId: chosen.id,
                                    size: (stacked ? 128 : spriteSize) - 2,
                                  ),
                                ],
                              ),
                            );
                            Widget details() => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: stacked
                                  ? CrossAxisAlignment.center
                                  : CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '★ 첫 번째 동료',
                                  style: TextStyle(color: _muted),
                                ),
                                Text(
                                  chosen.name,
                                  textAlign: stacked ? TextAlign.center : null,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${chosen.element} · ${chosen.role}\nLv ${store.owned.first.level} · ${store.owned.first.evolutionStage.label}',
                                  textAlign: stacked ? TextAlign.center : null,
                                  style: const TextStyle(color: _muted),
                                ),
                              ],
                            );
                            if (stacked) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    sprite,
                                    const SizedBox(height: 8),
                                    details(),
                                  ],
                                ),
                              );
                            }
                            return Row(
                              children: [
                                sprite,
                                SizedBox(width: compact ? 10 : 12),
                                Expanded(child: details()),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '스쿼드 · ${store.squad.whereType<String>().length}/5',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        store.trainingEndsAt == null
                            ? '칸을 눌러 보유 신수를 편성하세요.'
                            : '훈련 파견 중에는 편성을 바꿀 수 없어요.',
                        style: const TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 300 ? 3 : 2;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 8) /
                              columns;
                          final largeText =
                              MediaQuery.textScalerOf(context).scale(12) >= 18;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(5, (index) {
                              final memberId = store.squad[index];
                              final member = store.owned
                                  .where((creature) => creature.id == memberId)
                                  .firstOrNull;
                              final species = member == null
                                  ? null
                                  : speciesById(member.speciesId);
                              return Material(
                                color: const Color(0xFF2B3245),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: store.trainingEndsAt == null
                                      ? () => _editSquadSlot(index)
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: width,
                                    height: largeText ? 182 : 128,
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: species == null
                                            ? const Color(0xFF48586A)
                                            : const Color(0xFF85B2D2),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${index + 1} · ${index < 2 ? '전열' : '후열'}',
                                          style: const TextStyle(
                                            color: _muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (species != null)
                                          _SpeciesEmblem(
                                            species: species,
                                            size: 54,
                                          )
                                        else
                                          const Icon(
                                            Icons.add,
                                            color: _muted,
                                            size: 31,
                                          ),
                                        const SizedBox(height: 3),
                                        Text(
                                          species?.name ?? '빈 자리',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      if (store.owned.length == 1)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFAAD7F3),
                            disabledForegroundColor: const Color(0xFF91A5B4),
                          ),
                          onPressed: store.trainingEndsAt == null
                              ? () => setState(() => changingStarter = true)
                              : null,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('시작 신수 바꾸기'),
                        ),
                    ],
                    if (_section == 0) ...[
                      const SizedBox(height: 18),
                      _TrainingRegion(
                        store: store,
                        onStart: () => _trainingAction(finish: false),
                        onFinish: () => _trainingAction(finish: true),
                      ),
                      if (widget.gameRemoteClient != null) ...[
                        const SizedBox(height: 16),
                        ServerExpeditionPanel(
                          client: widget.gameRemoteClient!,
                          gameStore: store,
                          onOpenAccount: widget.onOpenAccount,
                          drawEnabled: widget.gameDrawEnabled,
                          stageRewardsEnabled: widget.gameStageRewardsEnabled,
                          onStateChanged: _receiveServerGame,
                        ),
                      ],
                    ],
                    if (_section == 1) ...[
                      const SizedBox(height: 14),
                      TrainingJournal(
                        completed: store.trainingCompletions,
                        cleared: store.adventureClears,
                        stageProgress: store.stageProgress,
                        onMission: () => _switchSection(0),
                        hasAccountExpedition: widget.gameRemoteClient != null,
                        serverProgressLoaded: mapServerFirstClears != null,
                        serverFirstClears: mapServerFirstClears ?? const [],
                        onServerBattle:
                            widget.gameStageRewardsEnabled &&
                                widget.gameRemoteClient?.auth.currentUser !=
                                    null
                            ? _openServerGame
                            : null,
                        onExplore: _exploreStage,
                        onDetails: _showStageDetails,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '안개 강가 · 장소 기록 ${riverStages.where((stage) => (store.stageProgress[stage.id]?.clearCount ?? 0) > 0).length}/${riverStages.length} · 기기 전투 ${riverStages.where((stage) => (store.stageProgress[stage.id]?.stars ?? 0) > 0).length}/${riverStages.length}',
                        style: const TextStyle(
                          color: Color(0xFFFFD991),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      for (final stage in riverStages) ...[
                        const SizedBox(height: 14),
                        _RiverStageCard(
                          store: store,
                          stage: stage,
                          onExplore: _exploreRiverStage,
                          onServerBattle:
                              widget.gameStageRewardsEnabled &&
                                  widget.gameRemoteClient?.auth.currentUser !=
                                      null
                              ? (stageId) => _openServerGame(stageId: stageId)
                              : null,
                          serverFirstClears: mapServerFirstClears,
                        ),
                      ],
                    ],
                    if (_section == 2) ...[
                      const SizedBox(height: 24),
                      Text(
                        '보유 신수 · ${store.owned.length}/20',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '기기 이야기에서 보유한 동료예요. 카드를 눌러 전열·후열에 편성하세요.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(store.owned.length, (index) {
                            final creature = store.owned[index];
                            final species = speciesById(creature.speciesId)!;
                            final assigned = store.squad.indexOf(creature.id);
                            final columns = constraints.maxWidth < 290 ? 1 : 2;
                            return SizedBox(
                              width:
                                  (constraints.maxWidth - (columns - 1) * 10) /
                                  columns,
                              height:
                                  MediaQuery.textScalerOf(context).scale(12) >=
                                      18
                                  ? 242
                                  : 178,
                              child: Material(
                                color: _card,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: ValueKey(
                                    'owned-creature-${creature.id}',
                                  ),
                                  onTap: store.trainingEndsAt == null
                                      ? () => _assignCreature(creature)
                                      : null,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: assigned < 0
                                            ? const Color(0xFF55657A)
                                            : const Color(0xFF85B2D2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: _SpeciesEmblem(
                                            species: species,
                                            size: 68,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${species.name} · #${index + 1}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${species.rarity} · ${species.element} · ${species.role}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                        Text(
                                          'Lv ${creature.level} · ${creature.evolutionStage.label} · ${assigned < 0 ? '대기' : '편성 ${assigned + 1}번'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '도감 · ${discoveredIds.length}/${allCreatureSpecies.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        serverGame == null ? '기기에서 시작하거나 이야기 전투로 만난 종이에요.' : '기기 이야기와 계정 정식 파견의 발견 종을 함께 보여줘요. 보유·편성 자료는 따로 관리돼요.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      ...dexSpecies.map((species) {
                        final discovered = discoveredIds.contains(species.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _GamePanel(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showDexDetail(species),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (discovered)
                                        _SpeciesEmblem(
                                          species: species,
                                          size: 64,
                                        )
                                      else
                                        ColorFiltered(
                                          colorFilter: const ColorFilter.mode(
                                            Color(0xFF101D28),
                                            BlendMode.srcIn,
                                          ),
                                          child: _SpeciesEmblem(
                                            species: species,
                                            size: 64,
                                          ),
                                        ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              discovered ? species.name : '미발견',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              discovered
                                                  ? '${species.rarity} · ${species.element} · ${species.role}'
                                                  : '획득 단서',
                                              style: const TextStyle(
                                                color: _muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        discovered
                                            ? Icons.chevron_right
                                            : Icons.search,
                                        color: discovered
                                            ? const Color(0xFFB8E2ED)
                                            : _muted,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    discovered
                                        ? species.description
                                        : _dexAcquisitionHint(
                                            species,
                                            store.starterSpeciesId,
                                            firstBattleWon,
                                            widget.gameDrawEnabled &&
                                                widget.gameRemoteClient != null,
                                          ),
                                    style: TextStyle(
                                      color: discovered
                                          ? _muted
                                          : const Color(0xFF8DCCA9),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    if (_section == 3) ...[
                      const SizedBox(height: 18),
                      const Text(
                        '보상 창고',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '할 일과 실천으로 얻은 보상을 여기서 확인해요.',
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 14),
                      _GamePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '훈련 가능 ${store.trainingPasses}회',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '할 일 완료 +2회 · 목표 MINI +1 / MORE +2 / MAX +3',
                              style: TextStyle(color: _muted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '지급 기록 ${store.rewardGrants.length}건 · 훈련 귀환 ${store.trainingCompletions}회',
                              style: const TextStyle(color: _muted),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '훈련 파견 1회 또는 기기 전투 입장에 훈련권 1회를 써요.',
                              style: TextStyle(color: _muted),
                            ),
                            TextButton.icon(
                              onPressed: () => _switchSection(0),
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text('임무에서 훈련하기'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _GamePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '행동별 보상',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '할 일 완료 · 훈련권 +2회',
                              style: TextStyle(color: Colors.white),
                            ),
                            Text(
                              '목표 MINI · +1회 · XP +10',
                              style: TextStyle(color: _muted),
                            ),
                            Text(
                              '목표 MORE · +2회 · XP +20',
                              style: TextStyle(color: _muted),
                            ),
                            Text(
                              '목표 MAX · +3회 · XP +30',
                              style: TextStyle(color: _muted),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '할 일 보상은 하루 5개까지, 지나간 기록은 최근 14일까지 지급해요. 같은 완료를 수정해도 훈련권은 다시 지급하지 않아요.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (serverGame != null) ...[
                        const SizedBox(height: 12),
                        _GamePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '계정 정식 모험',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '뽑기 조각 ${serverGame.drawShards}개 · 전투권 ${serverGame.battlePasses}개',
                                style: const TextStyle(color: _muted),
                              ),
                              const Text(
                                '기기 훈련권과 계정 전투권은 별도로 관리돼요.',
                                style: TextStyle(color: _muted),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '동기화한 할 일로 전투권 +2개 · 정식 전투 입장에 1개 사용',
                                style: TextStyle(color: _muted),
                              ),
                              const Text(
                                '정식 파견은 별도 입장권 없이 하루 3회 · 귀환마다 조각 +1개',
                                style: TextStyle(color: _muted),
                              ),
                              const Text(
                                '첫 승리 조각 1·1·2개 · 조각 3개로 무료 뽑기',
                                style: TextStyle(color: _muted),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                serverGame.activeExpedition == null
                                    ? '정식 파견 · 대기 중 (${serverGame.todayStarts}/3회 출발)'
                                    : DateTime.now().toUtc().isBefore(
                                        serverGame.activeExpedition!.readyAt,
                                      )
                                    ? '정식 파견 중 · 귀환 뒤 조각 1개 수령'
                                    : '정식 파견 귀환 보상 · 수령 가능',
                                style: const TextStyle(
                                  color: Color(0xFFAAD7F3),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '정식 첫 승리 보상 ${firstForestStages.where((stage) => serverGame.stageFirstClears.any((clear) => clear.stageId == stage.id)).length}/${firstForestStages.length}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              for (final stage in firstForestStages)
                                Text(
                                  serverGame.stageFirstClears.any(
                                        (clear) => clear.stageId == stage.id,
                                      )
                                      ? '${stage.place} · 지급 완료'
                                      : '${stage.place} · 첫 승리 전 · 조각 ${stage.firstClearReward.fragments}개',
                                  style: const TextStyle(color: _muted),
                                ),
                              TextButton.icon(
                                onPressed: () => _switchSection(1),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('모험 지도 보기'),
                              ),
                              TextButton.icon(
                                onPressed: _loadServerGame,
                                icon: const Icon(Icons.refresh),
                                label: const Text('계정 보상 새로고침'),
                              ),
                              TextButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => GameRewardLedgerPage(
                                      client: widget.gameRemoteClient!,
                                      taskTitles: {
                                        for (final task
                                            in widget.growthStore?.tasks ?? [])
                                          task.id: task.title,
                                      },
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text('계정 지급·사용 원장'),
                              ),
                            ],
                          ),
                        ),
                      ] else if (widget.gameRemoteClient != null) ...[
                        const SizedBox(height: 12),
                        const _GamePanel(
                          child: Text(
                            '계정 정식 모험의 전투권·조각은 로그인 후 확인할 수 있어요. 정식 파견에는 별도 파견권이 없어요.',
                            style: TextStyle(color: _muted),
                          ),
                        ),
                      ],
                      if (store.rewardGrants.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '최근 지급',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _RewardHistoryPage(
                                    grants: store.rewardGrants,
                                    growth: widget.growthStore,
                                  ),
                                ),
                              ),
                              child: const Text('전체 보기'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final grant in store.rewardGrants.reversed.take(5))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${grant.activityDay ?? '과거 기록'} · ${_rewardSourceTitle(grant, widget.growthStore)} · 훈련 +${grant.trainingPasses}${grant.experience > 0 ? ' · XP +${grant.experience}' : ''}${grant.capped ? ' · 지급 제외' : ''}',
                              style: const TextStyle(color: _muted),
                            ),
                          ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RewardHistoryPage extends StatelessWidget {
  const _RewardHistoryPage({required this.grants, required this.growth});

  final List<RewardGrant> grants;
  final GrowthStore? growth;

  @override
  Widget build(BuildContext context) {
    final newest = grants.reversed.toList(growable: false);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF203149),
        foregroundColor: Colors.white,
        title: const Text('훈련권 지급 내역'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: newest.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                final earned = grants.fold<int>(
                  0,
                  (sum, grant) => sum + grant.trainingPasses,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '기록 ${grants.length}건 · 지급된 훈련권 $earned회\n'
                    '이 내역은 획득 기록이에요. 현재 잔액은 보상 탭에서 확인해요.',
                    style: const TextStyle(color: _muted),
                  ),
                );
              }
              final grant = newest[index - 1];
              final time = grant.grantedAt.toUtc().add(
                const Duration(hours: 9),
              );
              final timeLabel =
                  '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
              return _GamePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rewardSourceTitle(grant, growth),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${grant.activityDay ?? '날짜 미상'} · ${_rewardKindLabel(grant.kind)}',
                      style: const TextStyle(color: _muted),
                    ),
                    Text(
                      '훈련권 +${grant.trainingPasses}${grant.experience > 0 ? ' · 목표 XP +${grant.experience}' : ''}',
                      style: const TextStyle(color: Color(0xFFBCE6CF)),
                    ),
                    if (grant.capped)
                      Text(
                        '훈련권 지급 제외 · ${_rewardCapReason(grant)}',
                        style: const TextStyle(color: Color(0xFFFFD991)),
                      ),
                    Text(
                      grant.grantedAt.year <= 1970
                          ? '이전 버전에서 가져온 지급 기록'
                          : '지급 시각 · $timeLabel',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TrainingRegion extends StatelessWidget {
  const _TrainingRegion({
    required this.store,
    required this.onStart,
    required this.onFinish,
  });

  final GameStore store;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final remaining = store.trainingRemaining();
    final ready = remaining == Duration.zero;
    final seconds = remaining == null
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();
    final progress = remaining == null
        ? 0.0
        : (1 -
                  remaining.inMilliseconds /
                      GameStore.trainingDuration.inMilliseconds)
              .clamp(0.0, 1.0);
    final travelerId = store.squad.whereType<String>().firstOrNull;
    final travelerSpeciesId = store.owned
        .where((creature) => creature.id == travelerId)
        .firstOrNull
        ?.speciesId;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF29413E), Color(0xFF263542)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF5D8D79)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 116,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    const GameForestDrift(),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xB70B2027),
                            Colors.transparent,
                            Color(0x750B2027),
                          ],
                        ),
                      ),
                    ),
                    const GameForestFireflies(),
                    const Positioned(
                      left: 12,
                      right: 12,
                      top: 10,
                      child: Text(
                        '첫 지역 · 훈련 길',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (remaining != null && travelerSpeciesId != null)
                      Positioned(
                        left: 14,
                        bottom: 1,
                        child: GameStaticSprite(
                          speciesId: travelerSpeciesId,
                          size: 64,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(20) >= 30;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.forest, color: Color(0xFF8DCCA9)),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          '솔바람 숲',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!largeText)
                        const Text(
                          '훈련  ·  30초',
                          style: TextStyle(color: _muted),
                        ),
                    ],
                  ),
                  if (largeText)
                    const Padding(
                      padding: EdgeInsets.only(left: 33, top: 4),
                      child: Text(
                        '훈련  ·  30초',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF172B33),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.route_outlined, color: Color(0xFF8DCCA9), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '훈련으로 새 장소를 열어요. 신수·조각은 여기서 발견하지 않아요.',
                    style: TextStyle(color: _muted, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '할 일 +2회(하루 5건까지) · 목표 MINI +1 / MORE +2 / MAX +3',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 4),
          const Text('귀환 1·3·7회에 새 장소가 열려요.', style: TextStyle(color: _muted)),
          const SizedBox(height: 16),
          Text(
            '남은 훈련 ${store.trainingPasses}회',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (remaining == null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                disabledBackgroundColor: const Color(0xFF526D81),
                disabledForegroundColor: Colors.white70,
              ),
              onPressed: store.trainingPasses > 0 ? onStart : null,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('훈련 파견 출발'),
            )
          else ...[
            Text(
              ready ? '동료가 돌아왔어요.' : '귀환까지 $seconds초',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFF48586A),
              color: const Color(0xFF8DCCA9),
            ),
            if (ready) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.home_outlined),
                label: const Text('귀환 확인'),
              ),
            ],
          ],
          if (remaining == null && store.trainingPasses == 0) ...[
            const SizedBox(height: 8),
            const Text(
              '오늘 탭에서 할 일을 마치거나 목표를 실천하면 훈련할 수 있어요.',
              style: TextStyle(color: _muted),
            ),
          ],
          if (store.trainingCompletions > 0) ...[
            const SizedBox(height: 12),
            Text(
              '훈련 파견 ${store.trainingCompletions}회 완료',
              style: const TextStyle(color: _muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiverStageCard extends StatelessWidget {
  const _RiverStageCard({
    required this.store,
    required this.stage,
    this.onExplore,
    this.onServerBattle,
    this.serverFirstClears,
  });

  final GameStore store;
  final AdventureStage stage;
  final ValueChanged<AdventureStage>? onExplore;
  final ValueChanged<String>? onServerBattle;
  final List<ServerStageFirstClear>? serverFirstClears;

  @override
  Widget build(BuildContext context) {
    final unlocked =
        store.trainingCompletions >= stage.at &&
        (store.stageProgress[stage.prerequisiteStageId]?.stars ?? 0) > 0;
    final progress = store.stageProgress[stage.id];
    return _GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            width: double.infinity,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: AssetImage(
                  stage.id == riverStages.last.id
                      ? 'assets/game/river-ferry-bg.png'
                      : stage.id == riverStages[1].id
                      ? 'assets/game/river-shallow-bg.png'
                      : 'assets/game/river-mist-bg.png',
                ),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Color(0x88202B35),
                  BlendMode.darken,
                ),
              ),
            ),
            child: Text(
              '안개 강가 · ${stage.place}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(stage.story, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Text(stage.strategy, style: const TextStyle(color: _muted)),
          if (stage.id == riverStages[1].id)
            const Text(
              '첫 승리 동료 · 자갈도롱뇽 1마리',
              style: TextStyle(color: Color(0xFFFFD991)),
            ),
          const SizedBox(height: 6),
          Text(
            unlocked
                ? '기기 전투 · 별 ${progress?.stars ?? 0}/3 · 최고 ${progress?.bestTurns ?? '—'}턴'
                : stage.id == riverStages.first.id
                ? '첫 숲길 보스 승리 후 열림'
                : '${allAdventureStages.firstWhere((item) => item.id == stage.prerequisiteStageId).place} 승리 후 열림',
            style: const TextStyle(color: Color(0xFFFFD991)),
          ),
          if ((progress?.clearCount ?? 0) > 0)
            const Text('기기 장소 기록 있음', style: TextStyle(color: _muted)),
          Text(
            '입장 훈련권 ${stage.entryTrainingPasses}장 · 권장 전투력 ${stage.recommendedPower} · 기기 전투 조각 없음',
            style: const TextStyle(color: _muted),
          ),
          if (onServerBattle != null)
            Text(
              serverFirstClears == null
                  ? '계정 정식 전투 기록을 불러오는 중이에요.'
                  : serverFirstClears!.any((clear) => clear.stageId == stage.id)
                  ? '계정 정식 첫 승리 기록 완료'
                  : '계정 정식 첫 승리 기록 없음',
              style: const TextStyle(color: _muted),
            ),
          const SizedBox(height: 8),
          if (onExplore != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAAD7F3),
                disabledForegroundColor: const Color(0xFF9CAAB6),
              ),
              onPressed: unlocked ? () => onExplore!(stage) : null,
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text('${stage.place} 탐색 이야기'),
            ),
          FilledButton.icon(
            onPressed: unlocked
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BattlePreparationPage(store: store, stage: stage),
                    ),
                  )
                : null,
            icon: const Icon(Icons.sports_martial_arts),
            label: Text('${stage.place} 전투 준비'),
          ),
          if (onServerBattle != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAAD7F3),
              ),
              onPressed: () => onServerBattle!(stage.id),
              icon: const Icon(Icons.cloud_outlined),
              label: Text('${stage.place} 계정 정식 전투'),
            ),
        ],
      ),
    );
  }
}

class TrainingJournal extends StatelessWidget {
  const TrainingJournal({
    super.key,
    required this.completed,
    required this.cleared,
    this.onMission,
    this.hasAccountExpedition = false,
    this.onExplore,
    this.onDetails,
    this.onServerBattle,
    this.serverFirstClears = const [],
    this.serverProgressLoaded = false,
    this.stageProgress = const {},
  });

  final int completed;
  final int cleared;
  final VoidCallback? onMission;
  final bool hasAccountExpedition;
  final ValueChanged<int>? onExplore;
  final ValueChanged<int>? onDetails;
  final VoidCallback? onServerBattle;
  final List<ServerStageFirstClear> serverFirstClears;
  final bool serverProgressLoaded;
  final Map<String, StageProgress> stageProgress;

  static const entries = firstForestStages;

  @override
  Widget build(BuildContext context) {
    final next = cleared < entries.length ? entries[cleared] : null;
    final battleCleared = entries
        .where((stage) => (stageProgress[stage.id]?.stars ?? 0) > 0)
        .length;
    final nextBattleIndex = entries.indexWhere(
      (stage) => (stageProgress[stage.id]?.stars ?? 0) == 0,
    );
    final nextBattle = nextBattleIndex < 0 ? null : entries[nextBattleIndex];
    return _GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route, color: Color(0xFF8DCCA9)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '숲길 지도 · 해금 $cleared/${entries.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            next == null
                ? '이야기 세 장소를 열었어요.'
                : completed >= next.at
                ? '다음 장소를 탐험할 수 있어요.'
                : '다음 장소: 훈련 ${next.at}회 · 현재 $completed회',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 4),
          Text(
            '기기 전투 클리어 $battleCleared/${entries.length}',
            style: const TextStyle(color: Color(0xFFFFD991)),
          ),
          if (onServerBattle != null) ...[
            const SizedBox(height: 4),
            Text(
              serverProgressLoaded
                  ? '계정 정식 첫 승리 ${entries.where((stage) => serverFirstClears.any((clear) => clear.stageId == stage.id)).length}/${entries.length} · 전투권과 보상은 계정에 저장'
                  : '계정 정식 전투 기록을 확인하는 중이에요.',
              style: const TextStyle(color: Color(0xFFAAD7F3)),
            ),
          ],
          if (onMission != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF253646),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF537C79)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '숲길 파견 거점',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '기기 훈련 · 30초 · 훈련권 1회 사용 · 귀환 1·3·7회에 지도 해금',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (hasAccountExpedition)
                    const Text(
                      '계정 정식 파견 · 10분 · 하루 3회 · 귀환 시 뽑기 조각 1개',
                      style: TextStyle(color: Color(0xFFAAD7F3), fontSize: 12),
                    ),
                  TextButton.icon(
                    onPressed: onMission,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('임무에서 파견하기'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Color(0xFF263342)),
              child: Column(
                children: [
                  _ForestRouteMap(
                    stages: entries,
                    cleared: cleared,
                    completed: completed,
                    stageProgress: stageProgress,
                    onDetails: onDetails,
                  ),
                  const SizedBox(height: 14),
                  for (var index = 0; index < entries.length; index++) ...[
                    _MapStop(
                      number: index + 1,
                      place: entries[index].place,
                      title: entries[index].title,
                      story: entries[index].story,
                      requiredReturns: entries[index].at,
                      boss: entries[index].boss,
                      stars: stageProgress[entries[index].id]?.stars ?? 0,
                      combatTitle: entries[index].firstClearReward.badge,
                      showServerProgress:
                          onServerBattle != null && serverProgressLoaded,
                      serverClear: serverFirstClears
                          .where((clear) => clear.stageId == entries[index].id)
                          .firstOrNull,
                      cleared: index < cleared,
                      current: index == cleared,
                      canExplore:
                          index == cleared && completed >= entries[index].at,
                      onExplore: onExplore == null
                          ? null
                          : () => onExplore!(index),
                      onDetails: onDetails == null
                          ? null
                          : () => onDetails!(index),
                    ),
                    if (index < entries.length - 1)
                      const SizedBox(
                        height: 28,
                        child: VerticalDivider(
                          color: Color(0xFF8DCCA9),
                          thickness: 2,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (nextBattle != null) ...[
            Text(
              '다음 전투 · ${nextBattle.place}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              completed < nextBattle.at
                  ? '훈련 귀환 ${nextBattle.at}회가 필요해요. 현재 $completed회예요.'
                  : nextBattleIndex > 0
                  ? '이전 장소의 전투를 이겼어요. 장소 정보에서 전투를 준비하세요.'
                  : '장소 정보에서 첫 전투를 준비하세요.',
              style: const TextStyle(color: _muted),
            ),
            if (onDetails != null)
              TextButton.icon(
                onPressed: () => onDetails!(nextBattleIndex),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFAAD7F3),
                ),
                icon: const Icon(Icons.sports_martial_arts),
                label: Text('${nextBattle.place} 전투 정보'),
              ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: const DecorationImage(
                  image: AssetImage('assets/game/dawn-lookout-bg.png'),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Color(0xB51B2130),
                    BlendMode.darken,
                  ),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '첫 숲길 완주',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '새벽 전망대 너머 안개 강가의 강가 입구가 열렸어요.',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '강가 입구 조건 · 첫 숲길 보스 전투 승리',
                    style: TextStyle(color: Color(0xFFFFD991)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            onServerBattle == null
                ? '세 장소 모두 장소 정보에서 기기 전투에 도전할 수 있어요. 기기 전투에서는 조각을 지급하지 않아요.'
                : '장소 정보의 기기 전투와 계정 정식 전투는 별도예요. 조각·배지는 정식 첫 승리에서만 받아요.',
            style: const TextStyle(color: _muted),
          ),
          if (onServerBattle != null)
            TextButton.icon(
              onPressed: onServerBattle,
              icon: const Icon(Icons.open_in_new),
              label: const Text('정식 서버 전투 보기'),
            ),
        ],
      ),
    );
  }
}

const _forestStageColors = <Color>[
  Color(0xFF83C8A1),
  Color(0xFFFFD47E),
  Color(0xFFF3A77F),
];

const _forestStageBackgrounds = <String>[
  'assets/game/moss-gate-bg.png',
  'assets/game/firefly-trail-bg.png',
  'assets/game/dawn-lookout-bg.png',
];

const _forestStageIcons = <IconData>[
  Icons.grass,
  Icons.flare,
  Icons.wb_twilight,
];

class _ForestStageBanner extends StatelessWidget {
  const _ForestStageBanner({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 110,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _forestStageBackgrounds[index],
            fit: BoxFit.cover,
            alignment: index == 0
                ? Alignment.bottomLeft
                : index == 1
                ? Alignment.center
                : Alignment.topRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xE611202A),
                  _forestStageColors[index].withValues(alpha: .18),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Icon(
              _forestStageIcons[index],
              size: 36,
              color: _forestStageColors[index],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ForestRouteMap extends StatelessWidget {
  const _ForestRouteMap({
    required this.stages,
    required this.cleared,
    required this.completed,
    required this.stageProgress,
    required this.onDetails,
  });

  final List<AdventureStage> stages;
  final int cleared;
  final int completed;
  final Map<String, StageProgress> stageProgress;
  final ValueChanged<int>? onDetails;

  static const _points = [
    Offset(0.18, 0.75),
    Offset(0.51, 0.46),
    Offset(0.81, 0.16),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      const height = 260.0;
      return Semantics(
        label: '첫 숲길 전체 지도',
        child: SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/game/pine-forest-bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x660B1A26)),
                ),
                Positioned.fill(
                  child: CustomPaint(painter: _ForestPathPainter()),
                ),
                for (var index = 0; index < stages.length; index++)
                  Positioned(
                    left: (width * _points[index].dx - 52).clamp(
                      0,
                      width - 104,
                    ),
                    top: height * _points[index].dy - 52,
                    width: 104,
                    height: 104,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _forestStageColors[index].withValues(alpha: .42),
                            _forestStageColors[index].withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (var index = 0; index < stages.length; index++)
                  Positioned(
                    left: (width * _points[index].dx - 38).clamp(0, width - 76),
                    top: height * _points[index].dy - 28,
                    width: 76,
                    child: InkWell(
                      key: ValueKey('forest-map-stage-${stages[index].id}'),
                      onTap: onDetails == null ? null : () => onDetails!(index),
                      borderRadius: BorderRadius.circular(28),
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  (stageProgress[stages[index].id]?.stars ??
                                          0) >
                                      0
                                  ? const Color(0xFFE6C982)
                                  : index < cleared
                                  ? const Color(0xFF8DCCA9)
                                  : index == cleared &&
                                        completed >= stages[index].at
                                  ? const Color(0xFFAAD7F3)
                                  : const Color(0xFF5B6872),
                              border: Border.all(
                                color: Colors.white70,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x99000000),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              index > cleared
                                  ? Icons.lock_outline
                                  : _forestStageIcons[index],
                              color: const Color(0xFF203040),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${index + 1} · ${stages[index].place}',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ForestPathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .18, size.height * .75)
      ..cubicTo(
        size.width * .41,
        size.height * .77,
        size.width * .24,
        size.height * .43,
        size.width * .51,
        size.height * .46,
      )
      ..cubicTo(
        size.width * .75,
        size.height * .50,
        size.width * .58,
        size.height * .15,
        size.width * .81,
        size.height * .16,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x990C1B25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE2D5A4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapStop extends StatelessWidget {
  const _MapStop({
    required this.number,
    required this.place,
    required this.title,
    required this.story,
    required this.requiredReturns,
    required this.boss,
    required this.stars,
    required this.combatTitle,
    required this.showServerProgress,
    required this.serverClear,
    required this.cleared,
    required this.current,
    required this.canExplore,
    required this.onExplore,
    required this.onDetails,
  });

  final int number;
  final String place;
  final String title;
  final String story;
  final int requiredReturns;
  final bool boss;
  final int stars;
  final String combatTitle;
  final bool showServerProgress;
  final ServerStageFirstClear? serverClear;
  final bool cleared;
  final bool current;
  final bool canExplore;
  final VoidCallback? onExplore;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(14) > 22;
      final marker = CircleAvatar(
        backgroundColor: cleared
            ? const Color(0xFF8DCCA9)
            : const Color(0xFF425466),
        foregroundColor: const Color(0xFF162632),
        child: Icon(
          cleared
              ? Icons.lock_open
              : current
              ? Icons.explore
              : Icons.lock_outline,
        ),
      );
      final placeLabel = Text(
        '$number · $place',
        style: const TextStyle(
          color: Color(0xFFAAD7F3),
          fontWeight: FontWeight.w700,
        ),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) placeLabel,
          if (!compact) const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (boss || cleared)
            Text(
              '${boss ? '보스 · ' : ''}기기 별 $stars/3',
              style: const TextStyle(color: Color(0xFFFFD991), fontSize: 12),
            ),
          if (stars > 0)
            Text(
              '기기 전투 칭호 · $combatTitle',
              style: const TextStyle(
                color: Color(0xFFFFD991),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (cleared && stars == 0)
            const Text(
              '기기 전투 미승리 · 장소 정보에서 도전하세요.',
              style: TextStyle(color: Color(0xFFFFD991), fontSize: 12),
            ),
          if (showServerProgress)
            Text(
              serverClear == null
                  ? '계정 정식 첫 승리 · 아직 없음'
                  : '계정 정식 첫 승리 ✓ · 조각 ${serverClear!.awardedShards}개 지급',
              style: TextStyle(
                color: serverClear == null ? _muted : const Color(0xFFAAD7F3),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            cleared
                ? story
                : current
                ? canExplore
                      ? '탐험 가능 · 동료와 함께 길을 열어요.'
                      : '진행 중 · 훈련 $requiredReturns회에 탐험 가능해요.'
                : '이전 장소를 마치면 열려요.',
            style: const TextStyle(color: _muted),
          ),
          if (onDetails != null)
            TextButton.icon(
              onPressed: onDetails,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAAD7F3),
              ),
              icon: const Icon(Icons.info_outline, size: 17),
              label: const Text('장소 정보'),
            ),
          if (canExplore && onExplore != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onExplore,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('탐험하기'),
            ),
          ],
        ],
      );
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xDD202B36),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cleared || current
                ? const Color(0xFF8DCCA9)
                : const Color(0xFF596A70),
          ),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      marker,
                      const SizedBox(width: 10),
                      Expanded(child: placeLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  details,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  marker,
                  const SizedBox(width: 10),
                  Expanded(child: details),
                ],
              ),
      );
    },
  );
}

class _GamePanel extends StatelessWidget {
  const _GamePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({
    required this.species,
    required this.selected,
    required this.onSelect,
  });

  final CreatureSpecies species;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => _GamePanel(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 270;
        final button = FilledButton(
          style: FilledButton.styleFrom(
            disabledBackgroundColor: const Color(0xFF455477),
            disabledForegroundColor: Colors.white,
          ),
          onPressed: selected ? null : onSelect,
          child: Text(selected ? '선택됨' : '선택'),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GameStaticSprite(
                  speciesId: species.id,
                  size: compact ? 72 : 84,
                ),
                SizedBox(width: compact ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        species.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${species.element} · ${species.role}',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[const SizedBox(width: 8), button],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              species.description,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            if (compact) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          ],
        );
      },
    ),
  );
}

class GameStaticSprite extends StatelessWidget {
  const GameStaticSprite({
    super.key,
    required this.speciesId,
    required this.size,
    this.evolutionStage = CreatureEvolutionStage.seed,
  });

  final String speciesId;
  final double size;
  final CreatureEvolutionStage evolutionStage;

  @override
  Widget build(BuildContext context) {
    final asset = switch (speciesId) {
      'pine_fox' => 'assets/game/pine-fox.png',
      'wave_otter' => 'assets/game/wave-otter.png',
      'pebble_newt' => switch (evolutionStage) {
        CreatureEvolutionStage.seed => 'assets/game/pebble-newt-seed.png',
        CreatureEvolutionStage.awakened =>
          'assets/game/pebble-newt-awakened.png',
        CreatureEvolutionStage.transcended =>
          'assets/game/pebble-newt-transcended.png',
      },
      _ => 'assets/game/star-crow.png',
    };
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        semanticLabel: '신수 이미지',
      ),
    );
  }
}

class _SpeciesEmblem extends StatelessWidget {
  const _SpeciesEmblem({required this.species, required this.size});

  final CreatureSpecies species;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (path, color) = switch (species.id) {
      'pine_fox' => ('assets/game/pine-fox.png', const Color(0xFF8DCCA9)),
      'wave_otter' => ('assets/game/wave-otter.png', const Color(0xFF8CCFF0)),
      'pebble_newt' => (
        'assets/game/pebble-newt-seed.png',
        const Color(0xFF7EDBD7),
      ),
      _ => ('assets/game/star-crow.png', const Color(0xFFD9B8F3)),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }
}
