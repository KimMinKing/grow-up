import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'state/game_reward_ledger.dart';

class GameRewardLedgerPage extends StatefulWidget {
  const GameRewardLedgerPage({
    super.key,
    required this.client,
    this.taskTitles = const {},
  });

  final SupabaseClient client;
  final Map<String, String> taskTitles;

  @override
  State<GameRewardLedgerPage> createState() => _GameRewardLedgerPageState();
}

class _GameRewardLedgerPageState extends State<GameRewardLedgerPage> {
  late Future<List<GameRewardLedgerEntry>> _entries = _load();
  late final String? _userId = widget.client.auth.currentUser?.id;
  StreamSubscription<AuthState>? _authSubscription;
  GameLedgerKind? _kind;
  String _query = '';
  bool _recentOnly = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<GameRewardLedgerEntry>> _load() =>
      loadGameRewardLedger(widget.client, taskTitles: widget.taskTitles);

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _entries = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the retry state.
    }
  }

  String _stamp(DateTime utc) {
    final kst = utc.toUtc().add(const Duration(hours: 9));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${kst.year}.${two(kst.month)}.${two(kst.day)} '
        '${two(kst.hour)}:${two(kst.minute)} KST';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF202330),
    appBar: AppBar(
      title: const Text('계정 보상 원장'),
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xFF202330),
      actions: [
        IconButton(
          tooltip: '원장 새로고침',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: widget.client.auth.currentUser?.id != _userId
        ? const Center(
            child: Text(
              '계정이 변경됐어요. 원장을 다시 열어 주세요.',
              style: TextStyle(color: Colors.white),
            ),
          )
        : FutureBuilder<List<GameRewardLedgerEntry>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '계정 기록을 불러오지 못했어요.',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final all = snapshot.data ?? const <GameRewardLedgerEntry>[];
              final entries = filterGameRewardLedger(
                all,
                kind: _kind,
                query: _query,
                since: _recentOnly
                    ? DateTime.now().toUtc().subtract(const Duration(days: 7))
                    : null,
              );
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '서버 기록을 시간순으로 보여줘요. 재시도는 같은 요청에 합쳐지고 초기 전투권 2개는 별도 기록이 없어요. 만료 반환은 잔액에서 확인하세요.',
                              style: TextStyle(color: Color(0xFFC2D5D1)),
                            ),
                            const SizedBox(height: 12),
                            Material(
                              color: const Color(0xFF303544),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    TextField(
                                      controller: _searchController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: '보상 내역 검색',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      onChanged: (value) =>
                                          setState(() => _query = value),
                                    ),
                                    DropdownButtonFormField<GameLedgerKind?>(
                                      initialValue: _kind,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF303544),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: '기록 종류',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: null,
                                          child: Text('모든 기록'),
                                        ),
                                        for (final (kind, label) in [
                                          (GameLedgerKind.taskGrant, '할 일 전투권'),
                                          (GameLedgerKind.battle, '정식 전투'),
                                          (GameLedgerKind.firstClear, '첫 승리'),
                                          (GameLedgerKind.expedition, '정식 파견'),
                                          (GameLedgerKind.draw, '무료 뽑기'),
                                        ])
                                          DropdownMenuItem(
                                            value: kind,
                                            child: Text(label),
                                          ),
                                      ],
                                      onChanged: (value) =>
                                          setState(() => _kind = value),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        '최근 7일만 보기',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      value: _recentOnly,
                                      onChanged: (value) =>
                                          setState(() => _recentOnly = value),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${entries.length}건${entries.isEmpty ? ' · 조건에 맞는 기록이 없어요.' : ''}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      );
                    }
                    final entry = entries[index - 1];
                    final change = [
                      if (entry.battlePassChange case final amount?)
                        '전투권 ${amount > 0 ? '+' : ''}$amount',
                      if (entry.shardChange case final amount?)
                        '조각 ${amount > 0 ? '+' : ''}$amount',
                    ].join(' · ');
                    return Card(
                      color: const Color(0xFF303544),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _stamp(entry.at),
                              style: const TextStyle(color: Color(0xFFAAD7F3)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.detail,
                              style: const TextStyle(color: Color(0xFFC2D5D1)),
                            ),
                            if (change.isNotEmpty)
                              Text(
                                change,
                                style: const TextStyle(
                                  color: Color(0xFFFFD991),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
  );
}
