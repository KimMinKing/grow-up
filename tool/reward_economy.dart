import 'dart:io';

import 'package:growup/models/reward_grant.dart';

/// Run with `dart run tool/reward_economy.dart`.
/// Server expeditions, draws, and battle passes are independent of local tickets.
void main() {
  const cases = [
    _Scenario('적게', 3, 1, 1, 'MINI', 1, 1, 1),
    _Scenario('보통', 5, 2, 1, 'MORE', 1, 1, 1),
    _Scenario('많이', 7, 8, 3, 'MAX', 3, 3, 3),
    _Scenario('오래 쉬었다 재시작', 1, 1, 1, 'MINI', 1, 1, 1),
    _Scenario('반복 루틴 중심', 7, 8, 0, 'MINI', 1, 1, 1),
  ];
  stdout.writeln(
    '| 유형 | 활동일 | 훈련권 획득 | 훈련 사용 | 전투 사용 | 남은 훈련권 | 파견 귀환 | 무료 뽑기 가능 |',
  );
  stdout.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  final accountRows = <String>[];
  for (final scenario in cases) {
    var earned = 0;
    var trainingSpent = 0;
    var battleSpent = 0;
    var returns = 0;
    var expeditions = 0;
    var accountPasses = 2;
    var accountEarned = 0;
    var accountSpent = 0;
    var unclaimedCompletions = 0;
    var capDays = 0;
    for (var day = 0; day < 14; day++) {
      if (day % 7 >= scenario.activeDaysPerWeek) continue;
      final checklist = scenario.checklistPerDay.clamp(
        0,
        RewardRules.dailyChecklistRewardLimit,
      );
      final dailyTickets =
          checklist * RewardRules.oneOffTrainingPasses +
          scenario.goalPracticesPerDay *
              RewardRules.goalTrainingPasses(scenario.goalLevel);
      earned += dailyTickets;
      final used = scenario.trainingPerDay.clamp(
        0,
        earned - trainingSpent - battleSpent,
      );
      trainingSpent += used;
      returns += used;
      if (returns > 0 && earned > trainingSpent + battleSpent) {
        battleSpent++;
      }
      expeditions += scenario.expeditionsPerDay.clamp(0, 3);
      // A synced independent task occurrence can be claimed once for two
      // server passes. Claims happen before battles; the wallet caps at 30.
      unclaimedCompletions += scenario.checklistPerDay;
      while (unclaimedCompletions > 0 && accountPasses <= 28) {
        accountPasses += 2;
        accountEarned += 2;
        unclaimedCompletions--;
      }
      if (unclaimedCompletions > 0) capDays++;
      final accountUsed = scenario.serverBattlesPerDay.clamp(0, accountPasses);
      accountPasses -= accountUsed;
      accountSpent += accountUsed;
    }
    stdout.writeln(
      '| ${scenario.name} | ${scenario.activeDaysPerWeek * 2} | $earned | '
      '$trainingSpent | $battleSpent | ${earned - trainingSpent - battleSpent} | '
      '$expeditions | ${expeditions ~/ 3} |',
    );
    accountRows.add(
      '| ${scenario.name} | ${scenario.activeDaysPerWeek * 2} | '
      '${scenario.serverBattlesPerDay} | $accountEarned | $accountSpent | '
      '$accountPasses | $unclaimedCompletions | $capDays |',
    );
  }
  stdout.writeln();
  stdout.writeln(
    '| 유형 | 활동일 | 활동일당 정식 전투 | 전투권 청구 | 전투권 사용 | 잔액 | 미청구 완료 | 30장 상한일 |',
  );
  stdout.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in accountRows) {
    stdout.writeln(row);
  }
}

class _Scenario {
  const _Scenario(
    this.name,
    this.activeDaysPerWeek,
    this.checklistPerDay,
    this.goalPracticesPerDay,
    this.goalLevel,
    this.trainingPerDay,
    this.expeditionsPerDay,
    this.serverBattlesPerDay,
  );

  final String name;
  final int activeDaysPerWeek;
  final int checklistPerDay;
  final int goalPracticesPerDay;
  final String goalLevel;
  final int trainingPerDay;
  final int expeditionsPerDay;
  final int serverBattlesPerDay;
}
