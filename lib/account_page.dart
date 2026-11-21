import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_data_page.dart';
import 'account_settings_page.dart';
import 'backup_page.dart';
import 'daily_sync_page.dart';
import 'game_guide_page.dart';
import 'login_page.dart';
import 'state/auth_gateway.dart';
import 'state/game_store.dart';
import 'state/goal_sync_service.dart';
import 'state/daily_sync_service.dart';
import 'state/growth_store.dart';
import 'models/growth_goal.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.auth,
    required this.store,
    required this.gameStore,
    this.goalSyncService,
    this.dailySyncService,
    this.serverGameAvailable = false,
    this.accountDeletionEnabled = false,
  });

  final AuthGateway auth;
  final GrowthStore store;
  final GameStore gameStore;
  final GoalSyncService? goalSyncService;
  final DailySyncService? dailySyncService;
  final bool serverGameAvailable;
  final bool accountDeletionEnabled;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final emailInput = TextEditingController();
  final codeInput = TextEditingController();
  StreamSubscription<String?>? subscription;
  String? signedInEmail;
  String? signedInUserId;
  String? error;
  bool codeSent = false;
  bool busy = false;
  GoalSyncResult? syncResult;
  String? syncError;

  @override
  void initState() {
    super.initState();
    signedInEmail = widget.auth.currentUserEmail;
    signedInUserId = widget.auth.currentUserId;
    subscription = widget.auth.authChanges.listen((_) {
      final userId = widget.auth.currentUserId;
      if (mounted && signedInUserId != userId) {
        setState(() {
          signedInUserId = userId;
          signedInEmail = widget.auth.currentUserEmail;
          if (userId == null) {
            codeSent = false;
            codeInput.clear();
          }
          syncResult = null;
          syncError = null;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    emailInput.dispose();
    codeInput.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = emailInput.text.trim();
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      setState(() => error = '이메일 주소를 확인해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.sendEmailCode(email);
      if (mounted) setState(() => codeSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = _emailSendError(e));
    } catch (_) {
      if (mounted) setState(() => error = '인증 메일을 보내지 못했어요. 인터넷 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _emailSendError(AuthException exception) {
    switch (exception.code) {
      case 'over_email_send_rate_limit':
        return '인증 메일 요청이 너무 잦아요. 잠시 후 다시 시도해 주세요.';
      case 'email_address_not_authorized':
        return '이 주소로 메일을 보낼 수 없어요. 발송 서비스 설정을 확인해 주세요.';
      case 'unexpected_failure':
        return '인증 메일 서버 오류(${exception.statusCode ?? '알 수 없음'}). SMTP 발송 설정을 확인해 주세요.';
      default:
        return '인증 메일을 보내지 못했어요. 오류: ${exception.code ?? exception.statusCode ?? '알 수 없음'}';
    }
  }

  Future<void> _verifyCode() async {
    if (codeInput.text.trim().isEmpty) {
      setState(() => error = '메일로 받은 코드를 적어 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.verifyEmailCode(emailInput.text.trim(), codeInput.text);
      if (mounted) {
        setState(() {
          signedInEmail = widget.auth.currentUserEmail;
          signedInUserId = widget.auth.currentUserId;
          codeSent = false;
          codeInput.clear();
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '코드를 확인하지 못했어요. 다시 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.signOut();
      if (mounted) {
        setState(() {
          signedInEmail = null;
          signedInUserId = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '로그아웃하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirmPhrase({
    required String title,
    required String description,
    required String phrase,
    required String action,
  }) async {
    var entered = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setDialogState(() => entered = value),
                decoration: InputDecoration(labelText: '확인하려면 "$phrase" 입력'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: entered.trim() == phrase
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    return confirmed == true;
  }

  Future<void> _editDisplayName() async {
    var draft = widget.auth.currentDisplayName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('표시 이름 변경'),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            labelText: '표시 이름',
            helperText: '이 계정의 프로필에 저장됩니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.updateDisplayName(name);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = '표시 이름을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (signedInEmail == null) return;
    final confirmed = await _confirmPhrase(
      title: '회원탈퇴',
      description:
          '이메일 계정과 서버에 연결된 게임·동기화 기록을 영구 삭제합니다. '
          '이 기기의 목표·할 일·메모와 별도 백업 파일은 남습니다. 먼저 필요한 기록을 백업해 주세요.',
      phrase: '탈퇴',
      action: '계정 삭제',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final deletingUserId = widget.auth.currentUserId;
      await widget.auth.deleteAccount();
      try {
        await DailySyncCheckpointStore(SharedPreferencesAsync())
            .clearLocalData(deletingUserId);
        await GoalSyncCheckpointStore(SharedPreferencesAsync())
            .clearLocalData();
      } catch (_) {
        // The server account is already deleted; local records remain usable.
      }
      if (mounted) {
        setState(() {
          signedInEmail = null;
          signedInUserId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('계정이 삭제됐어요. 이 기기의 기록은 남아 있어요.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '계정을 삭제하지 못했어요. 계정은 유지됩니다. 다시 시도해 주세요.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('계정 삭제에 실패했어요. 계정은 유지됩니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clearLocalData() async {
    final confirmed = await _confirmPhrase(
      title: '이 기기 기록 삭제',
      description:
          '이 기기의 목표·할 일·메모·신수·훈련 기록과 앱 설정을 영구 삭제합니다. '
          '계정과 서버 기록, 이미 내보낸 백업 파일은 지워지지 않습니다.',
      phrase: '기록 삭제',
      action: '기기 기록 삭제',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gameStore.clearLocalData();
      await widget.store.clearLocalData();
      final ownerId = await GoalSyncCheckpointStore(SharedPreferencesAsync())
          .ownerId;
      await DailySyncCheckpointStore(SharedPreferencesAsync())
          .clearLocalData(ownerId);
      await GoalSyncCheckpointStore(SharedPreferencesAsync()).clearLocalData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이 기기의 기록과 설정을 삭제했어요.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '기기 기록을 삭제하지 못했어요. 다시 시도해 주세요.');
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('기기 기록 삭제에 실패했어요.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sync() async {
    final service = widget.goalSyncService;
    if (service == null) return;
    final owner = await service.checkpoints.ownerId;
    if (!mounted) return;
    final localCount = service.store.allGoals
        .where((goal) => !goal.localBackup)
        .length;
    if (owner == null && localCount > 0) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('이 계정에 기록 연결'),
          content: Text(
            '이 기기의 목표 $localCount개를 $signedInEmail 계정에 연결할까요? '
            '한번 연결하면 다른 계정으로 바로 동기화할 수 없어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('연결하고 동기화'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      busy = true;
      syncError = null;
    });
    try {
      final result = await service.sync();
      if (mounted) setState(() => syncResult = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => syncError = error is StateError
              ? error.message.toString()
              : '동기화하지 못했어요. 기록은 이 기기에 남아 있어요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resolve(GoalSyncConflict conflict, bool keepLocal) async {
    final service = widget.goalSyncService;
    if (service == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('충돌한 기록 선택'),
        content: Text(
          keepLocal
              ? '이 기기의 기록을 사용합니다. 서버의 이전 기록은 이 기기에 보관본으로 남겨요.'
              : '서버의 기록을 사용합니다. 이 기기의 이전 기록은 보관본으로 남겨요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('선택'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      syncError = null;
    });
    try {
      await service.resolve(conflict, keepLocal: keepLocal);
      final result = await service.sync();
      if (mounted) setState(() => syncResult = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => syncError = error is StateError
              ? error.message.toString()
              : '기록을 선택하지 못했어요. 다시 동기화해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _goalSummary(String source, GrowthGoal? goal) {
    if (goal == null) return Text('$source: 목표 없음');
    final days = goal.completions.keys.toList()..sort();
    final rests = goal.restDays.toList()..sort();
    final recentDays = days.reversed.take(10);
    final recentRests = rests.reversed.take(10);
    String practiceOn(String day) {
      final action = goal.completionActions[day];
      return '$day ${goal.completions[day]}'
          '${action == null ? '' : ' · $action'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$source: ${goal.title}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          '실천 ${days.length}일 · 쉼 ${rests.length}일 · '
          '${goal.archived ? '보관됨' : '진행 중'}',
        ),
        if (days.isNotEmpty)
          Text('최근 실천: ${recentDays.map(practiceOn).join(', ')}'),
        if (rests.isNotEmpty) Text('최근 쉼: ${recentRests.join(', ')}'),
        if (goal.milestones.isNotEmpty)
          Text('이정표: ${goal.milestones.join(', ')}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(signedInUserId == null ? '로그인' : '계정')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (signedInUserId == null) ...[
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LoginPage(
                          auth: widget.auth,
                          onComplete: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('이메일 비밀번호 · 구글 · 카카오 로그인'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '이메일로 로그인',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '이메일로 받은 인증번호를 입력하면 로그인할 수 있어요. 메일은 컴퓨터에서 확인해도 됩니다.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: emailInput,
                    enabled: !busy && !codeSent,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const SizedBox(height: 12),
                  if (codeSent) ...[
                    const Text(
                      '메일의 인증번호를 아래에 입력해 주세요. 번호 대신 확인 링크가 온다면 휴대폰에서 그 링크를 열 수 있어요.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeInput,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '인증 코드'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy ? null : _verifyCode,
                      child: const Text('코드 확인'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              codeSent = false;
                              codeInput.clear();
                            }),
                      child: const Text('이메일 다시 입력'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: busy ? null : _sendCode,
                      child: const Text('인증번호 받기'),
                    ),
                ] else ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 23,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: const Icon(Icons.person_outline),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.auth.currentDisplayName ??
                                          '전설키우기 사용자',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      signedInEmail ?? '이메일 없는 계정',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(child: Text('이메일 인증 완료')),
                            ],
                          ),
                          if (widget.auth.currentUserCreatedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '가입 ${widget.auth.currentUserCreatedAt!.toLocal().year}.${widget.auth.currentUserCreatedAt!.toLocal().month}.${widget.auth.currentUserCreatedAt!.toLocal().day}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: busy ? null : _editDisplayName,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('표시 이름 변경'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.goalSyncService != null) ...[
                    const SizedBox(height: 28),
                    Text(
                      '목표·기록 동기화',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '이 기기의 목표와 실천 기록을 계정에 연결합니다. 충돌한 목표는 확인 후 선택할 수 있어요.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : _sync,
                      icon: const Icon(Icons.sync),
                      label: Text(busy ? '처리 중...' : '지금 동기화'),
                    ),
                    if (syncResult != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '올림 ${syncResult!.uploaded}개 · 내려받음 ${syncResult!.downloaded}개 · 충돌 ${syncResult!.conflicts.length}개',
                      ),
                      for (final conflict in syncResult!.conflicts) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conflict.local?.title ??
                                      conflict.remote?.snapshot['title']
                                          ?.toString() ??
                                      '목표 충돌',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                _goalSummary('이 기기', conflict.local),
                                const SizedBox(height: 8),
                                _goalSummary(
                                  '서버',
                                  conflict.remote == null
                                      ? null
                                      : GrowthGoal.fromJson(
                                          conflict.remote!.snapshot,
                                        ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (conflict.local != null)
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
                    if (syncError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        syncError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                  if (widget.dailySyncService != null) ...[
                    const SizedBox(height: 28),
                    Text(
                      '할 일·메모 동기화',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '계정 기록과 비교하고 서로 다른 기록은 직접 선택할 수 있어요. 선택하지 않은 내용은 기기에 보관돼요.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DailySyncPage(
                                  service: widget.dailySyncService!,
                                  accountEmail: signedInEmail,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('할 일·메모 동기화 열기'),
                    ),
                  ],
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text('설정', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tune_outlined),
                        title: const Text('앱 설정'),
                        subtitle: const Text('화면 · 보상 안내 · 알림'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AccountSettingsPage(
                              store: widget.store,
                              gameStore: widget.gameStore,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('내 데이터'),
                        subtitle: const Text('저장 위치와 삭제 범위'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AccountDataPage(
                              goalSyncAvailable: widget.goalSyncService != null,
                              dailySyncAvailable:
                                  widget.dailySyncService != null,
                              serverGameAvailable: widget.serverGameAvailable,
                              accountDeletionEnabled:
                                  widget.accountDeletionEnabled,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: const Text('게임 이용 안내'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const GameGuidePage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('계정과 기기', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (signedInUserId != null) ...[
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('로그아웃'),
                          subtitle: const Text('기기 기록은 유지돼요.'),
                          onTap: busy ? null : _signOut,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.person_remove_outlined,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            '회원탈퇴',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          subtitle: Text(
                            widget.accountDeletionEnabled
                                ? '계정과 연결된 서버 기록 삭제'
                                : '서버 삭제 기능 준비 중',
                          ),
                          onTap:
                              busy ||
                                  !widget.accountDeletionEnabled ||
                                  signedInEmail == null
                              ? null
                              : _deleteAccount,
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: const Text('기기 기록 삭제'),
                        subtitle: const Text('계정과 백업 파일은 유지돼요.'),
                        onTap: busy ? null : _clearLocalData,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('백업', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.save_alt_outlined),
                    title: const Text('기록 백업·가져오기'),
                    subtitle: const Text('JSON 파일로 보관·복원'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BackupPage(
                          store: widget.store,
                          gameStore: widget.gameStore,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
