import 'package:flutter/material.dart';

import 'app_date_picker.dart';

import 'package:flutter/foundation.dart';

import 'models/daily_content.dart';
import 'models/task_template.dart';
import 'state/growth_store.dart';
import 'state/task_reminders.dart';

Future<String?> _editText(
  BuildContext context, {
  required String title,
  String initial = '',
  required int maxLength,
  int maxLines = 1,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextEntryDialog(
    title: title,
    initial: initial,
    maxLength: maxLength,
    maxLines: maxLines,
  ),
);

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.maxLines,
  });

  final String title;
  final String initial;
  final int maxLength;
  final int maxLines;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
    controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final value = controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      textInputAction: widget.maxLines == 1
          ? TextInputAction.done
          : TextInputAction.newline,
      onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
      decoration: InputDecoration(
        hintText: widget.maxLines == 1 ? '할 일을 적어 주세요' : '오늘의 생각을 적어 주세요',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: controller.text.trim().isEmpty ? null : _submit,
        child: const Text('저장'),
      ),
    ],
  );
}

Future<bool> _confirmDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name 삭제'),
        content: Text('이 $name을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
    false;

typedef _TaskDraft = ({
  String title,
  String? scheduledDay,
  String? scheduledTime,
  String repeatPattern,
  List<int> repeatWeekdays,
  int repeatIntervalDays,
  String priority,
  List<String> tags,
  String? goalId,
  bool reminderEnabled,
});

Future<_TaskDraft?> _editTask(
  BuildContext context,
  GrowthStore store, {
  ChecklistItem? task,
}) => showDialog<_TaskDraft>(
  context: context,
  builder: (_) => _TaskEntryDialog(store: store, task: task),
);

Future<bool> editChecklistTask(
  BuildContext context,
  GrowthStore store,
  ChecklistItem task,
) async {
  if (task.roadmapLinked) {
    final title = await _editText(
      context,
      title: '로드맵에서 가져온 행동 수정',
      initial: task.title,
      maxLength: 160,
    );
    if (title == null) return false;
    return store.updateTask(
      task,
      title,
      scheduledDay: task.scheduledDay,
      scheduledTime: task.scheduledTime,
    );
  }
  final entry = await _editTask(context, store, task: task);
  if (entry == null) return false;
  return store.updateTask(
    task,
    entry.title,
    scheduledDay: entry.scheduledDay,
    scheduledTime: entry.scheduledTime,
    repeatPattern: entry.repeatPattern,
    repeatWeekdays: entry.repeatWeekdays,
    repeatIntervalDays: entry.repeatIntervalDays,
    priority: entry.priority,
    tags: entry.tags,
    goalId: entry.goalId,
    reminderEnabled: entry.reminderEnabled,
  );
}

class _TaskEntryDialog extends StatefulWidget {
  const _TaskEntryDialog({required this.store, this.task});
  final GrowthStore store;
  final ChecklistItem? task;

  @override
  State<_TaskEntryDialog> createState() => _TaskEntryDialogState();
}

class _TaskEntryDialogState extends State<_TaskEntryDialog> {
  late final TextEditingController controller;
  late final TextEditingController tagController;
  String? scheduledDay;
  String? scheduledTime;
  String repeatPattern = 'none';
  final Set<int> repeatWeekdays = {};
  int repeatIntervalDays = 2;
  String priority = 'normal';
  String? goalId;
  bool showCategories = false;
  bool reminderEnabled = false;

  Future<void> _chooseTemplate() async {
    FocusScope.of(context).unfocus();
    final template = await showModalBottomSheet<TaskTemplate>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const ListTile(
            title: Text('작은 루틴 예시'),
            subtitle: Text('고른 뒤 제목과 반복 일정을 바꿀 수 있어요.'),
          ),
          for (final template in taskTemplates)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(template.title),
              subtitle: Text(template.description),
              onTap: () => Navigator.pop(context, template),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    setState(() {
      controller.text = template.title;
      repeatPattern = template.repeatPattern;
      repeatWeekdays
        ..clear()
        ..addAll(template.weekdays);
      scheduledDay = widget.store.today;
      tagController.text = template.tag;
      showCategories = true;
    });
  }

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.task?.title ?? '');
    controller.addListener(_refresh);
    tagController = TextEditingController(
      text: widget.task?.tags.join(', ') ?? '',
    );
    tagController.addListener(_refresh);
    scheduledDay = widget.task?.scheduledDay;
    scheduledTime = widget.task?.scheduledTime;
    repeatPattern = widget.task?.repeatPattern ?? 'none';
    repeatWeekdays.addAll(widget.task?.repeatWeekdays ?? const []);
    repeatIntervalDays = widget.task?.repeatIntervalDays ?? 2;
    priority = widget.task?.priority ?? 'normal';
    goalId = widget.task?.goalId;
    reminderEnabled = widget.task?.reminderEnabled ?? false;
    showCategories =
        widget.task != null &&
        (priority != 'normal' ||
            tagController.text.isNotEmpty ||
            goalId != null);
  }

  Future<void> _chooseDay() async {
    final picked = await showAppDatePicker(
      context: context,
      title: '할 일 예정 날짜',
      initialDate: scheduledDay == null
          ? DateTime.now()
          : DateTime.parse(scheduledDay!),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => scheduledDay = dayKey(picked));
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    tagController.removeListener(_refresh);
    tagController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final parts = scheduledTime?.split(':');
    final initial = parts == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final compact =
        MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(12) > 18;
    final selected = compact
        ? await _showCompactTimePicker(initial)
        : await showTimePicker(
            context: context,
            initialEntryMode: TimePickerEntryMode.input,
            initialTime: initial,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          );
    if (selected != null && mounted) {
      setState(
        () => scheduledTime =
            '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<TimeOfDay?> _showCompactTimePicker(TimeOfDay initial) {
    var hour = initial.hour;
    var minute = initial.minute;
    return showDialog<TimeOfDay>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('시간 설정'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('시'),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: hour,
                      items: [
                        for (var value = 0; value < 24; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => hour = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('분'),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: minute,
                      items: [
                        for (var value = 0; value < 60; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => minute = value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
              child: const Text('설정'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final title = controller.text.trim();
    if (title.isNotEmpty && _tagsValid) {
      Navigator.pop(context, (
        title: title,
        scheduledDay: scheduledDay,
        scheduledTime: scheduledTime,
        repeatPattern: repeatPattern,
        repeatWeekdays: repeatWeekdays.toList()..sort(),
        repeatIntervalDays: repeatIntervalDays,
        priority: priority,
        tags: _parsedTags,
        goalId: goalId,
        reminderEnabled:
            reminderEnabled &&
            scheduledTime != null &&
            (scheduledDay != null || repeatPattern != 'none'),
      ));
    }
  }

  List<String> get _parsedTags => tagController.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();

  bool get _tagsValid {
    final tags = _parsedTags;
    return tags.length <= 3 &&
        tags.every((tag) => tag.length <= 24) &&
        tags.map((tag) => tag.toLowerCase()).toSet().length == tags.length;
  }

  String get _repeatPreview {
    final draft = ChecklistItem(
      id: 'preview',
      title: 'preview',
      createdDay: widget.store.today,
      scheduledDay: scheduledDay,
      repeatPattern: repeatPattern,
      repeatWeekdays: repeatWeekdays.toList(),
      repeatIntervalDays: repeatIntervalDays,
    );
    final today = DateTime.parse(widget.store.today);
    var cursor = dayKey(DateTime.utc(today.year, today.month, today.day - 1));
    final dates = <String>[];
    for (var i = 0; i < 3; i++) {
      final next = draft.nextOccurrenceAfter(cursor);
      if (next == null) break;
      final date = DateTime.parse(next);
      dates.add('${date.month}/${date.day}');
      cursor = next;
    }
    return '다음 기본 일정 · ${dates.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    title: Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.checklist_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.task == null ? '할 일 추가' : '할 일 수정',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '작게 적고 하나씩 해봐요',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: '무엇을 할까요?',
              hintText: '예: 책 10분 읽기',
            ),
          ),
          if (widget.task == null)
            TextButton.icon(
              onPressed: _chooseTemplate,
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('작은 루틴 예시에서 시작'),
            ),
          const SizedBox(height: 4),
          Text('일정', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _chooseDay,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          scheduledDay == null ? '날짜 설정' : scheduledDay!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (scheduledDay != null)
                      IconButton(
                        tooltip: '날짜 지우기',
                        onPressed: () => setState(() => scheduledDay = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const Divider(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _chooseTime,
                        icon: const Icon(Icons.schedule_outlined),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            scheduledTime == null ? '시간 설정' : scheduledTime!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (scheduledTime != null)
                      IconButton(
                        tooltip: '시간 지우기',
                        onPressed: () => setState(() {
                          scheduledTime = null;
                          reminderEnabled = false;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: const ValueKey('task-repeat-pattern'),
            initialValue: repeatPattern,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '반복'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('반복 안 함')),
              DropdownMenuItem(value: 'daily', child: Text('매일')),
              DropdownMenuItem(value: 'weekly', child: Text('선택 요일·매주')),
              DropdownMenuItem(value: 'interval', child: Text('며칠 간격')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                repeatPattern = value;
                if (value == 'weekly' && repeatWeekdays.isEmpty) {
                  repeatWeekdays.add(DateTime.now().weekday);
                }
              });
            },
          ),
          if (repeatPattern == 'weekly') ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(
                      const ['월', '화', '수', '목', '금', '토', '일'][day - 1],
                    ),
                    selected: repeatWeekdays.contains(day),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        repeatWeekdays.add(day);
                      } else if (repeatWeekdays.length > 1) {
                        repeatWeekdays.remove(day);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (repeatPattern == 'interval') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('반복 간격'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: repeatIntervalDays,
                  items: [
                    for (var value = 2; value <= 30; value++)
                      DropdownMenuItem(value: value, child: Text('$value일')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => repeatIntervalDays = value);
                    }
                  },
                ),
              ],
            ),
          ],
          if (widget.task == null && repeatPattern != 'none')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _repeatPreview,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '할 일 알림',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Semantics(
                      label: '할 일 알림',
                      child: Switch.adaptive(
                        value: reminderEnabled,
                        onChanged:
                            kIsWeb ||
                                defaultTargetPlatform !=
                                    TargetPlatform.android ||
                                scheduledTime == null ||
                                (scheduledDay == null &&
                                    repeatPattern == 'none')
                            ? null
                            : (value) async {
                                if (value) {
                                  final granted = await taskReminderService
                                      .requestPermission();
                                  if (!granted && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '알림 권한을 허용하면 예정 시각에 알려드려요.',
                                        ),
                                      ),
                                    );
                                  }
                                  if (!granted) return;
                                }
                                if (mounted) {
                                  setState(() => reminderEnabled = value);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                Text(
                  kIsWeb || defaultTargetPlatform != TargetPlatform.android
                      ? 'Android 앱에서 설정할 수 있어요.'
                      : scheduledTime == null ||
                            (scheduledDay == null && repeatPattern == 'none')
                      ? '날짜와 시간, 또는 반복과 시간을 정하면 켤 수 있어요.'
                      : '선택한 시각 근처에 알려줘요.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => showCategories = !showCategories),
            icon: Icon(showCategories ? Icons.expand_less : Icons.expand_more),
            label: const Text('중요도·태그·목표'),
          ),
          if (showCategories) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const ValueKey('task-priority'),
              initialValue: priority,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '중요도'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('낮음')),
                DropdownMenuItem(value: 'normal', child: Text('보통')),
                DropdownMenuItem(value: 'high', child: Text('높음')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => priority = value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tagController,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: '태그',
                hintText: '예: 공부, 집안일',
                helperText: '쉼표로 구분, 최대 3개',
                errorText: _tagsValid ? null : '태그는 3개까지, 각각 24자 이내로 적어 주세요.',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const ValueKey('task-goal'),
              initialValue: goalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '연결할 목표'),
              items: [
                const DropdownMenuItem(value: null, child: Text('연결 안 함')),
                for (final goal in widget.store.allGoals)
                  DropdownMenuItem(
                    value: goal.id,
                    child: Text(goal.title, overflow: TextOverflow.ellipsis),
                  ),
                if (goalId != null &&
                    !widget.store.allGoals.any((goal) => goal.id == goalId))
                  DropdownMenuItem(
                    value: goalId,
                    child: const Text('찾을 수 없는 목표'),
                  ),
              ],
              onChanged: (value) => setState(() => goalId = value),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: controller.text.trim().isEmpty || !_tagsValid
            ? null
            : _submit,
        child: const Text('저장'),
      ),
    ],
  );
}

class TodayChecklist extends StatelessWidget {
  const TodayChecklist({
    super.key,
    required this.store,
    this.onAwardTraining,
    this.onOpenGame,
  });

  final GrowthStore store;
  final Future<int> Function(String sourceId)? onAwardTraining;
  final VoidCallback? onOpenGame;

  @override
  Widget build(BuildContext context) {
    final overdue = store.overdueTasks;
    final dueToday = store.dueTodayTasks;
    final undated = store.undatedTasks;
    final upcoming = store.upcomingTasks;
    final archived = store.archivedTasks;
    final recurringLater = store.recurringLaterTasks;
    final doneToday = store.tasks
        .where(
          (task) =>
              !task.archived &&
              (task.repeats
                  ? task.wasCompletedOn(store.today)
                  : task.completedDay == store.today),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('따로 적는 할 일', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('목표 퀘스트와 별개예요. 끝내지 않은 일은 다음 날에도 보여요.'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final entry = await _editTask(context, store);
            if (entry != null) {
              await store.addTask(
                entry.title,
                scheduledDay: entry.scheduledDay,
                scheduledTime: entry.scheduledTime,
                repeatPattern: entry.repeatPattern,
                repeatWeekdays: entry.repeatWeekdays,
                repeatIntervalDays: entry.repeatIntervalDays,
                priority: entry.priority,
                tags: entry.tags,
                goalId: entry.goalId,
                reminderEnabled: entry.reminderEnabled,
              );
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('할 일 추가'),
        ),
        const SizedBox(height: 8),
        WeekTaskPanel(store: store),
        TaskFinder(store: store),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          TaskQuietHoursPanel(store: store),
        if (overdue.isEmpty &&
            dueToday.isEmpty &&
            undated.isEmpty &&
            upcoming.isEmpty &&
            recurringLater.isEmpty &&
            archived.isEmpty &&
            doneToday.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('아직 적은 할 일이 없어요.'),
            ),
          ),
        if (overdue.isNotEmpty) ...[
          _groupTitle(context, '지난 일 · ${overdue.length}개'),
          ...overdue.map((task) => _taskTile(context, task)),
        ],
        if (dueToday.isNotEmpty) ...[
          _groupTitle(context, '오늘 예정 · ${dueToday.length}개'),
          ...dueToday.map((task) => _taskTile(context, task)),
        ],
        if (undated.isNotEmpty) ...[
          _groupTitle(context, '날짜 미정 · ${undated.length}개'),
          ...undated.map((task) => _taskTile(context, task)),
        ],
        if (upcoming.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('upcoming-tasks'),
            title: Text('예정 · ${upcoming.length}개'),
            children: upcoming.map((task) => _taskTile(context, task)).toList(),
          ),
        if (recurringLater.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('recurring-later-tasks'),
            title: Text('다음 반복 · ${recurringLater.length}개'),
            children: recurringLater
                .map((task) => _taskTile(context, task))
                .toList(),
          ),
        if (archived.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('archived-tasks'),
            title: Text('보관한 일 · ${archived.length}개'),
            children: archived.map((task) => _taskTile(context, task)).toList(),
          ),
        if (doneToday.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('today-completed-tasks'),
            title: Text('오늘 완료 ${doneToday.length}개'),
            children: doneToday
                .map((task) => _taskTile(context, task))
                .toList(),
          ),
      ],
    );
  }

  Widget _groupTitle(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _taskTile(BuildContext context, ChecklistItem task) {
    final occurrenceDay = task.occursOn(store.today)
        ? store.today
        : task.nextOccurrenceAfter(store.today);
    final exceptionDays = <String>{
      ...task.skippedOccurrences,
      ...task.movedOccurrences.keys,
    }.where((day) => day.compareTo(store.today) >= 0).toList()..sort();
    final done = task.repeats
        ? task.wasCompletedOn(store.today)
        : task.completedDay != null;
    final completedSteps = task.steps
        .where(
          (step) => step.isCompletedOn(store.today, repeated: task.repeats),
        )
        .length;
    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            horizontalTitleGap: 8,
            minLeadingWidth: 40,
            leading: Checkbox(
              value: done,
              onChanged:
                  task.archived ||
                      task.roadmapLinked ||
                      (task.repeats && !task.occursOn(store.today))
                  ? null
                  : (_) async {
                      await store.toggleTask(task);
                      if (!done && onAwardTraining != null) {
                        final sourceId = task.repeats
                            ? '${task.id}:${store.today}'
                            : task.id;
                        final passes = await onAwardTraining!(sourceId);
                        if (passes > 0 &&
                            context.mounted &&
                            store.showGameRewards) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('할 일 완료 · 훈련 +$passes'),
                              persist: false,
                              action: onOpenGame == null
                                  ? null
                                  : SnackBarAction(
                                      label: '게임으로',
                                      onPressed: onOpenGame!,
                                    ),
                            ),
                          );
                        }
                      }
                      if (done && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '완료 기록을 취소했어요. 이미 받은 훈련권은 유지되고, 다시 완료해도 중복 지급되지 않아요.',
                            ),
                          ),
                        );
                      }
                    },
            ),
            title: Text(
              task.title,
              style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle:
                task.archived ||
                    task.scheduledDay != null ||
                    task.scheduledTime != null ||
                    (task.createdDay != store.today && !done) ||
                    task.steps.isNotEmpty ||
                    task.repeats ||
                    task.priority != 'normal' ||
                    task.tags.isNotEmpty ||
                    task.goalId != null ||
                    task.reminderEnabled
                ? Text(
                    [
                      if (task.archived) '보관됨',
                      if (task.scheduledDay != null) '예정 ${task.scheduledDay}',
                      if (task.scheduledTime != null) task.scheduledTime!,
                      if (task.reminderEnabled) '알림',
                      if (task.roadmapLinked) '목표 실천과 연결 · 훈련권 별도 없음',
                      if (task.repeats) _repeatLabel(task),
                      if (task.priority == 'high') '중요',
                      if (task.priority == 'low') '여유',
                      for (final tag in task.tags) '#$tag',
                      if (task.goalId != null)
                        '목표 ${store.goalById(task.goalId!)?.title ?? '찾을 수 없음'}',
                      if (task.wasSkippedOn(store.today)) '오늘 회차 쉬는 날',
                      if (task.movedOccurrences.containsKey(store.today))
                        '오늘 회차 → ${task.movedOccurrences[store.today]}',
                      if (task.repeats && !task.occursOn(store.today))
                        '다음 ${task.nextOccurrenceAfter(store.today) ?? '미정'}',
                      if (task.steps.isNotEmpty)
                        '단계 $completedSteps/${task.steps.length}',
                      if (task.scheduledDay == null &&
                          task.createdDay != store.today &&
                          !done)
                        '전날부터 남은 일',
                    ].join(' · '),
                  )
                : null,
            trailing: PopupMenuButton<String>(
              tooltip: '할 일 메뉴',
              onSelected: (value) async {
                if (value == 'edit') {
                  await editChecklistTask(context, store, task);
                } else if (value == 'copy') {
                  try {
                    final copied = await store.copyTask(task);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            copied
                                ? '새 할 일로 복사했어요. 완료 기록과 알림은 복사하지 않아요.'
                                : '할 일을 복사할 수 없어요. 저장된 할 일 수를 확인해 주세요.',
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('복사한 할 일을 저장하지 못했어요. 다시 시도해 주세요.'),
                        ),
                      );
                    }
                  }
                } else if (value == 'today') {
                  await store.updateTask(
                    task,
                    task.title,
                    scheduledDay: store.today,
                    scheduledTime: task.scheduledTime,
                  );
                } else if (value == 'step') {
                  final title = await _editText(
                    context,
                    title: '작은 단계 추가',
                    maxLength: 120,
                  );
                  if (title != null) await store.addTaskStep(task, title);
                } else if (value == 'first_step') {
                  final suggestion = '2분만 ${task.title} 시작하기';
                  final title = await _editText(
                    context,
                    title: '2분 첫 행동 정하기',
                    initial: suggestion.length > 120
                        ? suggestion.substring(0, 120)
                        : suggestion,
                    maxLength: 120,
                  );
                  if (title != null) await store.addTaskStep(task, title);
                } else if (value == 'enough_today') {
                  final bool changed;
                  if (task.repeats) {
                    changed = await store.skipTaskOccurrence(task, store.today);
                  } else {
                    changed = await store.deferTaskUntilTomorrow(task);
                  }
                  if (changed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('오늘은 여기까지. 내일 다시 볼 수 있어요.')),
                    );
                  }
                } else if (value == 'skip_occurrence' &&
                    occurrenceDay != null) {
                  await store.skipTaskOccurrence(task, occurrenceDay);
                } else if (value == 'move_occurrence' &&
                    occurrenceDay != null) {
                  final now = DateTime.now();
                  final date = await showAppDatePicker(
                    context: context,
                    title: '옮길 날짜',
                    initialDate: DateTime.parse(occurrenceDay)
                        .add(const Duration(days: 1)),
                    firstDate: now,
                    lastDate: DateTime(2100),
                  );
                  if (date != null && context.mounted) {
                    final target = dayKey(date);
                    final alreadyScheduled = task.occursOn(target);
                    final moved = await store.moveTaskOccurrence(
                      task,
                      occurrenceDay,
                      target,
                    );
                    if (moved && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            alreadyScheduled
                                ? '$target에 원래 일정이 있어 한 번만 체크해요.'
                                : '$occurrenceDay 회차를 $target로 옮겼어요.',
                          ),
                        ),
                      );
                    }
                  }
                } else if (value.startsWith('restore_occurrence:')) {
                  await store.restoreTaskOccurrence(
                    task,
                    value.substring('restore_occurrence:'.length),
                  );
                } else if (value == 'archive') {
                  await store.setTaskArchived(task, true);
                } else if (value == 'restore') {
                  await store.setTaskArchived(task, false);
                } else if (value == 'delete' &&
                    await _confirmDelete(context, '할 일')) {
                  await store.deleteTask(task);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(task.roadmapLinked ? '행동 문구 수정' : '수정·날짜 변경'),
                ),
                if (!task.roadmapLinked)
                  const PopupMenuItem(value: 'copy', child: Text('새 할 일로 복사')),
                if (!done &&
                    !task.archived &&
                    !task.repeats &&
                    task.scheduledDay != store.today)
                  const PopupMenuItem(value: 'today', child: Text('오늘로 옮기기')),
                if (!done && !task.archived && !task.roadmapLinked)
                  const PopupMenuItem(value: 'step', child: Text('작게 나누기')),
                if (!done &&
                    !task.archived &&
                    !task.roadmapLinked &&
                    task.steps.length < 20)
                  const PopupMenuItem(
                    value: 'first_step',
                    child: Text('2분 첫 행동 만들기'),
                  ),
                if (!done &&
                    !task.archived &&
                    (task.repeats
                        ? task.occursOn(store.today)
                        : task.scheduledDay == null ||
                              task.scheduledDay!.compareTo(store.today) <= 0))
                  const PopupMenuItem(
                    value: 'enough_today',
                    child: Text('오늘은 여기까지'),
                  ),
                if (task.repeats &&
                    !task.archived &&
                    occurrenceDay != null &&
                    !task.wasCompletedOn(occurrenceDay)) ...[
                  PopupMenuItem(
                    value: 'skip_occurrence',
                    child: Text('$occurrenceDay 회차 쉬기'),
                  ),
                  PopupMenuItem(
                    value: 'move_occurrence',
                    child: Text('$occurrenceDay 회차 미루기'),
                  ),
                ],
                if (task.repeats && exceptionDays.isNotEmpty)
                  PopupMenuItem(
                    value: 'restore_occurrence:${exceptionDays.first}',
                    child: Text('${exceptionDays.first} 예외 되돌리기'),
                  ),
                if (!done && !task.archived)
                  const PopupMenuItem(value: 'archive', child: Text('보관')),
                if (task.archived)
                  const PopupMenuItem(value: 'restore', child: Text('다시 꺼내기')),
                const PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
          ),
          if (task.roadmapLinked &&
              !done &&
              !task.archived &&
              task.scheduledDay == store.today &&
              store.goalById(task.goalId!)?.archived == false)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final beforeXp = store.experience;
                  await store.complete(store.goalById(task.goalId!)!, 'MINI');
                  if (onAwardTraining == null) return;
                  final passes = await onAwardTraining!(
                    'goal:${task.goalId}:${store.today}',
                  );
                  if (passes < 0) return;
                  final xp = store.experience - beforeXp;
                  if (context.mounted &&
                      store.showGameRewards &&
                      (passes > 0 || xp != 0)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('목표 실천 · XP +$xp · 훈련 +$passes'),
                        persist: false,
                        action: onOpenGame == null
                            ? null
                            : SnackBarAction(
                                label: '게임으로',
                                onPressed: onOpenGame!,
                              ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('목표 MINI로 실천 기록'),
              ),
            ),
          if (task.steps.isNotEmpty)
            ExpansionTile(
              title: Text('작은 단계 · $completedSteps/${task.steps.length}'),
              children: [
                for (final step in task.steps)
                  ListTile(
                    leading: Checkbox(
                      value: step.isCompletedOn(
                        store.today,
                        repeated: task.repeats,
                      ),
                      onChanged:
                          task.archived ||
                              (task.repeats && !task.occursOn(store.today))
                          ? null
                          : (_) => store.toggleTaskStep(task, step),
                    ),
                    title: Text(step.title),
                    trailing: IconButton(
                      tooltip: '단계 삭제',
                      icon: const Icon(Icons.close),
                      onPressed: () => store.deleteTaskStep(task, step),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _repeatLabel(ChecklistItem task) => switch (task.repeatPattern) {
    'daily' => '매일 반복',
    'weekly' =>
      '매주 ${task.repeatWeekdays.map((day) => const ['월', '화', '수', '목', '금', '토', '일'][day - 1]).join('·')}',
    'interval' => '${task.repeatIntervalDays}일 간격',
    _ => '',
  };
}

class TaskQuietHoursPanel extends StatelessWidget {
  const TaskQuietHoursPanel({super.key, required this.store});
  final GrowthStore store;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('알림과 조용한 시간'),
    shape: const Border(),
    collapsedShape: const Border(),
    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      SwitchListTile.adaptive(
        title: const Text('조용한 시간 사용'),
        subtitle: Text('${store.quietStart}~${store.quietEnd}에는 알림을 뒤로 미뤄요.'),
        value: store.quietEnabled,
        onChanged: (value) => store.setQuietHours(
          enabled: value,
          start: store.quietStart,
          end: store.quietEnd,
        ),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final result = await showDialog<({String start, String end})>(
            context: context,
            builder: (_) =>
                _QuietHoursDialog(start: store.quietStart, end: store.quietEnd),
          );
          if (result != null) {
            await store.setQuietHours(
              enabled: store.quietEnabled,
              start: result.start,
              end: result.end,
            );
          }
        },
        icon: const Icon(Icons.bedtime_outlined),
        label: const Text('조용한 시간 변경'),
      ),
      const Text('알림은 Android 앱에서만 예약하며 실제 도착 시각은 기기 설정에 따라 달라질 수 있어요.'),
    ],
  );
}

class _QuietHoursDialog extends StatefulWidget {
  const _QuietHoursDialog({required this.start, required this.end});
  final String start;
  final String end;

  @override
  State<_QuietHoursDialog> createState() => _QuietHoursDialogState();
}

class _QuietHoursDialogState extends State<_QuietHoursDialog> {
  late final TextEditingController start;
  late final TextEditingController end;

  @override
  void initState() {
    super.initState();
    start = TextEditingController(text: widget.start)..addListener(_refresh);
    end = TextEditingController(text: widget.end)..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    start.removeListener(_refresh);
    end.removeListener(_refresh);
    start.dispose();
    end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        validTaskTime(start.text) &&
        validTaskTime(end.text) &&
        start.text != end.text;
    return AlertDialog(
      title: const Text('조용한 시간'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: start,
            maxLength: 5,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: '시작',
              hintText: '22:00',
              counterText: '',
            ),
          ),
          TextField(
            controller: end,
            maxLength: 5,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: '끝',
              hintText: '08:00',
              counterText: '',
            ),
          ),
          if (!valid) const Text('시각은 24시간제로 다르게 적어 주세요.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, (start: start.text, end: end.text))
              : null,
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class TaskFinder extends StatefulWidget {
  const TaskFinder({super.key, required this.store});
  final GrowthStore store;

  @override
  State<TaskFinder> createState() => _TaskFinderState();
}

class _TaskFinderState extends State<TaskFinder> {
  String query = '';
  String status = 'all';
  String goalId = 'all';
  String tag = 'all';
  String sort = 'date';

  bool _matchesStatus(ChecklistItem task) => switch (status) {
    'open' =>
      !task.archived &&
          (task.repeats
              ? !task.wasCompletedOn(widget.store.today)
              : task.completedDay == null),
    'done' =>
      task.repeats
          ? task.wasCompletedOn(widget.store.today)
          : task.completedDay != null,
    'archived' => task.archived,
    _ => true,
  };

  String _plannedDay(ChecklistItem task) => task.repeats
      ? task.occursOn(widget.store.today)
            ? widget.store.today
            : task.nextOccurrenceAfter(widget.store.today) ?? '9999-12-31'
      : task.scheduledDay ?? '9999-12-31';

  @override
  Widget build(BuildContext context) {
    final all = widget.store.tasks;
    final allTags = all.expand((task) => task.tags).toSet().toList()..sort();
    final text = query.trim().toLowerCase();
    final matches = all.where((task) {
      if (!_matchesStatus(task) ||
          (goalId != 'all' && task.goalId != goalId) ||
          (tag != 'all' && !task.tags.contains(tag))) {
        return false;
      }
      if (text.isEmpty) return true;
      final goalTitle = task.goalId == null
          ? ''
          : widget.store.goalById(task.goalId!)?.title ?? '';
      return task.title.toLowerCase().contains(text) ||
          goalTitle.toLowerCase().contains(text) ||
          task.tags.any((value) => value.toLowerCase().contains(text));
    }).toList();
    final order = {for (var i = 0; i < all.length; i++) all[i].id: i};
    matches.sort((a, b) {
      if (sort == 'priority') {
        const ranks = {'high': 0, 'normal': 1, 'low': 2};
        final byPriority = ranks[a.priority]!.compareTo(ranks[b.priority]!);
        if (byPriority != 0) return byPriority;
      } else if (sort == 'date') {
        final byDay = _plannedDay(a).compareTo(_plannedDay(b));
        if (byDay != 0) return byDay;
        final byTime = (a.scheduledTime ?? '99:99').compareTo(
          b.scheduledTime ?? '99:99',
        );
        if (byTime != 0) return byTime;
      }
      return order[a.id]!.compareTo(order[b.id]!);
    });
    return ExpansionTile(
      title: const Text('할 일 찾기'),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: '제목·태그·목표 검색',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-filter-status'),
          initialValue: status,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '상태'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('전체')),
            DropdownMenuItem(value: 'open', child: Text('진행 중')),
            DropdownMenuItem(value: 'done', child: Text('완료')),
            DropdownMenuItem(value: 'archived', child: Text('보관')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => status = value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-filter-goal'),
          initialValue: goalId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '목표'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('모든 목표')),
            for (final goal in widget.store.allGoals)
              DropdownMenuItem(
                value: goal.id,
                child: Text(goal.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => goalId = value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-filter-tag'),
          initialValue: tag,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '태그'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('모든 태그')),
            for (final item in allTags)
              DropdownMenuItem(value: item, child: Text(item)),
            if (tag != 'all' && !allTags.contains(tag))
              DropdownMenuItem(value: tag, child: Text('$tag (현재 없음)')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => tag = value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('task-filter-sort'),
          initialValue: sort,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '정렬'),
          items: const [
            DropdownMenuItem(value: 'date', child: Text('예정 날짜·시각')),
            DropdownMenuItem(value: 'priority', child: Text('중요도')),
            DropdownMenuItem(value: 'manual', child: Text('입력 순서')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => sort = value);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('${matches.length}개 찾았어요.'),
        ),
        if (matches.isEmpty) const Text('조건에 맞는 할 일이 없어요.'),
        for (final task in matches.take(100))
          ListTile(
            title: Text(task.title),
            subtitle: Text(
              [
                if (task.archived) '보관',
                if (task.repeats)
                  task.wasCompletedOn(widget.store.today)
                      ? '오늘 완료'
                      : '다음 ${_plannedDay(task) == '9999-12-31' ? '미정' : _plannedDay(task)}'
                else if (task.completedDay != null)
                  '${task.completedDay} 완료'
                else if (task.scheduledDay != null)
                  '${task.scheduledDay} 예정',
                if (task.priority == 'high') '중요',
                if (task.priority == 'low') '여유',
                for (final value in task.tags) '#$value',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: '찾은 할 일 수정',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editChecklistTask(context, widget.store, task),
            ),
          ),
        if (matches.length > 100)
          const Text('처음 100개를 보여줘요. 검색어와 필터로 더 좁혀 주세요.'),
      ],
    );
  }
}

class WeekTaskPanel extends StatelessWidget {
  const WeekTaskPanel({super.key, required this.store});

  final GrowthStore store;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final entries = store.weekTaskEntries(now);
    const weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
    return ExpansionTile(
      key: const PageStorageKey('week-tasks'),
      title: Text('이번 주 계획 · ${entries.length}회차'),
      subtitle: const Text('완료·예정·쉼·미룸을 날짜별로 확인해요.'),
      children: [
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('이번 주에 날짜를 정한 할 일이 없어요.'),
          ),
        for (var index = 0; index < 7; index++) ...[
          if (entries.any(
            (entry) => entry.day == dayKey(start.add(Duration(days: index))),
          )) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                child: Text(
                  '${start.add(Duration(days: index)).month}/${start.add(Duration(days: index)).day} (${weekdayNames[index]})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            for (final entry in entries.where(
              (entry) => entry.day == dayKey(start.add(Duration(days: index))),
            ))
              ListTile(
                dense: true,
                leading: Icon(switch (entry.status) {
                  'done' => Icons.check_circle_outline,
                  'skipped' => Icons.pause_circle_outline,
                  'moved' => Icons.redo,
                  _ => Icons.radio_button_unchecked,
                }),
                title: Text(entry.task.title),
                subtitle: Text(
                  [
                    switch (entry.status) {
                      'done' =>
                        entry.task.repeats ||
                                entry.task.completedDay == entry.day
                            ? '완료'
                            : '${entry.task.completedDay} 완료',
                      'skipped' => '쉼',
                      'moved' =>
                        '${entry.task.movedOccurrences[entry.day]}로 미룸',
                      _ =>
                        entry.day.compareTo(store.today) < 0 ? '지난 예정' : '예정',
                    },
                    if (entry.task.scheduledTime != null)
                      entry.task.scheduledTime!,
                    if (entry.task.repeats) '반복',
                  ].join(' · '),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class GoalLinkedTasks extends StatelessWidget {
  const GoalLinkedTasks({super.key, required this.store, required this.goalId});

  final GrowthStore store;
  final String goalId;

  @override
  Widget build(BuildContext context) {
    final tasks = store.tasks.where((task) => task.goalId == goalId).toList();
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '연결된 할 일 · ${tasks.length}개',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final task in tasks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              (task.repeats
                      ? task.wasCompletedOn(store.today)
                      : task.completedDay != null)
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
            ),
            title: Text(task.title),
            subtitle: Text(
              [
                if (task.archived) '보관됨',
                if (task.repeats)
                  task.wasCompletedOn(store.today)
                      ? '오늘 완료'
                      : task.occursOn(store.today)
                      ? '오늘 반복'
                      : '다음 ${task.nextOccurrenceAfter(store.today) ?? '미정'}'
                else if (task.completedDay != null)
                  '${task.completedDay} 완료'
                else if (task.scheduledDay != null)
                  '${task.scheduledDay} 예정',
                if (task.priority == 'high') '중요',
                if (task.priority == 'low') '여유',
                for (final tag in task.tags) '#$tag',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: '연결된 할 일 수정',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editChecklistTask(context, store, task),
            ),
          ),
      ],
    );
  }
}

class DailyNotesPanel extends StatelessWidget {
  const DailyNotesPanel({super.key, required this.store});

  final GrowthStore store;

  Future<void> _writeNote(BuildContext context, DateTime date) async {
    final text = await _editText(
      context,
      title: '${date.month}월 ${date.day}일 메모',
      maxLength: 1000,
      maxLines: 4,
    );
    if (text != null && text.isNotEmpty) {
      await store.addNote(dayKey(date), text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = [...store.notes]..sort((a, b) => b.day.compareTo(a.day));
    final completed = <({ChecklistItem task, String day})>[
      for (final task in store.tasks) ...[
        if (!task.roadmapLinked) ...[
          if (task.completedDay != null) (task: task, day: task.completedDay!),
          for (final day in task.completedOccurrences) (task: task, day: day),
        ],
      ],
    ]..sort((a, b) => b.day.compareTo(a.day));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('날짜별 메모', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _writeNote(context, DateTime.now()),
              icon: const Icon(Icons.edit_note),
              label: const Text('오늘 메모 쓰기'),
            ),
            TextButton(
              onPressed: () async {
                final now = DateTime.now();
                final date = await showAppDatePicker(
                  context: context,
                  title: '메모 날짜',
                  initialDate: now,
                  firstDate: DateTime(2000),
                  lastDate: now,
                );
                if (date != null && context.mounted) {
                  await _writeNote(context, date);
                }
              },
              child: const Text('다른 날짜'),
            ),
          ],
        ),
        if (notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('아직 메모가 없어요.'),
          ),
        ...notes.map(
          (note) => Card(
            child: ListTile(
              title: Text(note.text),
              subtitle: Text(note.day),
              trailing: PopupMenuButton<String>(
                tooltip: '메모 메뉴',
                onSelected: (value) async {
                  if (value == 'edit') {
                    final text = await _editText(
                      context,
                      title: '메모 수정',
                      initial: note.text,
                      maxLength: 1000,
                      maxLines: 4,
                    );
                    if (text != null && text.isNotEmpty) {
                      await store.updateNote(note, note.day, text);
                    }
                  } else if (value == 'delete' &&
                      await _confirmDelete(context, '메모')) {
                    await store.deleteNote(note);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('완료한 할 일', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (completed.isEmpty) const Text('완료한 할 일이 아직 없어요.'),
        ...completed.map(
          (event) => ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(event.task.title),
            subtitle: Text(
              '${event.day} 완료'
              '${event.task.scheduledDay == null ? '' : ' · 예정 ${event.task.scheduledDay}'}'
              '${event.task.scheduledTime == null ? '' : ' · 예정 ${event.task.scheduledTime}'}'
              '${event.task.goalId == null ? '' : ' · 목표 ${store.goalById(event.task.goalId!)?.title ?? '찾을 수 없음'}'}'
              '${event.task.tags.isEmpty ? '' : ' · ${event.task.tags.map((tag) => '#$tag').join(' ')}'}',
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '완료한 할 일 메뉴',
              onSelected: (value) async {
                if (value == 'edit') {
                  final entry = await _editTask(
                    context,
                    store,
                    task: event.task,
                  );
                  if (entry != null) {
                    await store.updateTask(
                      event.task,
                      entry.title,
                      scheduledDay: entry.scheduledDay,
                      scheduledTime: entry.scheduledTime,
                      repeatPattern: entry.repeatPattern,
                      repeatWeekdays: entry.repeatWeekdays,
                      repeatIntervalDays: entry.repeatIntervalDays,
                      priority: entry.priority,
                      tags: entry.tags,
                      goalId: entry.goalId,
                      reminderEnabled: entry.reminderEnabled,
                    );
                  }
                } else if (value == 'undo') {
                  await store.toggleTask(event.task);
                } else if (value == 'delete' &&
                    await _confirmDelete(context, '할 일')) {
                  await store.deleteTask(event.task);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('수정')),
                if (event.task.completedDay == event.day ||
                    (event.task.repeats && event.day == store.today))
                  const PopupMenuItem(value: 'undo', child: Text('완료 취소')),
                const PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
            dense: true,
          ),
        ),
      ],
    );
  }
}
