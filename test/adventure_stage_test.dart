import 'package:flutter_test/flutter_test.dart';
import 'package:growup/game_page.dart';
import 'package:growup/models/adventure_stage.dart';
import 'package:growup/models/game_snapshot.dart';

void main() {
  test('first forest stages have stable IDs and ordered unlocks', () {
    expect(
      firstForestStages.map((stage) => stage.id).toSet(),
      hasLength(firstForestStages.length),
    );
    expect(
      firstForestStages.map((stage) => stage.at),
      adventureTrainingThresholds,
    );
    expect(TrainingJournal.entries, firstForestStages);
    expect(
      firstForestStages.every((stage) => stage.regionId == 'first_forest'),
      isTrue,
    );
    expect(firstForestStages.last.boss, isTrue);
    expect(firstForestStages.first.prerequisiteStageId, isNull);
    for (var index = 1; index < firstForestStages.length; index++) {
      expect(
        firstForestStages[index].prerequisiteStageId,
        firstForestStages[index - 1].id,
      );
    }
    expect(firstForestStages.take(2).every((stage) => !stage.boss), isTrue);
    for (final stage in firstForestStages) {
      expect(stage.waves, hasLength(2));
      expect(stage.waves.every((wave) => wave.enemies.isNotEmpty), isTrue);
      expect(stage.entryTrainingPasses, 1);
      expect(stage.recommendedPower, greaterThan(0));
      expect(stage.firstClearReward.badge, isNotEmpty);
      expect(stage.firstClearReward.fragments, greaterThan(0));
      expect(stage.repeatReward.fragments, 0);
    }
  });

  test('stage records reject impossible stars and preserve best turns', () {
    const progress = StageProgress(clearCount: 2, stars: 3, bestTurns: 5);
    expect(StageProgress.fromJson(progress.toJson()).bestTurns, 5);
    expect(StageProgress.fromJson(progress.toJson()).stars, 3);
    expect(
      StageProgress.fromJson(
        const StageProgress(
          clearCount: 2,
          stars: 3,
          rewardDay: '2026-11-04',
          rewardedWinsToday: 5,
        ).toJson(),
      ).rewardedWinsToday,
      5,
    );
    expect(
      () => StageProgress.fromJson({
        'clearCount': 1,
        'stars': 1,
        'rewardDay': '2026-11-04',
        'rewardedWinsToday': 6,
      }),
      throwsFormatException,
    );
    expect(
      () =>
          StageProgress.fromJson({'clearCount': 0, 'stars': 3, 'bestTurns': 5}),
      throwsFormatException,
    );
    expect(
      () =>
          StageProgress.fromJson({'clearCount': 1, 'stars': 4, 'bestTurns': 0}),
      throwsFormatException,
    );
    expect(
      readStageProgress(null, 2).keys,
      containsAll(firstForestStages.take(2).map((stage) => stage.id)),
    );
    expect(
      () => readStageProgress({
        firstForestStages.last.id: const StageProgress(clearCount: 1).toJson(),
      }, 1),
      throwsFormatException,
    );
  });

  test('river records require each previous victory and survive loading', () {
    final records = {
      for (final stage in firstForestStages)
        stage.id: const StageProgress(clearCount: 1, stars: 2).toJson(),
      for (final stage in riverStages)
        stage.id: const StageProgress(
          clearCount: 1,
          stars: 3,
          bestTurns: 4,
        ).toJson(),
    };
    expect(readStageProgress(records, 3)[riverStages.last.id]?.bestTurns, 4);
    records.remove(riverStages[1].id);
    expect(() => readStageProgress(records, 3), throwsFormatException);
    records[riverStages[1].id] = const StageProgress(
      clearCount: 1,
      stars: 3,
      bestTurns: 4,
    ).toJson();
    records.remove(firstForestStages.last.id);
    expect(() => readStageProgress(records, 2), throwsFormatException);
  });
}
