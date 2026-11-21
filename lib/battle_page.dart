import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'enemy_sprite.dart';
import 'battle_sprite_effect.dart';
import 'game_motion_sprite.dart';
import 'models/adventure_stage.dart';
import 'models/battle_engine.dart';
import 'models/game_creature.dart';
import 'models/squad_readiness.dart';
import 'state/game_store.dart';

const _bg = Color(0xFF202330);
const _panel = Color(0xFF303544);
const _mint = Color(0xFF8DCCA9);

class BattlePreparationPage extends StatefulWidget {
  const BattlePreparationPage({
    super.key,
    required this.store,
    required this.stage,
  });

  final GameStore store;
  final AdventureStage stage;

  @override
  State<BattlePreparationPage> createState() => _BattlePreparationPageState();
}

class _BattlePreparationPageState extends State<BattlePreparationPage> {
  bool starting = false;

  Future<void> _editSlot(int slot) async {
    final store = widget.store;
    if (store.trainingEndsAt != null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('편성할 신수')),
            for (final creature in store.owned)
              ListTile(
                leading: const Icon(Icons.pets),
                title: Text(speciesById(creature.speciesId)!.name),
                subtitle: Text(
                  'Lv ${creature.level} · ${creature.evolutionStage.label} · ${speciesById(creature.speciesId)!.role}',
                ),
                trailing: store.squad[slot] == creature.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, creature.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await store.moveCreatureToSlot(selected, slot);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('편성을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _start() async {
    if (starting) return;
    setState(() => starting = true);
    try {
      final result = await widget.store.runForestBattle(widget.stage.id);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('입장 조건을 다시 확인해 주세요.')));
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BattlePlaybackPage(
            store: widget.store,
            stage: widget.stage,
            result: result,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전투 결과를 저장하지 못했어요. 훈련권은 사용되지 않았어요.')),
        );
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final stage = widget.stage;
      final power = BattleEngine.estimatedPower(store.squad, store.owned);
      final readiness = SquadReadiness.evaluate(
        stage,
        store.squad,
        store.owned,
      );
      final ready =
          store.trainingCompletions >= stage.at &&
          (stage.prerequisiteStageId == null ||
              (store.stageProgress[stage.prerequisiteStageId]?.stars ?? 0) >
                  0) &&
          store.trainingPasses >= stage.entryTrainingPasses &&
          store.squad.any((id) => id != null) &&
          store.trainingEndsAt == null;
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('전투 준비'),
          backgroundColor: _bg,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              onPressed: ready && !starting ? _start : null,
              style: FilledButton.styleFrom(
                disabledForegroundColor: Colors.white70,
                disabledBackgroundColor: const Color(0xFF43495A),
                minimumSize: const Size(0, 48),
              ),
              icon: const Icon(Icons.sports_martial_arts),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(starting ? '저장 중...' : '전투 시작'),
                  if (!starting)
                    const Text('훈련권 1회 사용', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _panelCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stage.strategy,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '우리 전투력 $power · 권장 ${stage.recommendedPower}',
                    style: const TextStyle(color: _mint),
                  ),
                  Text(
                    '권장 역할 · ${stage.recommendedRole}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    '입장 훈련권 ${stage.entryTrainingPasses}회 · 보유 ${store.trainingPasses}회',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    '전투 경험 보상 · 오늘 ${store.remainingStageExperienceWins(stage.id)}/5회 남음',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    stage.regionId == 'mist_river'
                        ? stage.strategy
                        : stage.id == firstForestStages.first.id
                        ? '첫 전투는 시작 동료 한 마리로도 도전할 수 있어요.'
                        : stage.id == firstForestStages[1].id
                        ? '두 번째 장소는 적이 둘씩 나와요. 첫 승리 동료를 빈칸에 편성해 보세요.'
                        : '마지막 장소는 보스전이에요. 동료를 키우고 전열 순서를 바꿔 보세요.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _panelCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '편성 점검',
                    style: TextStyle(color: _mint, fontWeight: FontWeight.w700),
                  ),
                  for (final advice in readiness.advice)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        advice,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    '전투력은 참고 수치이며 승리를 보장하지 않아요.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      '동료 능력과 성장',
                      style: TextStyle(color: Colors.white),
                    ),
                    children: [
                      for (final member in readiness.members)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${speciesById(member.speciesId)!.name} · Lv ${member.level}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '체력 ${BattleEngine.allyStatsFor(member).hp} · 공격 ${BattleEngine.allyStatsFor(member).attack} · 속도 ${BattleEngine.allyStatsFor(member).speed}\n${SquadReadiness.skillSummary(member.speciesId)}\n${member.level >= 6 ? '현재 최고 레벨' : '다음 레벨까지 경험 ${3 - member.battleExperience}'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '스쿼드 · 앞 2칸 전열 / 뒤 3칸 후열',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '전열은 받는 피해를 줄이고, 후열은 공격에 힘을 보태요. 칸을 눌러 편성을 바꿀 수 있어요.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 430 ? 3 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(5, (slot) {
                    final member = store.owned
                        .where((creature) => creature.id == store.squad[slot])
                        .firstOrNull;
                    final species = member == null
                        ? null
                        : speciesById(member.speciesId);
                    return SizedBox(
                      width: width,
                      child: OutlinedButton(
                        onPressed: store.trainingEndsAt == null
                            ? () => _editSlot(slot)
                            : null,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: slot < 2 ? _mint : const Color(0xFF85B2D2),
                          ),
                          padding: const EdgeInsets.all(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${slot < 2 ? '전열' : '후열'} ${slot + 1}',
                              style: const TextStyle(color: _mint),
                            ),
                            Text(
                              species?.name ?? '빈 자리',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                            if (species != null)
                              Text(
                                'Lv ${member!.level}\n${species.role}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 16),
            _panelCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '상대와 보상',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final wave in stage.waves.asMap().entries)
                    Text(
                      '${wave.key + 1}웨이브 · ${wave.value.enemies.map((enemy) => enemy.boss ? '보스 ${enemy.name}' : enemy.name).join(', ')}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '서버 첫 승리 계획 · ${stage.firstClearReward.badge}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    '조각 ${stage.firstClearReward.fragments}개 · 반복 조각 ${stage.repeatReward.fragments}개',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (stage.id == firstForestStages.first.id)
                    Text(
                      store.owned.any(
                            (creature) =>
                                creature.id == GameStore.firstForestCompanionId,
                          )
                          ? '첫 승리 동료 · 이미 합류했어요.'
                          : '첫 승리 확정 동료 · 시작 신수와 다른 종 1마리',
                      style: const TextStyle(color: _mint),
                    ),
                  const Text(
                    '조각과 배지 지급은 아직 준비 중이에요.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  if (stage.id == riverStages[1].id)
                    const Text(
                      '첫 승리 확정 동료 · 자갈도롱뇽 1마리 (보유 20마리 미만)',
                      style: TextStyle(color: _mint),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!ready)
              Text(
                store.trainingCompletions < stage.at
                    ? '훈련 ${stage.at}회 귀환 뒤 입장할 수 있어요.'
                    : stage.prerequisiteStageId != null &&
                          (store
                                      .stageProgress[stage.prerequisiteStageId]
                                      ?.stars ??
                                  0) ==
                              0
                    ? '이전 장소의 전투에서 먼저 승리해 주세요.'
                    : store.trainingPasses < stage.entryTrainingPasses
                    ? '훈련권이 부족해요. 오늘의 할 일이나 목표 실천으로 얻을 수 있어요.'
                    : store.trainingEndsAt != null
                    ? '훈련 파견이 끝난 뒤 편성을 확인해 주세요.'
                    : '스쿼드에 신수를 한 마리 이상 편성해 주세요.',
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
      );
    },
  );
}

class BattlePlaybackPage extends StatefulWidget {
  const BattlePlaybackPage({
    super.key,
    required this.store,
    required this.stage,
    required this.result,
  });
  final GameStore store;
  final AdventureStage stage;
  final BattleResult result;

  @override
  State<BattlePlaybackPage> createState() => _BattlePlaybackPageState();
}

class _BattlePlaybackPageState extends State<BattlePlaybackPage>
    with WidgetsBindingObserver {
  int frameIndex = 0;
  bool paused = false;
  bool fast = false;
  bool lowEffects = false;
  bool battleHaptics = false;
  bool _savingEffects = false;
  bool _savingHaptics = false;
  bool _foreground = true;
  bool showAllLog = false;
  Timer? timer;

  String _bossRecoveryHint() {
    final passHint = widget.store.trainingPasses == 0
        ? ' 훈련권이 없다면 오늘의 할 일이나 목표 실천으로 다시 얻으세요.'
        : '';
    final deployed = widget.store.owned
        .where((creature) => widget.store.squad.contains(creature.id))
        .toList();
    if (deployed.length < 2) {
      return '첫 장소에서 합류한 동료를 빈칸에 편성하세요. 두 마리 이상이 함께 싸워야 버틸 수 있어요.$passHint';
    }
    var neededWins = 0;
    for (final creature in deployed) {
      final neededExperience =
          ((4 - creature.level) * 3 - creature.battleExperience).clamp(0, 18);
      final wins = (neededExperience + 1) ~/ 2;
      if (wins > neededWins) neededWins = wins;
    }
    if (neededWins == 0) {
      return '현재 편성은 모두 Lv4 이상이에요. 전열 1·2번의 순서를 바꿔 다시 도전해 보세요.$passHint';
    }
    final remaining = widget.store.remainingStageExperienceWins(
      firstForestStages[1].id,
    );
    final dailyHint = remaining == 0
        ? '오늘 경험 보상은 모두 받았어요. 내일 이어서 성장해 보세요.'
        : neededWins > remaining
        ? '오늘 경험 보상은 $remaining회 남았어요. 나머지는 다음 날 이어서 받을 수 있어요.'
        : '오늘 경험 보상은 $remaining/5회 남았어요.';
    return '반딧불이 오솔길 전투를 이기면 편성 신수마다 경험 +2를 받아요. '
        '모두 Lv4에 도달하려면 약 $neededWins번 더 이겨야 해요. '
        '$dailyHint$passHint';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lowEffects = widget.store.reduceBattleEffects;
    battleHaptics = widget.store.battleHaptics;
    _tick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _toggleEffects() async {
    if (_savingEffects) return;
    final next = !lowEffects;
    setState(() {
      lowEffects = next;
      _savingEffects = true;
    });
    try {
      await widget.store.setReduceBattleEffects(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => lowEffects = !next);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('전투 효과 설정을 저장하지 못했어요.')));
    } finally {
      if (mounted) setState(() => _savingEffects = false);
    }
  }

  Future<void> _toggleHaptics() async {
    if (_savingHaptics) return;
    final next = !battleHaptics;
    setState(() {
      battleHaptics = next;
      _savingHaptics = true;
    });
    try {
      await widget.store.setBattleHaptics(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => battleHaptics = !next);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('전투 진동 설정을 저장하지 못했어요.')));
    } finally {
      if (mounted) setState(() => _savingHaptics = false);
    }
  }

  void _tick() {
    timer?.cancel();
    timer = Timer.periodic(Duration(milliseconds: fast ? 550 : 1100), (_) {
      if (!mounted || paused || !_foreground) return;
      if (frameIndex >= widget.result.frames.length - 1) {
        timer?.cancel();
      } else {
        final nextIndex = frameIndex + 1;
        setState(() => frameIndex = nextIndex);
        if (battleHaptics &&
            !kIsWeb &&
            !MediaQuery.disableAnimationsOf(context)) {
          final next = widget.result.frames[nextIndex];
          if (next.actorSlot != null) {
            unawaited(HapticFeedback.selectionClick());
          } else if (nextIndex == widget.result.frames.length - 1 &&
              widget.result.won) {
            unawaited(HapticFeedback.mediumImpact());
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final systemReducedMotion = MediaQuery.disableAnimationsOf(context);
    final reducedMotion = systemReducedMotion || lowEffects;
    final frame = widget.result.frames[frameIndex];
    final finished = frameIndex == widget.result.frames.length - 1;
    final previous = frameIndex > 0
        ? widget.result.frames[frameIndex - 1]
        : null;
    BattleFighterState? before(
      BattleFighterState fighter, {
      required bool ally,
    }) {
      if (previous == null || previous.wave != frame.wave) return null;
      return (ally ? previous.allies : previous.enemies)
          .where((item) => item.slot == fighter.slot && item.id == fighter.id)
          .firstOrNull;
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('${widget.stage.place} · 전투'),
        foregroundColor: Colors.white,
        backgroundColor: _bg,
      ),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: Stack(
          children: [
            Positioned.fill(
              child: GameForestDrift(
                assetPath: widget.stage.id == riverStages.last.id
                    ? 'assets/game/river-ferry-bg.png'
                    : widget.stage.id == riverStages[1].id
                    ? 'assets/game/river-shallow-bg.png'
                    : widget.stage.id == riverStages.first.id
                    ? 'assets/game/river-mist-bg.png'
                    : widget.stage.id == firstForestStages[2].id
                    ? 'assets/game/dawn-lookout-bg.png'
                    : widget.stage.id == firstForestStages[1].id
                    ? 'assets/game/firefly-trail-bg.png'
                    : 'assets/game/moss-gate-bg.png',
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: widget.stage.id == firstForestStages[2].id
                    ? const Color(0xB51B2130)
                    : const Color(0xD51B2130),
              ),
            ),
            if (widget.stage.id == firstForestStages[1].id)
              const Positioned.fill(
                child: ColoredBox(color: Color(0x323D2B66)),
              ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${frame.wave}/${widget.stage.waves.length}웨이브 · ${frame.round}턴',
                  style: const TextStyle(
                    color: _mint,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _panelCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '우리 스쿼드',
                        style: TextStyle(color: Colors.white),
                      ),
                      for (final ally in frame.allies)
                        _fighterRow(
                          ally,
                          ally: true,
                          before: before(ally, ally: true),
                          message: frame.message,
                          actorSlot: frame.actorSlot,
                          actorIsAlly: frame.actorIsAlly,
                          effect: frame.effect,
                          trigger: frameIndex,
                          victory: finished && widget.result.won,
                          reduceMotion: reducedMotion,
                        ),
                    ],
                  ),
                  translucent: true,
                ),
                const SizedBox(height: 12),
                _panelCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('상대', style: TextStyle(color: Colors.white)),
                      if (frame.enemies.isEmpty)
                        const Text(
                          '웨이브 종료',
                          style: TextStyle(color: Colors.white70),
                        ),
                      for (final enemy in frame.enemies)
                        _fighterRow(
                          enemy,
                          ally: false,
                          before: before(enemy, ally: false),
                          message: frame.message,
                          actorSlot: frame.actorSlot,
                          actorIsAlly: frame.actorIsAlly,
                          effect: frame.effect,
                          trigger: frameIndex,
                          victory: false,
                          reduceMotion: reducedMotion,
                        ),
                    ],
                  ),
                  translucent: true,
                ),
                const SizedBox(height: 12),
                _panelCard(
                  Text(
                    frame.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  translucent: true,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: finished
                          ? null
                          : () => setState(() => paused = !paused),
                      child: Text(paused ? '계속' : '일시정지'),
                    ),
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: finished
                          ? null
                          : () {
                              setState(() => fast = !fast);
                              _tick();
                            },
                      child: Text(fast ? '1배속' : '2배속'),
                    ),
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: finished
                          ? null
                          : () {
                              timer?.cancel();
                              setState(
                                () => frameIndex =
                                    widget.result.frames.length - 1,
                              );
                            },
                      child: const Text('결과까지 보기'),
                    ),
                    if (!systemReducedMotion)
                      OutlinedButton(
                        style: _battleControlStyle,
                        onPressed: _savingEffects ? null : _toggleEffects,
                        child: Text(lowEffects ? '일반 효과' : '효과 줄이기'),
                      ),
                    if (!kIsWeb && !systemReducedMotion)
                      OutlinedButton(
                        style: _battleControlStyle,
                        onPressed: _savingHaptics ? null : _toggleHaptics,
                        child: Text(battleHaptics ? '진동 끄기' : '진동 켜기'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (finished) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: widget.result.won
                            ? const [Color(0xFF304D4A), Color(0xFF263C44)]
                            : const [Color(0xFF533C47), Color(0xFF332E3D)],
                      ),
                      border: Border.all(
                        color: widget.result.won
                            ? const Color(0xFF8DCCA9)
                            : const Color(0xFFFFB4A2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          widget.result.won
                              ? Icons.auto_awesome
                              : Icons.shield_outlined,
                          size: 32,
                          color: widget.result.won
                              ? const Color(0xFFFFD991)
                              : const Color(0xFFFFB4A2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.result.won
                              ? '승리 · 별 ${widget.result.stars}/3 · ${widget.result.turns}턴'
                              : '패배 · 편성을 확인하고 다시 도전해 보세요.',
                          style: TextStyle(
                            color: widget.result.won
                                ? _mint
                                : const Color(0xFFFFB4A2),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.result.won) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            children: List.generate(
                              3,
                              (index) => Icon(
                                index < widget.result.stars
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: const Color(0xFFFFD991),
                                size: 27,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.result.won &&
                      widget.result.firstBattleClear &&
                      widget.stage.id == firstForestStages.last.id) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
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
                          Icon(Icons.wb_twilight, color: Color(0xFFFFD991)),
                          SizedBox(height: 8),
                          Text(
                            '첫 숲길 완주',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '새벽 전망대에 빛이 돌아왔어요. 동료와 함께 새 길을 바라봅니다.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.result.won &&
                      widget.result.firstBattleClear &&
                      widget.stage.id == riverStages.last.id)
                    _panelCard(
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.nights_stay, color: Color(0xFFFFD991)),
                          SizedBox(height: 8),
                          Text(
                            '안개 강가 완주',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '달빛 나루의 장막을 걷고 강 너머를 바라봅니다.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  if (widget.result.rewardSpeciesId case final speciesId?) ...[
                    _panelCard(
                      Row(
                        children: [
                          GameMotionSprite(speciesId: speciesId, size: 54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${speciesById(speciesId)!.name} 합류!\n보유 신수에서 빈칸에 편성해 보세요.',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      translucent: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.result.won && widget.result.firstBattleClear) ...[
                    _panelCard(
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium,
                            color: Color(0xFFFFD991),
                            size: 34,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '전투 기록 칭호 · ${widget.stage.firstClearReward.badge}',
                              style: const TextStyle(
                                color: Color(0xFFFFD991),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      translucent: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.result.won) ...[
                    Text(
                      widget.result.experiencePerCreature > 0
                          ? '편성 신수마다 전투 경험 +${widget.result.experiencePerCreature} · 경험 3마다 레벨 상승'
                          : '오늘 이 장소의 전투 경험 5회를 모두 받았어요. 별점 기록은 갱신돼요.',
                      style: const TextStyle(color: _mint),
                    ),
                    for (final creatureId in widget.result.leveledUpCreatureIds)
                      Text(
                        '${speciesById(widget.store.owned.firstWhere((creature) => creature.id == creatureId).speciesId)!.name} 레벨 상승!',
                        style: const TextStyle(color: _mint),
                      ),
                    for (final creatureId in widget.result.evolvedCreatureIds)
                      Text(
                        '${speciesById(widget.store.owned.firstWhere((creature) => creature.id == creatureId).speciesId)!.name} ${widget.store.owned.firstWhere((creature) => creature.id == creatureId).evolutionStage.label} 단계 도달!',
                        style: const TextStyle(
                          color: Color(0xFFFFD991),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                  Text(
                    !widget.result.won
                        ? '패배 기록이 저장됐어요. 입장 훈련권 1회가 사용됐고 조각 보상은 없어요.'
                        : widget.result.rewardSpeciesId == null
                        ? '전투 기록이 저장됐어요. 조각 보상은 아직 지급되지 않습니다.'
                        : '전투 기록과 새 동료가 저장됐어요. 조각 보상은 아직 지급되지 않습니다.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (!widget.result.won &&
                      widget.stage.id == firstForestStages[1].id &&
                      widget.store.squad.whereType<String>().length < 2)
                    const Text(
                      '첫 장소에서 합류한 신수를 빈칸에 편성하면 함께 싸울 수 있어요.',
                      style: TextStyle(color: _mint),
                    ),
                  if (!widget.result.won && widget.stage.boss) ...[
                    const SizedBox(height: 8),
                    _panelCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '다음 준비',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _bossRecoveryHint(),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            style: _battleControlStyle,
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => BattlePreparationPage(
                                      store: widget.store,
                                      stage: firstForestStages[1],
                                    ),
                                  ),
                                ),
                            child: const Text('오솔길 전투로 성장'),
                          ),
                        ],
                      ),
                      translucent: true,
                    ),
                  ],
                  if (widget.result.won) ...[
                    const SizedBox(height: 8),
                    _panelCard(
                      Text(
                        widget.stage.id == riverStages.first.id
                            ? '강가 입구를 돌파했어요. 다음 장소인 물안개 여울이 열렸어요.'
                            : widget.stage.id == riverStages[1].id
                            ? '물안개 여울을 건넜어요. 달빛 나루의 보스전에 도전할 수 있어요.'
                            : widget.stage.id == riverStages.last.id
                            ? '안개 강가의 세 전투를 마쳤어요. 계정 정식 전투와 다음 지역은 준비 중이에요.'
                            : widget.stage.id == firstForestStages.first.id
                            ? '다음 여정 · 새 동료를 스쿼드에 편성하고 훈련을 3회 귀환하면 반딧불이 오솔길 전투가 열려요.'
                            : widget.stage.id == firstForestStages[1].id
                            ? widget.store.trainingCompletions >=
                                      firstForestStages[2].at
                                  ? '다음 여정 · 새벽 전망대 보스전이 열렸어요. 동료를 키우고 전열을 확인해 도전하세요.'
                                  : '다음 여정 · 훈련을 7회 귀환하면 새벽 전망대 보스전에 도전할 수 있어요.'
                            : '첫 숲길의 세 전투를 마쳤어요. 안개 강가의 강가 입구가 열렸어요.',
                        style: const TextStyle(color: _mint),
                      ),
                      translucent: true,
                    ),
                  ],
                  if (widget.result.won &&
                      widget.stage.id == firstForestStages[1].id &&
                      widget.store.trainingCompletions >=
                          firstForestStages[2].at)
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BattlePreparationPage(
                            store: widget.store,
                            stage: firstForestStages[2],
                          ),
                        ),
                      ),
                      child: const Text('보스 전투 준비'),
                    ),
                  if (widget.result.won &&
                      widget.stage.id == firstForestStages.last.id)
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BattlePreparationPage(
                            store: widget.store,
                            stage: riverStages.first,
                          ),
                        ),
                      ),
                      child: const Text('강가 입구 전투 준비'),
                    ),
                  if (widget.result.won &&
                      widget.stage.id == riverStages.first.id)
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BattlePreparationPage(
                            store: widget.store,
                            stage: riverStages[1],
                          ),
                        ),
                      ),
                      child: const Text('물안개 여울 전투 준비'),
                    ),
                  if (widget.result.won && widget.stage.id == riverStages[1].id)
                    OutlinedButton(
                      style: _battleControlStyle,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => BattlePreparationPage(
                            store: widget.store,
                            stage: riverStages.last,
                          ),
                        ),
                      ),
                      child: const Text('달빛 나루 전투 준비'),
                    ),
                  OutlinedButton(
                    style: _battleControlStyle,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => BattlePreparationPage(
                          store: widget.store,
                          stage: widget.stage,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.result.won ? '편성을 바꿔 다시 도전' : '편성 확인하고 재도전',
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  '행동 기록',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (finished && widget.result.frames.length > 8)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => setState(() => showAllLog = !showAllLog),
                    child: Text(showAllLog ? '최근 기록만 보기' : '전체 기록 보기'),
                  ),
                for (final past
                    in widget.result.frames
                        .take(frameIndex + 1)
                        .toList()
                        .reversed
                        .take(showAllLog ? widget.result.frames.length : 8))
                  Text(
                    past.message,
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fighterRow(
    BattleFighterState fighter, {
    required bool ally,
    BattleFighterState? before,
    required String message,
    required int? actorSlot,
    required bool? actorIsAlly,
    required BattleActionEffect effect,
    required int trigger,
    required bool victory,
    required bool reduceMotion,
  }) {
    final difference = fighter.hp - (before?.hp ?? fighter.hp);
    final isActor = actorSlot == null
        ? message.startsWith('${fighter.name}의 ')
        : actorSlot == fighter.slot && actorIsAlly == ally;
    final motion = fighter.hp == 0
        ? GameSpriteMotion.defeat
        : victory
        ? GameSpriteMotion.victory
        : difference < 0
        ? GameSpriteMotion.hit
        : isActor
        ? GameSpriteMotion.attack
        : GameSpriteMotion.idle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: AnimatedContainer(
        key: ValueKey(
          'fighter-${ally ? 'ally' : 'enemy'}-${fighter.slot}-${fighter.id}',
        ),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: difference < 0
              ? const Color(0x44FF7D77)
              : difference > 0
              ? const Color(0x4475D9A0)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (ally && speciesById(fighter.id) != null)
                    GameMotionSprite(
                      speciesId: fighter.id,
                      size: 56,
                      motion: motion,
                      motionTrigger: trigger,
                      evolutionStage: evolutionStageForLevel(fighter.level),
                    )
                  else if (!ally &&
                      const {
                        'moss_spore',
                        'moss_guard',
                        'night_mushroom',
                        'firefly_wisp',
                        'wind_shadow',
                        'dawn_sentinel',
                        'river_mist_guard',
                        'river_stone_crab',
                        'river_reed_stalker',
                        'river_moon_ferryman',
                      }.contains(fighter.id))
                    EnemySprite(
                      enemyId: fighter.id,
                      motion: motion,
                      motionTrigger: trigger,
                    )
                  else
                    Icon(
                      ally ? Icons.pets : Icons.bug_report,
                      size: 30,
                      color: ally ? _mint : const Color(0xFFFFB4A2),
                    ),
                  Positioned.fill(
                    child: BattleSpriteEffect(
                      motion:
                          difference > 0 && effect == BattleActionEffect.heal
                          ? GameSpriteMotion.attack
                          : motion,
                      trigger: trigger,
                      towardBottom: ally,
                      effect: effect,
                      color: motion == GameSpriteMotion.hit
                          ? const Color(0xFFFFD6AB)
                          : switch (effect) {
                              BattleActionEffect.heal => const Color(
                                0xFF8DCCA9,
                              ),
                              BattleActionEffect.water => const Color(
                                0xFF8ADAF4,
                              ),
                              BattleActionEffect.star => const Color(
                                0xFFFFD991,
                              ),
                              BattleActionEffect.wind => const Color(
                                0xFFB9E8DD,
                              ),
                              BattleActionEffect.dawn => const Color(
                                0xFFFFD991,
                              ),
                              _ =>
                                ally
                                    ? const Color(0xFFCFB6FF)
                                    : const Color(0xFFFFB4A2),
                            },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fighter.boss ? '보스 · ${fighter.name}' : fighter.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(
                      'hp-${ally ? 'ally' : 'enemy'}-${fighter.slot}-${fighter.id}',
                    ),
                    tween: Tween<double>(
                      begin: before == null
                          ? fighter.hp / fighter.maxHp
                          : before.hp / fighter.maxHp,
                      end: fighter.hp / fighter.maxHp,
                    ),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 400),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      color: ally ? _mint : const Color(0xFFFFB4A2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${fighter.hp}/${fighter.maxHp}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (difference != 0)
                  Text(
                    difference > 0 ? '+$difference' : '$difference',
                    style: TextStyle(
                      color: difference > 0 ? _mint : const Color(0xFFFFB4A2),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _panelCard(Widget child, {bool translucent = false}) => Material(
  color: translucent ? const Color(0xDF303544) : _panel,
  borderRadius: BorderRadius.circular(12),
  child: SizedBox(
    width: double.infinity,
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  ),
);

final _battleControlStyle = OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  disabledForegroundColor: Colors.white54,
  side: const BorderSide(color: Colors.white70),
);
