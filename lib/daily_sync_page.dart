import 'package:flutter/material.dart';

import 'models/daily_snapshot.dart';
import 'state/daily_sync_planner.dart';
import 'state/daily_sync_service.dart';

class DailySyncPage extends StatefulWidget {
  const DailySyncPage({
    super.key,
    required this.service,
    required this.accountEmail,
  });

  final DailySyncService service;
  final String? accountEmail;

  @override
  State<DailySyncPage> createState() => _DailySyncPageState();
}

class _DailySyncPageState extends State<DailySyncPage> {
  bool busy = false;
  String? error;
  DailySyncResult? result;
  List<DailySyncArchive> archives = [];

  @override
  void initState() {
    super.initState();
    _loadArchives();
  }

  Future<void> _loadArchives() async {
    final userId = widget.service.userId();
    if (userId == null) return;
    try {
      final loaded = await widget.service.checkpoints.archives(userId);
      if (mounted && widget.service.userId() == userId) {
        setState(() => archives = loaded);
      }
    } catch (_) {
      if (mounted) setState(() => error = '보관본을 읽지 못했어요.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await _loadArchives();
    } catch (caught) {
      if (mounted) {
        setState(
          () => error = caught is StateError
              ? caught.message.toString()
              : caught is FormatException
              ? '동기화 자료를 확인하지 못했어요. 기기 기록은 유지됩니다.'
              : '서버에 연결하지 못했어요. 기기 기록은 유지됩니다.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      )) ??
      false;

  Future<void> _sync() async {
    final owner = await widget.service.ownerBinding.ownerId;
    if (!mounted) return;
    final local = widget.service.store.dailySnapshot;
    if (owner == null && !local.isEmpty) {
      final accepted = await _confirm(
        '할 일·메모 계정 연결',
        '이 기기의 할 일 ${local.tasks.length}개와 메모 ${local.notes.length}개를 '
            '${widget.accountEmail ?? '현재 계정'}에 연결할까요? '
            '연결한 기기 기록은 다른 계정으로 바로 동기화할 수 없어요.',
        '연결하고 확인',
      );
      if (!accepted || !mounted) return;
    }
    await _run(() async {
      final synced = await widget.service.sync();
      if (mounted) setState(() => result = synced);
    });
  }

  Future<void> _resolve(DailySyncConflict conflict, bool keepLocal) async {
    final accepted = await _confirm(
      '서로 다른 기록 선택',
      keepLocal
          ? '이 기기의 할 일·메모를 서버에 저장합니다. 기존 서버 기록은 기기 보관본에 남습니다.'
          : '서버의 할 일·메모를 이 기기에 적용합니다. 기존 기기 기록은 보관본에 남습니다.',
      keepLocal ? '이 기기 선택' : '서버 선택',
    );
    if (!accepted || !mounted) return;
    await _run(() async {
      await widget.service.resolve(conflict, keepLocal: keepLocal);
      final synced = await widget.service.sync();
      if (mounted) setState(() => result = synced);
    });
  }

  Future<void> _restore(DailySyncArchive archive) async {
    final accepted = await _confirm(
      '보관본 복원',
      '보관본의 할 일·메모로 이 기기 기록을 바꿉니다. 현재 기기 기록도 새 보관본에 남습니다. '
          '복원 후 서버와 다시 동기화하려면 충돌을 확인하고 선택해야 합니다.',
      '이 기기에 복원',
    );
    if (!accepted || !mounted) return;
    await _run(() async {
      await widget.service.restoreArchive(archive);
      if (mounted) setState(() => result = null);
    });
  }

  Widget _summary(String label, DailySnapshot snapshot) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label · 할 일 ${snapshot.tasks.length}개 · 메모 ${snapshot.notes.length}개',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (snapshot.tasks.isNotEmpty)
        Text(
          '할 일: ${snapshot.tasks.take(3).map((item) => item.title).join(' · ')}',
        ),
      if (snapshot.notes.isNotEmpty)
        Text(
          '메모 날짜: ${snapshot.notes.take(3).map((item) => item.day).join(' · ')}',
        ),
    ],
  );

  Future<void> _showSnapshot(
    String title,
    DailySnapshot snapshot,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: ListView(
          children: [
            Text('할 일 ${snapshot.tasks.length}개'),
            for (final task in snapshot.tasks)
              ListTile(
                dense: true,
                title: Text(task.title),
                subtitle: Text(
                  '완료 ${task.completedDay ?? task.completedOccurrences.join(', ')}',
                ),
              ),
            const Divider(),
            Text('메모 ${snapshot.notes.length}개'),
            for (final note in snapshot.notes)
              ListTile(
                dense: true,
                title: Text(note.day),
                subtitle: Text(note.text),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('할 일·메모 동기화')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '동기화를 누를 때만 계정 기록과 비교합니다. 서로 다른 기록은 직접 선택하며, '
                  '선택하지 않은 내용은 이 기기의 보관본에 남습니다.',
                ),
                const SizedBox(height: 16),
                _summary('이 기기', widget.service.store.dailySnapshot),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _sync,
                  icon: const Icon(Icons.sync),
                  label: Text(busy ? '확인 중...' : '지금 동기화'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (result != null) ...[
                  const SizedBox(height: 16),
                  Text(switch (result!.action) {
                    DailySyncAction.upload => '이 기기 기록을 계정에 저장했어요.',
                    DailySyncAction.download => '계정 기록을 이 기기에 가져왔어요.',
                    DailySyncAction.unchanged => '기기와 계정 기록이 같아요.',
                    DailySyncAction.conflict =>
                      '기기와 계정 기록이 달라요. 유지할 내용을 선택해 주세요.',
                  }),
                  if (result!.conflict case final conflict?) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _summary('이 기기', conflict.local),
                            TextButton(
                              onPressed: () =>
                                  _showSnapshot('이 기기 기록', conflict.local),
                              child: const Text('이 기기 전체 보기'),
                            ),
                            const SizedBox(height: 12),
                            if (conflict.remote != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _summary('서버', conflict.remote!.snapshot),
                                  TextButton(
                                    onPressed: () => _showSnapshot(
                                      '서버 기록',
                                      conflict.remote!.snapshot,
                                    ),
                                    child: const Text('서버 전체 보기'),
                                  ),
                                ],
                              )
                            else
                              const Text('서버: 저장된 기록 없음'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _resolve(conflict, true),
                                  child: const Text('이 기기 기록 선택'),
                                ),
                                if (conflict.remote != null)
                                  OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => _resolve(conflict, false),
                                    child: const Text('서버 기록 선택'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 28),
                Text(
                  '동기화 보관본 · ${archives.length}개',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('충돌에서 선택하지 않은 기록과 복원 전 기록을 이 기기에 보관합니다.'),
                for (final archive in archives) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _summary(archive.source, archive.snapshot),
                          TextButton(
                            onPressed: () =>
                                _showSnapshot('보관본', archive.snapshot),
                            child: const Text('전체 보기'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            archive.savedAt.toLocal().toString().substring(
                              0,
                              16,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy ? null : () => _restore(archive),
                              child: const Text('이 기기에 복원'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
