import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_creature.dart';
import '../models/adventure_stage.dart';
import '../models/battle_engine.dart';
import '../models/game_snapshot.dart';
import '../models/daily_content.dart';
import '../models/reward_grant.dart';

class GameStore extends ChangeNotifier {
  static const dailyStageExperienceLimit = 5;
  GameStore(this._prefs);

  static const _storageKey = 'game_collection_v1';
  static const _reduceBattleEffectsKey = 'game_reduce_battle_effects_v1';
  static const _battleHapticsKey = 'game_battle_haptics_v1';
  static const firstForestCompanionId = 'forest-gift-1';
  static const riverCompanionId = 'river-gift-1';
  final SharedPreferencesAsync _prefs;
  final List<CreatureInstance> _owned = [];
  final List<String?> _squad = List.filled(5, null);
  final Set<String> _discoveredSpeciesIds = {};
  bool _loadFailed = false;
  bool _reduceBattleEffects = false;
  bool _battleHaptics = false;
  DateTime? _trainingEndsAt;
  int _trainingCompletions = 0;
  int _adventureClears = 0;
  final Map<String, StageProgress> _stageProgress = {};
  int _trainingPasses = 0;
  final Set<String> _creditedTaskIds = {};
  final List<RewardGrant> _rewardGrants = [];
  bool _mutationInFlight = false;

  static const trainingDuration = Duration(seconds: 30);

  List<CreatureInstance> get owned => List.unmodifiable(_owned);
  String? get starterSpeciesId => _owned
      .where((creature) => creature.id == 'starter-1')
      .firstOrNull
      ?.speciesId;
  List<String?> get squad => List.unmodifiable(_squad);
  Set<String> get discoveredSpeciesIds =>
      Set.unmodifiable(_discoveredSpeciesIds);
  bool get hasStarter => _owned.isNotEmpty;
  bool get loadFailed => _loadFailed;
  bool get reduceBattleEffects => _reduceBattleEffects;
  bool get battleHaptics => _battleHaptics;

  Future<void> setReduceBattleEffects(bool value) async {
    if (_reduceBattleEffects == value) return;
    await _prefs.setBool(_reduceBattleEffectsKey, value);
    _reduceBattleEffects = value;
    notifyListeners();
  }

  Future<void> setBattleHaptics(bool value) async {
    if (_battleHaptics == value) return;
    await _prefs.setBool(_battleHapticsKey, value);
    _battleHaptics = value;
    notifyListeners();
  }

  DateTime? get trainingEndsAt => _trainingEndsAt;
  int get trainingCompletions => _trainingCompletions;
  int get adventureClears => _adventureClears;
  Map<String, StageProgress> get stageProgress =>
      Map.unmodifiable(_stageProgress);
  int get trainingPasses => _trainingPasses;
  List<RewardGrant> get rewardGrants => List.unmodifiable(_rewardGrants);

  Future<void> clearLocalData() async {
    if (_mutationInFlight) throw StateError('Game data is being updated');
    await _prefs.remove(_storageKey);
    await _prefs.remove(_reduceBattleEffectsKey);
    await _prefs.remove(_battleHapticsKey);
    _owned.clear();
    _squad.fillRange(0, _squad.length, null);
    _discoveredSpeciesIds.clear();
    _loadFailed = false;
    _reduceBattleEffects = false;
    _battleHaptics = false;
    _trainingEndsAt = null;
    _trainingCompletions = 0;
    _adventureClears = 0;
    _stageProgress.clear();
    _trainingPasses = 0;
    _creditedTaskIds.clear();
    _rewardGrants.clear();
    notifyListeners();
  }

  GameSnapshot? exportSnapshot() => _loadFailed || _owned.isEmpty
      ? null
      : GameSnapshot.fromJson({
          'version': 1,
          'owned': _owned.map((item) => item.toJson()).toList(),
          'squad': _squad,
          'discoveredSpeciesIds': _discoveredSpeciesIds.toList(),
          'trainingEndsAt': _trainingEndsAt?.toIso8601String(),
          'trainingCompletions': _trainingCompletions,
          'adventureClears': _adventureClears,
          'stageProgress': _stageProgress.map(
            (id, progress) => MapEntry(id, progress.toJson()),
          ),
          'trainingPasses': _trainingPasses,
          'creditedTaskIds': _creditedTaskIds.toList(),
          'rewardGrants': _rewardGrants.map((item) => item.toJson()).toList(),
        });

  /// Keep the current collection if this device has already chosen a starter.
  Future<bool> importIfEmpty(GameSnapshot snapshot) async {
    if (_loadFailed || _owned.isNotEmpty || _mutationInFlight) return false;
    final nextOwned = List<CreatureInstance>.from(snapshot.owned);
    final nextDiscovered = Set<String>.from(snapshot.discoveredSpeciesIds);
    if ((snapshot.stageProgress[firstForestStages.first.id]?.stars ?? 0) > 0) {
      final companion = _firstForestCompanion(nextOwned);
      if (companion != null) {
        nextOwned.add(companion);
        nextDiscovered.add(companion.speciesId);
      }
    }
    _mutationInFlight = true;
    try {
      final data = snapshot.toJson()
        ..['owned'] = nextOwned.map((creature) => creature.toJson()).toList()
        ..['discoveredSpeciesIds'] = nextDiscovered.toList();
      await _prefs.setString(_storageKey, jsonEncode(data));
      _owned.addAll(nextOwned);
      _squad.setAll(0, snapshot.squad);
      _discoveredSpeciesIds.addAll(nextDiscovered);
      _trainingEndsAt = snapshot.trainingEndsAt;
      _trainingCompletions = snapshot.trainingCompletions;
      _adventureClears = snapshot.adventureClears;
      _stageProgress
        ..clear()
        ..addAll(snapshot.stageProgress);
      _trainingPasses = snapshot.trainingPasses;
      _creditedTaskIds
        ..clear()
        ..addAll(snapshot.creditedTaskIds);
      _rewardGrants
        ..clear()
        ..addAll(snapshot.rewardGrants);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Duration? trainingRemaining({DateTime? now}) {
    final end = _trainingEndsAt;
    if (end == null) return null;
    final remaining = end.difference((now ?? DateTime.now()).toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> load() async {
    _reduceBattleEffects =
        await _prefs.getBool(_reduceBattleEffectsKey) ?? false;
    _battleHaptics = await _prefs.getBool(_battleHapticsKey) ?? false;
    final raw = await _prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['version'] != 1) {
        throw const FormatException('Invalid game data');
      }
      final items = data['owned'];
      final slots = data['squad'];
      final trainingDate = data['trainingEndsAt'];
      final completions = data['trainingCompletions'] ?? 0;
      final rawClears = data['adventureClears'];
      final clears =
          rawClears ??
          adventureTrainingThresholds.where((at) => completions >= at).length;
      final passes = data['trainingPasses'] ?? 0;
      final credited = data['creditedTaskIds'] ?? const [];
      final rawGrants = data['rewardGrants'] ?? const [];
      final rawStageProgress = data['stageProgress'];
      final discoveries = data['discoveredSpeciesIds'];
      if (items is! List ||
          slots is! List ||
          slots.length != 5 ||
          items.length > 20 ||
          (trainingDate != null &&
              (trainingDate is! String ||
                  DateTime.tryParse(trainingDate) == null)) ||
          completions is! int ||
          completions < 0 ||
          clears is! int ||
          clears < 0 ||
          clears > adventureTrainingThresholds.length ||
          (clears > 0 &&
              completions < adventureTrainingThresholds[clears - 1]) ||
          passes is! int ||
          passes < 0 ||
          passes > 100000 ||
          credited is! List ||
          credited.length > 100000 ||
          rawGrants is! List ||
          rawGrants.length > 100000 ||
          (discoveries != null && discoveries is! List)) {
        throw const FormatException('Invalid game collection');
      }
      final creatures = items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid creature');
        }
        return CreatureInstance.fromJson(item);
      }).toList();
      if (trainingDate != null &&
          (creatures.isEmpty || !slots.any((id) => id != null))) {
        throw const FormatException('Training without a creature');
      }
      final ids = creatures.map((creature) => creature.id).toSet();
      final discovered = discoveries == null
          ? creatures.map((creature) => creature.speciesId).toSet()
          : discoveries.toSet();
      final creditedIds = credited.toSet();
      final grants = rawGrants.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid reward grant');
        }
        return RewardGrant.fromJson(item);
      }).toList();
      final grantIds = grants.map((item) => item.sourceId).toSet();
      if (ids.length != creatures.length ||
          creditedIds.length != credited.length ||
          creditedIds.any(
            (id) => id is! String || id.isEmpty || id.length > 100,
          ) ||
          grantIds.length != grants.length ||
          discovered.any((id) => id is! String || speciesById(id) == null) ||
          !creatures.every(
            (creature) => discovered.contains(creature.speciesId),
          ) ||
          slots.any(
            (id) => id != null && (id is! String || !ids.contains(id)),
          ) ||
          slots.whereType<String>().toSet().length !=
              slots.whereType<String>().length) {
        throw const FormatException('Invalid squad');
      }
      for (final id in creditedIds.cast<String>()) {
        if (grantIds.add(id)) grants.add(RewardGrant.fromLegacyTaskId(id));
      }
      if (grants.length > 100000) {
        throw const FormatException('Too many reward grants');
      }
      final progress = readStageProgress(rawStageProgress, clears);
      _owned
        ..clear()
        ..addAll(creatures);
      _squad.setAll(0, slots.cast<String?>());
      _discoveredSpeciesIds
        ..clear()
        ..addAll(discovered.cast<String>());
      _trainingEndsAt = trainingDate == null
          ? null
          : DateTime.parse(trainingDate as String).toUtc();
      _trainingCompletions = completions;
      _adventureClears = clears;
      _stageProgress
        ..clear()
        ..addAll(progress);
      _trainingPasses = passes;
      _creditedTaskIds
        ..clear()
        ..addAll(creditedIds.cast<String>());
      _rewardGrants
        ..clear()
        ..addAll(grants);
      _loadFailed = false;
    } on FormatException {
      _loadFailed = true;
    } on TypeError {
      _loadFailed = true;
    }
    if (!_loadFailed &&
        (_stageProgress[firstForestStages.first.id]?.stars ?? 0) > 0) {
      try {
        await _grantFirstForestCompanionForPastWin();
      } catch (_) {
        // The existing save remains intact; the next load can retry the grant.
      }
    }
    notifyListeners();
  }

  CreatureInstance? _firstForestCompanion(List<CreatureInstance> owned) {
    if (owned.length >= 20 ||
        owned.any((creature) => creature.id == firstForestCompanionId)) {
      return null;
    }
    final starter = owned
        .where((creature) => creature.id == 'starter-1')
        .firstOrNull;
    if (starter == null) return null;
    final speciesId = firstForestCompanionSpeciesId(starter.speciesId);
    return CreatureInstance(
      id: firstForestCompanionId,
      speciesId: speciesId,
      level: 1,
    );
  }

  CreatureInstance? _riverCompanion(List<CreatureInstance> owned) {
    if (owned.length >= 20 ||
        owned.any((creature) => creature.id == riverCompanionId)) {
      return null;
    }
    return const CreatureInstance(
      id: riverCompanionId,
      speciesId: 'pebble_newt',
      level: 3,
    );
  }

  Future<void> _grantFirstForestCompanionForPastWin() async {
    final companion = _firstForestCompanion(_owned);
    if (companion == null) return;
    final nextOwned = [..._owned, companion];
    final nextDiscovered = {..._discoveredSpeciesIds, companion.speciesId};
    await _persist(
      nextOwned,
      _squad,
      trainingEndsAt: _trainingEndsAt,
      trainingCompletions: _trainingCompletions,
      discoveredSpeciesIds: nextDiscovered,
    );
    _owned.add(companion);
    _discoveredSpeciesIds.add(companion.speciesId);
  }

  Future<bool> chooseStarter(String speciesId) async {
    if (_loadFailed ||
        _mutationInFlight ||
        _owned.isNotEmpty ||
        !starterSpecies.any((species) => species.id == speciesId)) {
      return false;
    }
    const id = 'starter-1';
    final creature = CreatureInstance(id: id, speciesId: speciesId, level: 1);
    _mutationInFlight = true;
    try {
      await _persist(
        [creature],
        [id, null, null, null, null],
        trainingEndsAt: null,
        trainingCompletions: 0,
        discoveredSpeciesIds: {speciesId},
      );
      _owned.add(creature);
      _squad[0] = id;
      _discoveredSpeciesIds.add(speciesId);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<bool> changeStarter(String speciesId) async {
    if (_loadFailed ||
        _mutationInFlight ||
        _owned.length != 1 ||
        _owned.single.id != 'starter-1' ||
        _trainingEndsAt != null ||
        !starterSpecies.any((species) => species.id == speciesId) ||
        _owned.single.speciesId == speciesId) {
      return false;
    }
    final creature = CreatureInstance(
      id: 'starter-1',
      speciesId: speciesId,
      level: 1,
    );
    final discovered = {..._discoveredSpeciesIds, speciesId};
    _mutationInFlight = true;
    try {
      await _persist(
        [creature],
        _squad,
        trainingEndsAt: null,
        trainingCompletions: _trainingCompletions,
        discoveredSpeciesIds: discovered,
      );
      _owned[0] = creature;
      _discoveredSpeciesIds.add(speciesId);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<bool> moveCreatureToSlot(String creatureId, int slot) async {
    if (_loadFailed ||
        _trainingEndsAt != null ||
        _mutationInFlight ||
        slot < 0 ||
        slot >= _squad.length ||
        !_owned.any((creature) => creature.id == creatureId) ||
        _squad[slot] == creatureId) {
      return false;
    }
    final next = List<String?>.from(_squad);
    final oldSlot = next.indexOf(creatureId);
    final displaced = next[slot];
    next[slot] = creatureId;
    if (oldSlot >= 0) next[oldSlot] = displaced;
    _mutationInFlight = true;
    try {
      await _persist(
        _owned,
        next,
        trainingEndsAt: null,
        trainingCompletions: _trainingCompletions,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _squad.setAll(0, next);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<bool> clearSquadSlot(int slot) async {
    if (_loadFailed ||
        _trainingEndsAt != null ||
        _mutationInFlight ||
        slot < 0 ||
        slot >= _squad.length ||
        _squad[slot] == null) {
      return false;
    }
    final next = List<String?>.from(_squad);
    next[slot] = null;
    _mutationInFlight = true;
    try {
      await _persist(
        _owned,
        next,
        trainingEndsAt: null,
        trainingCompletions: _trainingCompletions,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _squad.setAll(0, next);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<bool> startTraining({DateTime? now}) async {
    if (_loadFailed ||
        _trainingPasses < 1 ||
        _owned.isEmpty ||
        !_squad.any((id) => id != null) ||
        _mutationInFlight ||
        _trainingEndsAt != null) {
      return false;
    }
    final end = (now ?? DateTime.now()).toUtc().add(trainingDuration);
    _mutationInFlight = true;
    try {
      await _persist(
        _owned,
        _squad,
        trainingEndsAt: end,
        trainingCompletions: _trainingCompletions,
        trainingPasses: _trainingPasses - 1,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _trainingEndsAt = end;
      _trainingPasses -= 1;
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<bool> finishTraining({DateTime? now}) async {
    if (_loadFailed ||
        _trainingEndsAt == null ||
        _mutationInFlight ||
        trainingRemaining(now: now) != Duration.zero) {
      return false;
    }
    final nextCount = _trainingCompletions + 1;
    _mutationInFlight = true;
    try {
      await _persist(
        _owned,
        _squad,
        trainingEndsAt: null,
        trainingCompletions: nextCount,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _trainingEndsAt = null;
      _trainingCompletions = nextCount;
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  /// A map place can be cleared after its training goal and the preceding
  /// place are complete. Clearing a place does not spend a training pass.
  Future<bool> clearAdventureStage(int stageIndex) async {
    if (_loadFailed ||
        _mutationInFlight ||
        _owned.isEmpty ||
        stageIndex != _adventureClears ||
        stageIndex < 0 ||
        stageIndex >= adventureTrainingThresholds.length ||
        _trainingCompletions < adventureTrainingThresholds[stageIndex]) {
      return false;
    }
    _mutationInFlight = true;
    try {
      final stageId = firstForestStages[stageIndex].id;
      final nextProgress = {
        ..._stageProgress,
        stageId: const StageProgress(clearCount: 1),
      };
      await _persist(
        _owned,
        _squad,
        trainingEndsAt: _trainingEndsAt,
        trainingCompletions: _trainingCompletions,
        adventureClears: _adventureClears + 1,
        stageProgress: nextProgress,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _adventureClears += 1;
      _stageProgress
        ..clear()
        ..addAll(nextProgress);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  /// Opens a river place's story without spending a training pass or
  /// changing the battle unlock chain.
  Future<bool> exploreRiverStage(String stageId) async {
    final stage = riverStages.where((item) => item.id == stageId).firstOrNull;
    if (stage == null ||
        _loadFailed ||
        _mutationInFlight ||
        _owned.isEmpty ||
        _trainingCompletions < stage.at ||
        (_stageProgress[stage.prerequisiteStageId]?.stars ?? 0) == 0 ||
        (_stageProgress[stageId]?.clearCount ?? 0) > 0) {
      return false;
    }
    _mutationInFlight = true;
    try {
      final nextProgress = {
        ..._stageProgress,
        stageId: const StageProgress(clearCount: 1),
      };
      await _persist(
        _owned,
        _squad,
        trainingEndsAt: _trainingEndsAt,
        trainingCompletions: _trainingCompletions,
        adventureClears: _adventureClears,
        stageProgress: nextProgress,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _stageProgress
        ..clear()
        ..addAll(nextProgress);
      notifyListeners();
      return true;
    } finally {
      _mutationInFlight = false;
    }
  }

  /// Resolves a playable device battle and saves cost and result
  /// together. The UI replays frames only after the save succeeds.
  int remainingStageExperienceWins(String stageId, {DateTime? now}) {
    final progress = _stageProgress[stageId];
    final today = _battleDay(now ?? DateTime.now());
    final earned = progress?.rewardDay == today
        ? progress!.rewardedWinsToday
        : 0;
    return dailyStageExperienceLimit - earned;
  }

  Future<BattleResult?> runForestBattle(String stageId, {DateTime? now}) async {
    final stageIndex = allAdventureStages.indexWhere(
      (stage) => stage.id == stageId,
    );
    if (stageIndex < 0) return null;
    final stage = allAdventureStages[stageIndex];
    if (_loadFailed ||
        _mutationInFlight ||
        _owned.isEmpty ||
        !_squad.any((id) => id != null) ||
        _trainingEndsAt != null ||
        _trainingCompletions < stage.at ||
        (stage.prerequisiteStageId != null &&
            (_stageProgress[stage.prerequisiteStageId]?.stars ?? 0) < 1) ||
        _trainingPasses < stage.entryTrainingPasses) {
      return null;
    }
    final result = BattleEngine.simulate(stage, _squad, _owned);
    if (result.frames.isEmpty) return null;
    final companion = !result.won
        ? null
        : stageIndex == 0
        ? _firstForestCompanion(_owned)
        : stage.id == riverStages[1].id
        ? _riverCompanion(_owned)
        : null;
    final deployed = _squad.whereType<String>().toSet();
    final previous = _stageProgress[stage.id];
    final today = _battleDay(now ?? DateTime.now());
    final rewardedToday = previous?.rewardDay == today
        ? previous!.rewardedWinsToday
        : 0;
    final experience = result.won && rewardedToday < dailyStageExperienceLimit
        ? (stageIndex + 1).clamp(1, 3)
        : 0;
    final nextOwned = [
      for (final creature in _owned)
        result.won && deployed.contains(creature.id)
            ? creature.earnBattleExperience(experience)
            : creature,
      ?companion,
    ];
    final leveledUpIds = [
      for (var index = 0; index < _owned.length; index++)
        if (nextOwned[index].level > _owned[index].level) _owned[index].id,
    ];
    final evolvedIds = [
      for (var index = 0; index < _owned.length; index++)
        if (nextOwned[index].evolutionStage != _owned[index].evolutionStage)
          _owned[index].id,
    ];
    final nextDiscovered = companion == null
        ? _discoveredSpeciesIds
        : {..._discoveredSpeciesIds, companion.speciesId};
    final nextProgress = {
      ..._stageProgress,
      if (result.won)
        stage.id: StageProgress(
          clearCount: (previous?.clearCount ?? 0) + 1,
          stars: result.stars > (previous?.stars ?? 0)
              ? result.stars
              : previous!.stars,
          bestTurns:
              previous?.bestTurns == null || result.turns < previous!.bestTurns!
              ? result.turns
              : previous.bestTurns,
          rewardDay: experience > 0 ? today : previous?.rewardDay,
          rewardedWinsToday: experience > 0
              ? rewardedToday + 1
              : previous?.rewardedWinsToday ?? 0,
        ),
    };
    final nextClears =
        result.won &&
            stageIndex < firstForestStages.length &&
            _adventureClears == stageIndex
        ? stageIndex + 1
        : _adventureClears;
    _mutationInFlight = true;
    try {
      await _persist(
        nextOwned,
        _squad,
        trainingEndsAt: _trainingEndsAt,
        trainingCompletions: _trainingCompletions,
        adventureClears: nextClears,
        stageProgress: nextProgress,
        trainingPasses: _trainingPasses - stage.entryTrainingPasses,
        discoveredSpeciesIds: nextDiscovered,
      );
      _owned
        ..clear()
        ..addAll(nextOwned);
      if (companion != null) _discoveredSpeciesIds.add(companion.speciesId);
      _trainingPasses -= stage.entryTrainingPasses;
      _adventureClears = nextClears;
      _stageProgress
        ..clear()
        ..addAll(nextProgress);
      notifyListeners();
      return BattleResult(
        result.frames,
        result.won,
        result.turns,
        result.stars,
        rewardSpeciesId: companion?.speciesId,
        leveledUpCreatureIds: leveledUpIds,
        evolvedCreatureIds: evolvedIds,
        experiencePerCreature: experience,
        firstBattleClear: result.won && (previous?.stars ?? 0) == 0,
      );
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<BattleResult?> runFirstBattle() =>
      runForestBattle(firstForestStages.first.id);

  String _battleDay(DateTime at) {
    final koreanDate = at.toUtc().add(const Duration(hours: 9));
    return '${koreanDate.year.toString().padLeft(4, '0')}-'
        '${koreanDate.month.toString().padLeft(2, '0')}-'
        '${koreanDate.day.toString().padLeft(2, '0')}';
  }

  /// Compatibility entry point for callers with only task IDs.
  Future<int> creditCompletedTasks(Iterable<String> taskIds) async {
    return creditRewards(
      taskIds.map(
        (id) => (
          sourceId: id,
          kind: 'task',
          trainingPasses: RewardRules.oneOffTrainingPasses,
          experience: 0,
          activityDay: _dayKey(DateTime.now()),
        ),
      ),
    );
  }

  /// Persist a receipt and its tickets together before updating memory.
  Future<int> creditRewards(Iterable<RewardCandidate> candidates) async {
    if (_loadFailed || _mutationInFlight) return 0;
    final known = {
      ..._creditedTaskIds,
      ..._rewardGrants.map((grant) => grant.sourceId),
    };
    final now = DateTime.now().toUtc();
    final today = _dayKey(DateTime.now());
    final earliestRewardDay = _dayKey(
      DateTime.now().subtract(const Duration(days: RewardRules.backfillDays)),
    );
    final fresh = <RewardGrant>[];
    final rewardedChecklistByDay = <String, int>{};
    for (final grant in _rewardGrants) {
      if ((grant.kind == 'task' || grant.kind == 'routine') &&
          grant.trainingPasses > 0 &&
          grant.activityDay != null) {
        rewardedChecklistByDay.update(
          grant.activityDay!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final candidate in candidates) {
      if (candidate.sourceId.isEmpty ||
          candidate.sourceId.length > 150 ||
          !validDailyKey(candidate.activityDay) ||
          candidate.activityDay.compareTo(today) > 0 ||
          !{
            'task',
            'routine',
            'mini',
            'more',
            'max',
          }.contains(candidate.kind) ||
          candidate.trainingPasses !=
              RewardRules.expectedForKind(candidate.kind).passes ||
          candidate.experience !=
              RewardRules.expectedForKind(candidate.kind).xp ||
          !known.add(candidate.sourceId)) {
        continue;
      }
      final checklist = candidate.kind == 'task' || candidate.kind == 'routine';
      final alreadyRewarded =
          rewardedChecklistByDay[candidate.activityDay] ?? 0;
      final capped =
          candidate.activityDay.compareTo(earliestRewardDay) < 0 ||
          (checklist &&
              alreadyRewarded >= RewardRules.dailyChecklistRewardLimit);
      if (checklist && !capped) {
        rewardedChecklistByDay[candidate.activityDay] = alreadyRewarded + 1;
      }
      fresh.add(
        RewardGrant(
          sourceId: candidate.sourceId,
          kind: candidate.kind,
          trainingPasses: capped ? 0 : candidate.trainingPasses,
          experience: candidate.experience,
          grantedAt: now,
          activityDay: candidate.activityDay,
          capped: capped,
        ),
      );
    }
    final passes = fresh.fold<int>(
      0,
      (sum, grant) => sum + grant.trainingPasses,
    );
    if (fresh.isEmpty ||
        _trainingPasses + passes > 100000 ||
        _rewardGrants.length + fresh.length > 100000) {
      return 0;
    }
    final nextIds = {
      ..._creditedTaskIds,
      ...fresh
          .where((grant) => grant.kind == 'task' || grant.kind == 'routine')
          .map((grant) => grant.sourceId),
    };
    final nextGrants = [..._rewardGrants, ...fresh];
    _mutationInFlight = true;
    try {
      await _persist(
        _owned,
        _squad,
        trainingEndsAt: _trainingEndsAt,
        trainingCompletions: _trainingCompletions,
        trainingPasses: _trainingPasses + passes,
        creditedTaskIds: nextIds,
        rewardGrants: nextGrants,
        discoveredSpeciesIds: _discoveredSpeciesIds,
      );
      _trainingPasses += passes;
      _creditedTaskIds
        ..clear()
        ..addAll(nextIds);
      _rewardGrants
        ..clear()
        ..addAll(nextGrants);
      notifyListeners();
      return passes;
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<void> _persist(
    List<CreatureInstance> owned,
    List<String?> squad, {
    required DateTime? trainingEndsAt,
    required int trainingCompletions,
    int? adventureClears,
    Map<String, StageProgress>? stageProgress,
    int? trainingPasses,
    Set<String>? creditedTaskIds,
    List<RewardGrant>? rewardGrants,
    required Set<String> discoveredSpeciesIds,
  }) => _prefs.setString(
    _storageKey,
    jsonEncode({
      'version': 1,
      'owned': owned.map((creature) => creature.toJson()).toList(),
      'squad': squad,
      'trainingEndsAt': trainingEndsAt?.toIso8601String(),
      'trainingCompletions': trainingCompletions,
      'adventureClears': adventureClears ?? _adventureClears,
      'stageProgress': (stageProgress ?? _stageProgress).map(
        (id, progress) => MapEntry(id, progress.toJson()),
      ),
      'trainingPasses': trainingPasses ?? _trainingPasses,
      'creditedTaskIds': (creditedTaskIds ?? _creditedTaskIds).toList(),
      'rewardGrants': (rewardGrants ?? _rewardGrants)
          .map((item) => item.toJson())
          .toList(),
      'discoveredSpeciesIds': discoveredSpeciesIds.toList(),
    }),
  );
}

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
