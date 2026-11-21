import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/adventure_stage.dart';

enum GameLedgerKind { taskGrant, battle, firstClear, expedition, draw, other }

class GameRewardLedgerEntry {
  const GameRewardLedgerEntry({
    required this.at,
    required this.title,
    required this.detail,
    this.battlePassChange,
    this.shardChange,
    this.kind = GameLedgerKind.other,
  });

  final DateTime at;
  final String title;
  final String detail;
  final int? battlePassChange;
  final int? shardChange;
  final GameLedgerKind kind;
}

List<GameRewardLedgerEntry> filterGameRewardLedger(
  List<GameRewardLedgerEntry> entries, {
  GameLedgerKind? kind,
  String query = '',
  DateTime? since,
}) {
  final search = query.trim().toLowerCase();
  return entries
      .where(
        (entry) =>
            (kind == null || entry.kind == kind) &&
            (since == null || !entry.at.isBefore(since)) &&
            (search.isEmpty ||
                '${entry.title} ${entry.detail}'.toLowerCase().contains(
                  search,
                )),
      )
      .toList();
}

String _stagePlace(String? id) =>
    firstForestStages.where((stage) => stage.id == id).firstOrNull?.place ??
    '숲길';

DateTime _date(Object? value) => DateTime.parse(value as String).toUtc();

String _requestSuffix(Object? value) {
  final id = value as String?;
  return id == null || id.isEmpty
      ? ''
      : ' · 요청 ${id.length <= 8 ? id : id.substring(0, 8)}';
}

List<GameRewardLedgerEntry> mergeGameRewardLedger({
  required List<Map<String, dynamic>> taskGrants,
  required List<Map<String, dynamic>> battles,
  required List<Map<String, dynamic>> firstClears,
  required List<Map<String, dynamic>> expeditions,
  required List<Map<String, dynamic>> draws,
  Map<String, String> taskTitles = const {},
}) {
  final entries = <GameRewardLedgerEntry>[
    for (final row in taskGrants)
      GameRewardLedgerEntry(
        at: _date(row['granted_at']),
        title: '할 일 전투권 지급',
        kind: GameLedgerKind.taskGrant,
        detail:
            '${taskTitles[row['task_id']] ?? '할 일 ${row['task_id']}'} · ${row['completed_day']} 완료',
        battlePassChange: (row['passes'] as num).toInt(),
      ),
    for (final row in battles)
      GameRewardLedgerEntry(
        at: _date(row['started_at']),
        title: '${_stagePlace(row['stage_id'] as String?)} 정식 전투',
        kind: GameLedgerKind.battle,
        detail:
            '${switch (row['status']) {
              'pending' => '진행 중 · 전투권 사용',
              'expired' => '만료 · 전투권 반환은 서버 잔액에서 확인',
              _ => '${row['won'] == true ? '승리' : '패배'} · 별 ${row['stars'] ?? 0}/3 · 전투권 사용',
            }}${_requestSuffix(row['request_id'])}',
        battlePassChange: row['status'] == 'expired' ? null : -1,
      ),
    for (final row in firstClears)
      GameRewardLedgerEntry(
        at: _date(row['awarded_at']),
        title: '${_stagePlace(row['stage_id'] as String?)} 첫 승리',
        kind: GameLedgerKind.firstClear,
        detail: '첫 승리 보상 · 같은 장소는 한 번만 지급',
        shardChange: (row['awarded_shards'] as num).toInt(),
      ),
    for (final row in expeditions)
      GameRewardLedgerEntry(
        at: _date(row['claimed_at'] ?? row['started_at']),
        title: '정식 파견 ${row['claimed_at'] == null ? '진행 중' : '귀환 수령'}',
        kind: GameLedgerKind.expedition,
        detail: row['claimed_at'] == null ? '아직 조각을 수령하지 않았어요.' : '귀환 보상 수령 완료',
        shardChange: row['claimed_at'] == null
            ? null
            : (row['reward_shards'] as num).toInt(),
      ),
    for (final row in draws)
      GameRewardLedgerEntry(
        at: _date(row['created_at']),
        title: '무료 신수 뽑기',
        kind: GameLedgerKind.draw,
        detail:
            '${row['guaranteed'] == true ? '확정 뽑기 · 조각 사용' : '조각 사용'}${_requestSuffix(row['request_id'])}',
        shardChange: -(row['shards_spent'] as num).toInt(),
      ),
  ];
  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries;
}

/// Each table is protected by its own account RLS policy. Fetch every page so
/// older payouts remain visible instead of silently truncating the ledger.
Future<List<GameRewardLedgerEntry>> loadGameRewardLedger(
  SupabaseClient client, {
  Map<String, String> taskTitles = const {},
}) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw StateError('로그인이 필요해요.');

  Future<List<Map<String, dynamic>>> rows(
    String table,
    String columns,
    String timestamp,
  ) async {
    const pageSize = 500;
    final all = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      if (client.auth.currentUser?.id != userId) {
        throw StateError('계정이 변경되어 기록을 다시 읽어야 해요.');
      }
      final page = await client
          .from(table)
          .select(columns)
          .order(timestamp, ascending: false)
          .range(offset, offset + pageSize - 1);
      all.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < pageSize) return all;
    }
  }

  final results = await Future.wait([
    rows(
      'game_task_battle_grants',
      'task_id,completed_day,passes,granted_at',
      'granted_at',
    ),
    rows(
      'game_battle_attempts',
      'request_id,stage_id,status,won,stars,started_at',
      'started_at',
    ),
    rows(
      'game_stage_first_clears',
      'stage_id,awarded_shards,awarded_at',
      'awarded_at',
    ),
    rows(
      'game_expeditions',
      'started_at,claimed_at,reward_shards',
      'started_at',
    ),
    rows(
      'game_draw_requests',
      'request_id,guaranteed,shards_spent,created_at',
      'created_at',
    ),
  ]);
  if (client.auth.currentUser?.id != userId) {
    throw StateError('계정이 변경되어 기록을 다시 읽어야 해요.');
  }
  return mergeGameRewardLedger(
    taskGrants: results[0],
    battles: results[1],
    firstClears: results[2],
    expeditions: results[3],
    draws: results[4],
    taskTitles: taskTitles,
  );
}
