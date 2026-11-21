import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/focus_session.dart';
import 'theme/app_palette.dart';

/// Returns true only when the user explicitly asks to record their practice.
class FocusPage extends StatefulWidget {
  const FocusPage({
    super.key,
    required this.goalId,
    required this.title,
    required this.action,
  });
  final String goalId;
  final String title;
  final String action;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> with WidgetsBindingObserver {
  FocusSession session = FocusSession();
  final repository = FocusSessionRepository(SharedPreferencesAsync());
  bool loading = true;
  bool saving = false;
  String? saveError;
  Timer? ticker;
  bool leaving = false;
  bool askingToLeave = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
    ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && session.running) {
        if (session.remainingAt(DateTime.now()) == Duration.zero) {
          session.pause(DateTime.now());
        }
        setState(() {});
      }
    });
  }

  Future<void> _restore() async {
    try {
      final restored = await repository.read(widget.goalId);
      if (!mounted) return;
      if (restored != null) session = restored;
    } catch (_) {
      saveError = '이전 집중 시간을 읽지 못했어요. 새로 시작할 수 있어요.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _change(VoidCallback update) async {
    if (saving) return;
    setState(() {
      update();
      saving = true;
      saveError = null;
    });
    try {
      if (session.started) {
        await repository.write(widget.goalId, session);
      } else {
        await repository.clearForGoal(widget.goalId);
      }
    } catch (_) {
      saveError = '집중 상태를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _leave() async {
    if (askingToLeave || loading || saving) return;
    askingToLeave = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('집중을 마칠까요?'),
        content: Text(
          saveError == null
              ? '집중 시간은 저장돼요. 같은 목표에서 집중하기를 다시 열면 이어갈 수 있어요.'
              : '집중 상태를 저장하지 못했어요. 나가면 마지막으로 저장한 상태까지만 이어갈 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('이어 하기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    askingToLeave = false;
    if (exit == true && mounted) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, false);
      });
    }
  }

  Future<void> _record() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await repository.clearForGoal(widget.goalId);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = '집중 상태를 정리하지 못했어요. 다시 시도해 주세요.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = session.remainingAt(DateTime.now());
    final finished = session.started && remaining == Duration.zero;
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final display =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: leaving || (!loading && !saving && !session.started),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('작게 시작하는 집중')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('오늘의 MINI · ${widget.action}'),
                  const SizedBox(height: 28),
                  Center(
                    child: Semantics(
                      label: '남은 시간',
                      value: '$display 남음',
                      child: ExcludeSemantics(
                        child: FittedBox(
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).pine,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value:
                        1 -
                        remaining.inMilliseconds /
                            session.duration.inMilliseconds,
                  ),
                  const SizedBox(height: 24),
                  if (!session.started)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final minutes in [2, 5, 10, 25])
                          ChoiceChip(
                            label: Text('$minutes분'),
                            selected: session.duration.inMinutes == minutes,
                            onSelected: saving
                                ? null
                                : (_) => setState(
                                    () => session.selectMinutes(minutes),
                                  ),
                          ),
                      ],
                    ),
                  if (finished) ...[
                    Text(
                      '작은 시간을 함께 걸었어요.',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('실제로 한 만큼 MINI·MORE·MAX를 골라 기록해 주세요.'),
                  ] else
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () => _change(
                              () => session.running
                                  ? session.pause(DateTime.now())
                                  : session.start(DateTime.now()),
                            ),
                      icon: Icon(
                        session.running ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(
                        session.running
                            ? '잠깐 멈추기'
                            : session.started
                            ? '이어 하기'
                            : '집중 시작',
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: saving ? null : _record,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(finished ? '실천 기록하기' : '여기까지 하고 실천 기록하기'),
                  ),
                  if (session.started)
                    TextButton(
                      onPressed: saving ? null : () => _change(session.reset),
                      child: const Text('타이머 다시 정하기'),
                    ),
                  const SizedBox(height: 16),
                  if (saveError != null)
                    Text(
                      saveError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Text('시간을 다 채우지 않아도 괜찮아요. 타이머는 실천을 자동 완료하지 않아요.'),
                  const SizedBox(height: 8),
                  const Text('최근 집중 한 건을 저장해요. 앱을 다시 켠 뒤 같은 목표에서 이어갈 수 있어요.'),
                ],
              ),
      ),
    );
  }
}
