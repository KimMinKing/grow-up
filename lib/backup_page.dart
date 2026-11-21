import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'state/growth_backup.dart';
import 'state/growth_store.dart';
import 'state/game_store.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store, this.gameStore});

  final GrowthStore store;
  final GameStore? gameStore;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const _backupChannel = MethodChannel('com.example.growup/backup');
  bool busy = false;
  String? message;
  bool error = false;

  Future<void> _export() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final contents = widget.store
          .createBackup()
          .withGame(widget.gameStore?.exportSnapshot())
          .encode();
      final bytes = Uint8List.fromList(utf8.encode(contents));
      if (bytes.length > GrowthBackup.maxBytes) {
        throw const FormatException('백업 파일이 너무 커요.');
      }
      final date = dayKey(DateTime.now()).replaceAll('-', '');
      final fileName = 'growup-backup-$date.json';
      String feedback;
      if (kIsWeb) {
        await XFile.fromData(
          bytes,
          name: fileName,
          mimeType: 'application/json',
        ).saveTo(fileName);
        feedback = '백업 파일 다운로드를 시작했어요. 브라우저의 다운로드 목록을 확인해 주세요.';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final saved = await _backupChannel.invokeMethod<bool>('saveBackup', {
          'fileName': fileName,
          'bytes': bytes,
        });
        feedback = saved == true ? '백업 파일을 저장했어요.' : '파일 저장을 취소했어요.';
      } else {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'application/json')],
            fileNameOverrides: [fileName],
          ),
        );
        feedback = result.status == ShareResultStatus.dismissed
            ? '파일 공유를 취소했어요.'
            : '공유 화면을 닫았어요. 저장 위치에서 백업 파일을 확인해 주세요.';
      }
      if (mounted) {
        setState(() {
          message = feedback;
          error = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          message = exception is FormatException
              ? exception.message
              : '백업 파일을 내보내지 못했어요.';
          error = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      const group = XTypeGroup(
        label: '전설키우기 백업',
        extensions: ['json'],
        mimeTypes: ['application/json'],
      );
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      if (await file.length() > GrowthBackup.maxBytes) {
        throw const FormatException('백업 파일이 너무 커요.');
      }
      final backup = GrowthBackup.decode(await file.readAsString());
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('백업 기록 가져오기'),
          content: Text(
            '백업 목표 ${backup.goals.length}개를 가져옵니다. '
            '할 일 ${backup.tasks.length}개 · 메모 ${backup.notes.length}개'
            '${backup.game == null ? '' : ' · 로컬 게임 포함'}\n\n'
            '현재 기록은 유지해요. 같은 목표는 건너뛰고, 다른 기록이나 5개를 넘는 진행 목표는 보관본으로 남겨요. '
            '이미 시작한 게임도 유지해요.\n\n'
            '계정 동기화 중이라면 새 목표는 다음 수동 동기화 때 전송될 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final result = await widget.store.importBackup(backup);
      final gameRestored =
          backup.game != null &&
          widget.gameStore != null &&
          await widget.gameStore!.importIfEmpty(backup.game!);
      if (mounted) {
        setState(() {
          message =
              '목표 ${result.added}개를 가져왔어요. '
              '할 일 ${result.tasksAdded}개 · 메모 ${result.notesAdded}개 · 보관본 ${result.archivedCopies}개 · 이미 같은 목표 ${result.skipped}개. '
              '${backup.game == null
                  ? '게임 자료 없음'
                  : gameRestored
                  ? '로컬 게임 복원'
                  : '기존 로컬 게임 유지'}';
          error = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          message = exception is FormatException
              ? exception.message
              : '백업 파일을 가져오지 못했어요. 기존 기록은 남아 있어요.';
          error = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('기록 백업')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '기록을 파일로 옮기기',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  '목표·실천·할 일·메모·로드맵, 신수 이름과 테마, 로컬 게임 진행을 JSON 파일로 보관하고 복원합니다.',
                ),
                const SizedBox(height: 20),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내보내기',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          kIsWeb
                              ? '현재 기록을 내려받습니다. 브라우저의 다운로드 위치를 확인해 주세요.'
                              : '현재 기록을 파일로 저장합니다. 저장 위치를 직접 선택해 주세요.',
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: busy ? null : _export,
                            icon: const Icon(Icons.save_alt),
                            label: const Text('백업 파일 내보내기'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '백업에서 복원',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '백업을 현재 기록에 추가합니다. 같은 목표는 건너뛰고, 이미 기록이 있으면 현재 설정을 유지해요.',
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _import,
                            icon: const Icon(Icons.file_open_outlined),
                            label: const Text('백업 파일 가져오기'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(Icons.hourglass_top_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('파일 처리 중…'),
                    ],
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        message!,
                        style: error
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  '백업 파일에는 목표와 메모의 내용이 들어 있어요. 보관 위치를 확인해 주세요.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
