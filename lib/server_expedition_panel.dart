import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/game_creature.dart';
import 'models/adventure_stage.dart';
import 'state/game_expedition_remote.dart';
import 'state/game_draw_coordinator.dart';
import 'state/game_battle_coordinator.dart';
import 'state/game_battle_remote.dart';
import 'state/game_store.dart';

class ServerExpeditionPanel extends StatefulWidget {
  const ServerExpeditionPanel({
    super.key,
    required this.client,
    required this.gameStore,
    this.initialStageId,
    this.onOpenAccount,
    this.onStateChanged,
    this.battleRemote,
    this.drawEnabled = false,
    this.stageRewardsEnabled = false,
  });

  final SupabaseClient client;
  final GameStore gameStore;
  final String? initialStageId;
  final VoidCallback? onOpenAccount;
  final ValueChanged<ServerGameState?>? onStateChanged;
  final GameBattleRemote? battleRemote;
  final bool drawEnabled;
  final bool stageRewardsEnabled;

  @override
  State<ServerExpeditionPanel> createState() => _ServerExpeditionPanelState();
}

class _ServerExpeditionPanelState extends State<ServerExpeditionPanel>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _ticker;
  ServerGameState? _game;
  bool _busy = false;
  bool _loading = false;
  String? _error;
  String? _loadedUserId;
  GameDrawResult? _lastDraw;
  bool _pendingDraw = false;
  ServerBattleResult? _lastBattle;
  int? _lastClaimedPasses;
  PendingServerBattle? _pendingBattle;
  int _refreshSerial = 0;
  final Stopwatch _serverElapsed = Stopwatch();
  final SharedPreferencesAsync _drawPrefs = SharedPreferencesAsync();
  final SharedPreferencesAsync _battlePrefs = SharedPreferencesAsync();

  GameExpeditionRemote get _remote => SupabaseGameExpeditionRemote(
    widget.client,
    drawEnabled: widget.drawEnabled,
    stageRewardsEnabled: widget.stageRewardsEnabled,
  );

  GameBattleRemote get _battleRemote =>
      widget.battleRemote ?? SupabaseGameBattleRemote(widget.client);

  void _publishState(ServerGameState? state, int serial, String? userId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          serial != _refreshSerial ||
          widget.client.auth.currentUser?.id != userId) {
        return;
      }
      widget.onStateChanged?.call(state);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = widget.client.auth.onAuthStateChange.listen((_) {
      _refresh();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _game?.activeExpedition != null) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.client.auth.currentUser != null) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final serial = ++_refreshSerial;
    final userId = widget.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _game = null;
          _error = null;
          _loading = false;
          _loadedUserId = null;
          _lastDraw = null;
          _pendingDraw = false;
          _lastBattle = null;
          _lastClaimedPasses = null;
          _pendingBattle = null;
          _serverElapsed.stop();
          _serverElapsed.reset();
        });
      }
      _publishState(null, serial, null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (_loadedUserId != userId) {
        _game = null;
        _lastDraw = null;
        _pendingDraw = false;
        _lastBattle = null;
        _lastClaimedPasses = null;
        _pendingBattle = null;
        _serverElapsed.stop();
        _serverElapsed.reset();
      }
    });
    if (_loadedUserId != userId) _publishState(null, serial, userId);
    try {
      final game = await _remote.load();
      final pendingDraw =
          widget.drawEnabled &&
          await GameDrawCoordinator(
            prefs: _drawPrefs,
            remote: _remote,
          ).hasPendingRequest(userId);
      final pendingBattle = widget.stageRewardsEnabled
          ? await GameBattleCoordinator(
              prefs: _battlePrefs,
              remote: _battleRemote,
            ).pending(userId)
          : null;
      if (!mounted ||
          serial != _refreshSerial ||
          widget.client.auth.currentUser?.id != userId) {
        return;
      }
      setState(() {
        _game = game;
        _loadedUserId = userId;
        _pendingDraw = pendingDraw;
        _pendingBattle = pendingBattle;
        _serverElapsed
          ..stop()
          ..reset()
          ..start();
      });
      _publishState(game, serial, userId);
    } catch (_) {
      if (!mounted ||
          serial != _refreshSerial ||
          widget.client.auth.currentUser?.id != userId) {
        return;
      }
      setState(() => _error = '서버 게임 자료를 읽지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    } finally {
      if (mounted &&
          serial == _refreshSerial &&
          widget.client.auth.currentUser?.id == userId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } on FunctionException catch (error) {
      if (mounted) setState(() => _error = _messageForBattle(error));
    } catch (_) {
      if (mounted) setState(() => _error = '서버 요청을 완료하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerStarter(String speciesId) async {
    final species = speciesById(speciesId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('서버 동료 등록'),
        content: Text(
          '${species?.name ?? '이 동료'}를 계정의 첫 신수로 등록할까요? 서버에 등록한 첫 신수는 바꿀 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _act(() => _remote.claimStarter(speciesId));
    }
  }

  Future<void> _draw() async {
    final userId = widget.client.auth.currentUser?.id;
    if (userId == null) return;
    final coordinator = GameDrawCoordinator(prefs: _drawPrefs, remote: _remote);
    await _act(() async {
      final result = await coordinator.draw(userId);
      if (mounted && widget.client.auth.currentUser?.id == userId) {
        setState(() => _lastDraw = result);
      }
    });
    final pendingDraw = await coordinator.hasPendingRequest(userId);
    if (mounted && widget.client.auth.currentUser?.id == userId) {
      setState(() => _pendingDraw = pendingDraw);
    }
  }

  Future<void> _battle(String stageId) async {
    final userId = widget.client.auth.currentUser?.id;
    if (userId == null) return;
    final coordinator = GameBattleCoordinator(
      prefs: _battlePrefs,
      remote: _battleRemote,
    );
    await _act(() async {
      final result = await coordinator.battle(userId, stageId);
      if (mounted && widget.client.auth.currentUser?.id == userId) {
        setState(() => _lastBattle = result);
      }
    });
    final pendingBattle = await coordinator.pending(userId);
    if (mounted && widget.client.auth.currentUser?.id == userId) {
      setState(() => _pendingBattle = pendingBattle);
    }
  }

  Future<void> _claimBattlePasses() async {
    final userId = widget.client.auth.currentUser?.id;
    if (userId == null) return;
    await _act(() async {
      final added = await _remote.claimTaskBattlePasses();
      if (mounted && widget.client.auth.currentUser?.id == userId) {
        setState(() => _lastClaimedPasses = added);
      }
    });
  }

  Future<void> _editServerSquadSlot(int slot) async {
    final game = _game;
    if (game == null || game.activeExpedition != null || _busy) return;
    final creatureId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('정식 파견 스쿼드 동료 선택')),
            ...game.owned.map(
              (creature) => ListTile(
                title: Text(
                  speciesById(creature.speciesId)?.name ?? creature.speciesId,
                ),
                subtitle: Text(
                  creature.level >= 6
                      ? 'Lv 6 · 전투 성장 완료'
                      : 'Lv ${creature.level} · 전투 경험 ${creature.battleExperience}/3 · 다음 레벨까지 ${creature.experienceToNextLevel}',
                ),
                trailing: game.squad[slot] == creature.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, creature.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (creatureId == null || !mounted) return;
    await _act(() => _remote.setSquadSlot(creatureId, slot + 1));
  }

  String _messageFor(PostgrestException error) => switch (error.message) {
    'daily expedition limit reached' => '오늘은 파견을 3번 마쳤어요. 내일 다시 출발할 수 있어요.',
    'expedition not ready' => '아직 귀환 시간이 되지 않았어요.',
    'expedition in progress' => '진행 중인 파견을 먼저 확인해 주세요.',
    'collection full' => '보유 신수가 20마리예요. 조각은 사용되지 않았어요.',
    'not enough draw shards' => '뽑기 조각이 3개 필요해요.',
    'sync tasks before claiming passes' => '계정에서 할 일·메모 동기화를 먼저 완료해 주세요.',
    _ => '서버 요청을 완료하지 못했어요. 다시 시도해 주세요.',
  };

  String _messageForBattle(FunctionException error) {
    if (error.status == 401) return '계정 로그인을 다시 확인해 주세요.';
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    final code = details is Map ? details['error'] : null;
    return switch (reason) {
      'daily battle limit reached' => '오늘 정식 전투 15회를 모두 마쳤어요. 내일 다시 도전해 주세요.',
      'battle already in progress' => '이전 정식 전투 결과를 먼저 확인해 주세요.',
      'previous stage required' => '앞 장소의 서버 전투에서 먼저 승리해 주세요.',
      'squad empty' => '정식 스쿼드에 신수를 한 마리 이상 편성해 주세요.',
      'battle request expired' => '이전 전투 시간이 지났어요. 새로 도전해 주세요.',
      'no battle passes' => '정식 전투권이 없어요. 할 일을 완료하고 계정에서 동기화한 뒤 전투권을 받으세요.',
      _ =>
        code == 'battle_attempt_expired'
            ? '이전 전투 시간이 지났어요. 새로 도전해 주세요.'
            : code == 'battle_start_failed'
            ? '정식 전투를 시작하지 못했어요. 장소와 편성을 확인해 주세요.'
            : '정식 전투 결과를 확인하지 못했어요. 이전 전투 결과 확인을 눌러 다시 시도해 주세요.',
    };
  }

  Widget _stageRewardRow(ServerGameState game, AdventureStage stage) {
    final reward = game.stageFirstClears
        .where((item) => item.stageId == stage.id)
        .firstOrNull;
    final record = game.stageRecords[stage.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${reward == null ? '○' : '✓'} ${stage.firstClearReward.badge} · ${reward == null
            ? '서버 미지급'
            : reward.awardedShards == 0
            ? '첫 승리 기록'
            : '조각 ${reward.awardedShards}개 지급'}'
        '${record == null ? '' : ' · 최고 별 ${record.stars}/3 · 최저 ${record.bestTurns}턴'}',
        style: TextStyle(
          color: reward == null
              ? const Color(0xFFC2D5D1)
              : const Color(0xFFFFD991),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final active = game?.activeExpedition;
    final serverNow = game?.serverNow.add(_serverElapsed.elapsed);
    final remaining = active == null || serverNow == null
        ? null
        : active.readyAt.difference(serverNow);
    final ready = remaining != null && remaining <= Duration.zero;
    final starter = game?.starterSpeciesId;
    final localStarter = widget.gameStore.starterSpeciesId;
    final selectedStage = allAdventureStages
        .where((stage) => stage.id == widget.initialStageId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF303544),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '정식 파견',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.client.auth.currentUser != null)
                IconButton(
                  tooltip: '서버 게임 새로고침',
                  onPressed: _busy || _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '솔바람 숲 · 10분 · 하루 3회 · 귀환 시 뽑기 조각 1개',
            style: TextStyle(color: Color(0xFFC2D5D1)),
          ),
          const SizedBox(height: 12),
          if (widget.client.auth.currentUser == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '계정에 로그인하면 정식 파견을 시작할 수 있어요.',
                  style: TextStyle(color: Colors.white),
                ),
                if (widget.onOpenAccount != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF93B3C4)),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('계정에서 로그인'),
                  ),
                ],
              ],
            )
          else if (_loading && game == null)
            const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '서버 게임 자료를 불러오는 중…',
                    style: TextStyle(color: Color(0xFFC2D5D1)),
                  ),
                ),
              ],
            )
          else if (game == null)
            OutlinedButton(
              onPressed: _loading ? null : _refresh,
              child: const Text('다시 불러오기'),
            )
          else ...[
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                Text(
                  '서버 동료 ${starter == null ? '없음' : speciesById(starter)?.name ?? starter}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  '뽑기 조각 ${game.drawShards}개',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  '오늘 파견 ${game.todayStarts}/3회',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            Text(
              '서버 보유 신수 ${game.ownedCount}/20',
              style: const TextStyle(color: Color(0xFFC2D5D1)),
            ),
            if (widget.stageRewardsEnabled) ...[
              if (selectedStage != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF263E4A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF83B7A4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지도에서 선택 · ${selectedStage.place}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '권장 전투력 ${selectedStage.recommendedPower} · ${selectedStage.firstClearReward.fragments == 0 ? '첫 승리 기록' : '첫 승리 조각 ${selectedStage.firstClearReward.fragments}개'} · ${selectedStage.firstClearReward.badge}',
                        style: const TextStyle(color: Color(0xFFC2D5D1)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pendingBattle != null
                            ? '이전 전투 결과를 먼저 확인해 주세요.'
                            : starter == null
                            ? '서버 시작 신수를 먼저 등록해 주세요.'
                            : game.battlePasses == 0
                            ? '전투권이 없어요. 아래에서 동기화한 할 일의 전투권을 받으세요.'
                            : selectedStage.prerequisiteStageId != null &&
                                  !game.stageFirstClears.any(
                                    (clear) =>
                                        clear.stageId ==
                                        selectedStage.prerequisiteStageId,
                                  )
                            ? '이전 장소의 계정 정식 전투에서 먼저 승리해야 해요.'
                            : '전투권 1장을 사용해 서버 편성으로 도전해요.',
                        style: const TextStyle(color: Color(0xFFFFD991)),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                starter == null ||
                                _pendingBattle != null ||
                                game.battlePasses == 0 ||
                                (selectedStage.prerequisiteStageId != null &&
                                    !game.stageFirstClears.any(
                                      (clear) =>
                                          clear.stageId ==
                                          selectedStage.prerequisiteStageId,
                                    ))
                            ? null
                            : () => _battle(selectedStage.id),
                        icon: const Icon(Icons.sports_martial_arts),
                        label: const Text('선택한 장소 정식 전투 시작'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '서버 첫 승리 보상 · ${firstForestStages.where((stage) => game.stageFirstClears.any((clear) => clear.stageId == stage.id)).length}/${firstForestStages.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '기기 전투 칭호와 별도로 서버가 확정한 보상이에요.',
                style: TextStyle(color: Color(0xFFC2D5D1)),
              ),
              const SizedBox(height: 8),
              for (final stage in firstForestStages)
                _stageRewardRow(game, stage),
              const SizedBox(height: 8),
              Text(
                '안개 강가 첫 승리 · ${riverStages.where((stage) => game.stageFirstClears.any((clear) => clear.stageId == stage.id)).length}/${riverStages.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final stage in riverStages) _stageRewardRow(game, stage),
              if (starter != null) ...[
                const SizedBox(height: 14),
                const Text(
                  '정식 숲길·강가 전투',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '서버 편성·레벨로 판정해요. 첫 승리 배지·동료와 전투 경험이 계정에 저장돼요. 숲길은 조각도 지급해요. 기기 지도 기록과는 별도예요. 하루 최대 15회 도전할 수 있어요.',
                  style: TextStyle(color: Color(0xFFC2D5D1)),
                ),
                const SizedBox(height: 6),
                Text(
                  '정식 전투권 ${game.battlePasses}/30 · 오늘 도전 ${game.todayBattleAttempts}/15',
                  style: const TextStyle(
                    color: Color(0xFFFFD991),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '할 일 완료 1회당 전투권 2장 · 계정에서 할 일·메모를 동기화한 뒤 받으세요. 로드맵 연결 행동은 제외돼요.',
                  style: TextStyle(color: Color(0xFFC2D5D1)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || game.battlePasses > 28
                          ? null
                          : _claimBattlePasses,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('동기화한 할 일에서 전투권 받기'),
                    ),
                    if (widget.onOpenAccount != null)
                      TextButton(
                        onPressed: widget.onOpenAccount,
                        child: const Text('계정 동기화로 이동'),
                      ),
                  ],
                ),
                if (game.battlePasses > 28)
                  const Text(
                    '전투권을 더 받으려면 잔액이 28장 이하여야 해요. 전투권을 사용한 뒤 다시 받으세요.',
                    style: TextStyle(color: Color(0xFFFFD991)),
                  ),
                if (_lastClaimedPasses != null)
                  Text(
                    _lastClaimedPasses! > 0
                        ? '전투권 $_lastClaimedPasses장을 받았어요.'
                        : game.battlePasses > 28
                        ? '전투권 잔액을 28장 이하로 만든 뒤 다시 받으세요.'
                        : '새로 받을 전투권이 없어요. 완료한 할 일을 동기화했는지 확인해 주세요.',
                    style: const TextStyle(color: Color(0xFFFFD991)),
                  ),
                const SizedBox(height: 4),
                const Text(
                  '장소별 경험 획득',
                  style: TextStyle(color: Color(0xFFC2D5D1)),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final stage in allAdventureStages)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF314C60),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${stage.place} ${game.todayStageExperienceWins[stage.id] ?? 0}/5',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_pendingBattle != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFFB8C8D5),
                      side: const BorderSide(color: Color(0xFF93B3C4)),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _battle(_pendingBattle!.stageId),
                    icon: const Icon(Icons.replay),
                    label: const Text('이전 정식 전투 결과 확인'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (
                        var index = 0;
                        index < firstForestStages.length;
                        index++
                      )
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: const Color(0xFF9CAAB6),
                            side: const BorderSide(color: Color(0xFF93B3C4)),
                          ),
                          onPressed:
                              _busy ||
                                  game.battlePasses == 0 ||
                                  (index > 0 &&
                                      !game.stageFirstClears.any(
                                        (item) =>
                                            item.stageId ==
                                            firstForestStages[index - 1].id,
                                      ))
                              ? null
                              : () => _battle(firstForestStages[index].id),
                          child: Text(
                            '${index + 1}. ${firstForestStages[index].place}',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                const Text(
                  '안개 강가 정식 전투',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  '강가 첫 승리는 배지로 기록돼요. 물안개 여울 첫 승리에는 자갈도롱뇽이 합류합니다. 조각은 지급하지 않아요.',
                  style: TextStyle(color: Color(0xFFC2D5D1)),
                ),
                if (_pendingBattle == null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final stage in riverStages)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: const Color(0xFF9CAAB6),
                            side: const BorderSide(color: Color(0xFF93B3C4)),
                          ),
                          onPressed:
                              _busy ||
                                  game.battlePasses == 0 ||
                                  !game.stageFirstClears.any(
                                    (item) =>
                                        item.stageId ==
                                        stage.prerequisiteStageId,
                                  )
                              ? null
                              : () => _battle(stage.id),
                          child: Text(stage.place),
                        ),
                    ],
                  ),
                if (_lastBattle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_lastBattle!.won ? '승리' : '패배'} · ${allAdventureStages.where((stage) => stage.id == _lastBattle!.stageId).firstOrNull?.place ?? '모험'} · 별 ${_lastBattle!.stars}/3 · ${_lastBattle!.turns}턴',
                    style: const TextStyle(
                      color: Color(0xFFFFD991),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_lastBattle!.firstClearShards == 0 ? '첫 승리 조각 없음' : '첫 승리 조각 +${_lastBattle!.firstClearShards}'} · 편성 신수 경험 +${_lastBattle!.experienceAwarded}',
                    style: const TextStyle(color: Color(0xFFC2D5D1)),
                  ),
                  if (_lastBattle!.companionSpeciesId != null)
                    Text(
                      '${speciesById(_lastBattle!.companionSpeciesId!)!.name} 합류!',
                      style: const TextStyle(color: Color(0xFFFFD991)),
                    ),
                  if (_lastBattle!.companionSpeciesId != null &&
                      game.squad.contains(null) &&
                      game.owned.any(
                        (creature) =>
                            creature.speciesId ==
                                _lastBattle!.companionSpeciesId &&
                            !game.squad.contains(creature.id),
                      ))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFAAD7F3),
                      ),
                      onPressed: _busy
                          ? null
                          : () =>
                                _editServerSquadSlot(game.squad.indexOf(null)),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('새 동료 편성하기'),
                    ),
                ],
              ],
            ],
            if (starter != null) ...[
              const SizedBox(height: 12),
              const Text(
                '정식 파견 스쿼드',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: List.generate(5, (slot) {
                  final creature = game.owned
                      .where((item) => item.id == game.squad[slot])
                      .firstOrNull;
                  return OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFFB8C8D5),
                      side: const BorderSide(color: Color(0xFF63768A)),
                    ),
                    onPressed: active == null && !_busy
                        ? () => _editServerSquadSlot(slot)
                        : null,
                    child: Text(
                      '${slot + 1} ${creature == null ? '빈 칸' : '${speciesById(creature.speciesId)?.name ?? creature.speciesId} Lv${creature.level}${creature.level >= 6 ? ' · 성장 완료' : ' · ${creature.battleExperience}/3'}'}',
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 12),
            if (starter == null && localStarter != null)
              FilledButton(
                onPressed: _busy ? null : () => _registerStarter(localStarter),
                child: Text('${speciesById(localStarter)?.name ?? '첫 동료'} 등록'),
              )
            else if (starter != null && active == null)
              FilledButton.icon(
                onPressed: _busy || game.todayStarts >= 3
                    ? null
                    : () => _act(_remote.start),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('정식 파견 출발'),
              )
            else if (active != null) ...[
              Text(
                ready ? '귀환할 준비가 됐어요.' : '귀환까지 ${remaining!.inMinutes + 1}분',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              if (ready)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          await _remote.claim(active.id);
                        }),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('귀환 보상 받기'),
                ),
            ],
            if (starter != null && localStarter != starter) ...[
              const SizedBox(height: 10),
              const Text(
                '이 계정의 정식 동료와 이 기기의 훈련 동료가 다릅니다. 정식 파견은 서버 동료로 진행해요.',
                style: TextStyle(color: Color(0xFFC2D5D1)),
              ),
            ],
            if (widget.drawEnabled && starter != null) ...[
              const SizedBox(height: 20),
              const Text(
                '무료 뽑기',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '조각 3개로 신수 한 마리. 기본 확률: 솔여우 50% · 파도수달 30% · 별까마귀 20%. 첫 뽑기와 5번째마다 미발견 신수가 있으면 보장합니다.',
                style: TextStyle(color: Color(0xFFC2D5D1)),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  disabledForegroundColor: const Color(0xFFB8C8D5),
                  disabledBackgroundColor: const Color(0xFF3D5066),
                ),
                onPressed:
                    _busy ||
                        (!_pendingDraw &&
                            (game.drawShards < 3 || game.ownedCount >= 20))
                    ? null
                    : _draw,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_pendingDraw ? '이전 뽑기 결과 확인' : '무료 뽑기 · 조각 3개'),
              ),
              if (_pendingDraw)
                const Text(
                  '같은 요청으로 결과를 확인해요. 조각은 중복 사용되지 않아요.',
                  style: TextStyle(color: Color(0xFFC2D5D1)),
                ),
              if (_lastDraw != null) ...[
                const SizedBox(height: 10),
                Text(
                  '새 동료: ${speciesById(_lastDraw!.speciesId)?.name ?? _lastDraw!.speciesId}${_lastDraw!.guaranteed ? ' · 미발견 보장' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Color(0xFFFFB4AB))),
            TextButton(
              onPressed: _loading ? null : _refresh,
              child: const Text('다시 불러오기'),
            ),
          ],
          if (_loading && game != null) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
