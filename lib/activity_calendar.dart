import 'package:flutter/material.dart';

import 'daily_content_widgets.dart';
import 'app_date_picker.dart';
import 'models/daily_content.dart';
import 'models/growth_goal.dart';
import 'state/growth_store.dart';
import 'theme/app_palette.dart';

const _miniColor = Color(0xFF176E9A);
const _moreColor = Color(0xFF1F705C);
const _maxColor = Color(0xFFA76513);

String _levelName(String? value) => switch (value) {
  'MINI' || '쉬움' => 'MINI',
  'MORE' || '보통' => 'MORE',
  'MAX' || '도전' => 'MAX',
  _ => '쉼',
};

Color _levelColor(String level) => switch (level) {
  'MINI' => _miniColor,
  'MORE' => _moreColor,
  'MAX' => _maxColor,
  _ => const Color(0xFF8495A4),
};

class ActivityCalendar extends StatefulWidget {
  const ActivityCalendar({super.key, required this.store});

  final GrowthStore store;

  @override
  State<ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<ActivityCalendar> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? selected;

  Future<void> _editPractice(DateTime date) async {
    final day = dayKey(date);
    final eligible = widget.store.allGoals
        .where((goal) => goal.startDay.compareTo(day) <= 0)
        .toList();
    if (eligible.isEmpty || day.compareTo(widget.store.today) > 0) return;
    final goal = await showModalBottomSheet<GrowthGoal>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('수정할 목표 선택')),
            for (final item in eligible)
              ListTile(
                title: Text(item.title),
                subtitle: Text(
                  item.completions[day] == null
                      ? '실천 기록 없음'
                      : '${_levelName(item.completions[day])} 기록됨',
                ),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (goal == null || !mounted) return;
    final current = goal.completions[day];
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('${date.month}월 ${date.day}일 · ${goal.title}'),
            ),
            for (final (level, action) in [
              ('MINI', goal.mini),
              ('MORE', goal.more),
              ('MAX', goal.max),
            ])
              ListTile(
                title: Text(level),
                subtitle: Text(action),
                trailing: _levelName(current) == level
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap: () => Navigator.pop(sheetContext, level),
              ),
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, 'DELETE'),
                child: const Text('이날 실천 기록 취소'),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('XP는 기록에 맞춰 다시 계산돼요. 같은 목표·날짜의 훈련권은 중복 지급되지 않아요.'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final saved = await widget.store.setPracticeOn(
      goal,
      day,
      choice == 'DELETE' ? null : choice,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '실천 기록을 수정했어요.' : '이 날짜의 기록을 수정할 수 없어요.'),
        persist: false,
      ),
    );
  }

  Widget _levelDot(String level, String day) => Container(
    key: ValueKey('calendar-level-$day-$level'),
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: _levelColor(level),
      shape: BoxShape.circle,
    ),
  );

  Widget _goalRecordLine(String title, String? value, String? action) {
    final level = _levelName(value);
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _levelColor(level).withValues(alpha: .15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              level,
              style: TextStyle(
                color: _levelColor(level),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title${action == null || action.isEmpty ? '' : ' · $action'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.ink),
            ),
          ),
        ],
      ),
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      month = DateTime(month.year, month.month + offset);
      selected = null;
    });
  }

  Widget _plannedTaskCard(
    BuildContext context,
    ChecklistItem task,
    String day,
  ) {
    final today = widget.store.today;
    final completed = task.wasCompletedOn(day);
    final canToggle =
        !task.archived &&
        !task.roadmapLinked &&
        (task.repeats ? day == today && task.occursOn(day) : true);
    final canMove =
        !task.archived &&
        !completed &&
        (task.repeats ? day.compareTo(today) >= 0 : task.completedDay == null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              [
                if (task.scheduledTime != null) task.scheduledTime!,
                if (task.repeats) '반복',
                if (completed) '이날 완료',
                if (task.roadmapLinked) '목표 실천 기록과 함께 완료',
                if (!task.repeats && task.completedDay != null && !completed)
                  '${task.completedDay} 완료',
              ].join(' · '),
            ),
            Wrap(
              spacing: 6,
              children: [
                TextButton(
                  onPressed: () async {
                    await editChecklistTask(context, widget.store, task);
                    if (mounted) setState(() {});
                  },
                  child: const Text('수정'),
                ),
                if (canToggle)
                  TextButton(
                    onPressed: () async {
                      await widget.store.toggleTask(task);
                      if (mounted) setState(() {});
                    },
                    child: Text(
                      task.repeats
                          ? completed
                                ? '완료 취소'
                                : '오늘 완료'
                          : task.completedDay == null
                          ? '오늘 완료'
                          : '완료 취소',
                    ),
                  ),
                if (canMove)
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final next = DateTime.parse(day)
                          .add(const Duration(days: 1));
                      final initial = next.isAfter(now)
                          ? next
                          : now.add(const Duration(days: 1));
                      final picked = await showAppDatePicker(
                        context: context,
                        title: '할 일 옮길 날짜',
                        initialDate: initial,
                        firstDate: now,
                        lastDate: DateTime(2101),
                      );
                      if (picked == null) return;
                      final target = dayKey(picked);
                      final alreadyScheduled =
                          task.repeats && task.occursOn(target);
                      final bool moved;
                      if (task.repeats) {
                        moved = await widget.store.moveTaskOccurrence(
                          task,
                          day,
                          target,
                        );
                      } else {
                        moved = await widget.store.updateTask(
                          task,
                          task.title,
                          scheduledDay: target,
                          scheduledTime: task.scheduledTime,
                        );
                      }
                      if (mounted && context.mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              moved
                                  ? alreadyScheduled
                                        ? '$target에 원래 일정이 있어 한 번만 체크해요.'
                                        : '$target로 미뤘어요.'
                                  : '이 회차를 미루지 못했어요.',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('미루기'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gridScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.2);
    final cellHeight = 48 * gridScaler.scale(1);
    final compactHeading = MediaQuery.textScalerOf(context).scale(12) > 18;
    final firstWeekday = DateTime(month.year, month.month).weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((firstWeekday + days + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final canNext = month.isBefore(DateTime(2100, 12));
    final allGoals = [...widget.store.goals, ...widget.store.archivedGoals];
    final independentTasks = widget.store.tasks
        .where((task) => !task.roadmapLinked)
        .toList();
    final recordedDays = List.generate(days, (index) => days - index).where((
      day,
    ) {
      final key = dayKey(DateTime(month.year, month.month, day));
      return allGoals.any(
            (goal) => goal.isDoneOn(key) || goal.restDays.contains(key),
          ) ||
          independentTasks.any(
            (task) =>
                task.wasCompletedOn(key) ||
                task.wasSkippedOn(key) ||
                task.movedOccurrences.containsKey(key),
          ) ||
          widget.store.notes.any((note) => note.day == key);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                compactHeading
                    ? '${month.year}.${month.month.toString().padLeft(2, '0')}'
                    : '${month.year}년 ${month.month}월',
                textScaler: compactHeading ? gridScaler : null,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '이전 달',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed: canNext ? () => _changeMonth(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: const ['월', '화', '수', '목', '금', '토', '일']
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      textScaler: gridScaler,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 5),
        ...List.generate(
          cells ~/ 7,
          (week) => Row(
            children: List.generate(7, (weekday) {
              final day = week * 7 + weekday - firstWeekday + 1;
              if (day < 1 || day > days) {
                return Expanded(child: SizedBox(height: cellHeight));
              }
              final date = DateTime(month.year, month.month, day);
              final key = dayKey(date);
              final isFuture = date.isAfter(
                DateTime(today.year, today.month, today.day),
              );
              final done = allGoals.where((goal) => goal.isDoneOn(key)).length;
              final miniCount = allGoals
                  .where((goal) => _levelName(goal.completions[key]) == 'MINI')
                  .length;
              final moreCount = allGoals
                  .where((goal) => _levelName(goal.completions[key]) == 'MORE')
                  .length;
              final maxCount = allGoals
                  .where((goal) => _levelName(goal.completions[key]) == 'MAX')
                  .length;
              final tasksDone = independentTasks
                  .where((task) => task.wasCompletedOn(key))
                  .length;
              final tasksPlanned = widget.store.tasksPlannedOn(key).length;
              final tasksPaused = independentTasks.any(
                (task) =>
                    task.wasSkippedOn(key) ||
                    task.movedOccurrences.containsKey(key),
              );
              final hasNote = widget.store.notes.any((note) => note.day == key);
              final rested = allGoals.any(
                (goal) => goal.restDays.contains(key),
              );
              final isToday =
                  date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final isSelected =
                  selected?.year == date.year &&
                  selected?.month == date.month &&
                  selected?.day == date.day;
              return Expanded(
                child: Semantics(
                  label: isFuture
                      ? '${date.month}월 $day일, 앞으로 예정된 할 일 $tasksPlanned개'
                      : '${date.month}월 $day일, MINI $miniCount개, MORE $moreCount개, MAX $maxCount개, 예정된 할 일 $tasksPlanned개, 완료한 할 일 $tasksDone개${hasNote ? ', 메모 있음' : ''}${rested ? ', 쉬기 기록 있음' : ''}${tasksPaused ? ', 반복 예외 있음' : ''}',
                  child: InkWell(
                    onTap: () => setState(() => selected = date),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: cellHeight,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? palette.selected
                            : isFuture && tasksPlanned == 0
                            ? palette.subtle.withValues(alpha: .45)
                            : palette.card,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: isSelected || isToday
                              ? palette.pine
                              : palette.line,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            textScaler: gridScaler,
                            style: TextStyle(
                              color: isFuture && tasksPlanned == 0
                                  ? palette.muted.withValues(alpha: .55)
                                  : palette.ink,
                              fontWeight: isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                          if (done > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (miniCount > 0) _levelDot('MINI', key),
                                if (miniCount > 0 &&
                                    (moreCount > 0 || maxCount > 0))
                                  const SizedBox(width: 2),
                                if (moreCount > 0) _levelDot('MORE', key),
                                if (moreCount > 0 && maxCount > 0)
                                  const SizedBox(width: 2),
                                if (maxCount > 0) _levelDot('MAX', key),
                              ],
                            )
                          else if (rested)
                            Text(
                              '쉼',
                              textScaler: gridScaler,
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 10,
                              ),
                            ),
                          if (tasksDone > 0 ||
                              tasksPlanned > 0 ||
                              hasNote ||
                              tasksPaused)
                            Text(
                              [
                                if (tasksPlanned > 0) '○$tasksPlanned',
                                if (tasksDone > 0) '✓$tasksDone',
                                if (hasNote) '✎',
                                if (tasksPaused) '⏸',
                              ].join(' '),
                              textScaler: gridScaler,
                              style: TextStyle(
                                color: palette.pine,
                                fontSize: 9,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 13,
          runSpacing: 6,
          children: [
            for (final level in const ['MINI', 'MORE', 'MAX'])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _levelDot(level, 'legend'),
                  const SizedBox(width: 4),
                  Text(
                    level,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (selected == null) ...[
          Text('이번 달 기록', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          if (recordedDays.isEmpty)
            Text('아직 이 달에 남긴 기록이 없어요.', style: TextStyle(color: palette.muted)),
        ],
        if (selected == null)
          ...recordedDays.map((day) {
            final key = dayKey(DateTime(month.year, month.month, day));
            final lines = <String>[
              for (final task in independentTasks)
                if (task.wasCompletedOn(key)) '✓ ${task.title}',
              for (final task in independentTasks)
                if (task.wasSkippedOn(key)) '⏸ ${task.title} · 이번 회차 쉬기',
              for (final task in independentTasks)
                if (task.movedOccurrences.containsKey(key))
                  '↗ ${task.title} · ${task.movedOccurrences[key]}로 미룸',
              for (final note in widget.store.notes)
                if (note.day == key) '✎ ${note.text}',
            ];
            return Card(
              margin: const EdgeInsets.only(bottom: 9),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${month.month}월 $day일',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    for (final goal in allGoals)
                      if (goal.isDoneOn(key) || goal.restDays.contains(key))
                        _goalRecordLine(
                          goal.title,
                          goal.completions[key],
                          goal.completionActions[key],
                        ),
                    ...lines.map(
                      (line) => Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        if (selected != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${selected!.month}월 ${selected!.day}일 기록',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => selected = null),
                child: const Text('이번 달 전체'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (dayKey(selected!).compareTo(widget.store.today) <= 0 &&
              allGoals.any(
                (goal) => goal.startDay.compareTo(dayKey(selected!)) <= 0,
              ))
            TextButton.icon(
              onPressed: () => _editPractice(selected!),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('이날 목표 실천 수정'),
            ),
          ...allGoals
              .where(
                (goal) =>
                    goal.isDoneOn(dayKey(selected!)) ||
                    goal.restDays.contains(dayKey(selected!)),
              )
              .map((goal) {
                final key = dayKey(selected!);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _goalRecordLine(
                    goal.title,
                    goal.completions[key],
                    goal.completionActions[key],
                  ),
                );
              }),
          if (widget.store.tasksPlannedOn(dayKey(selected!)).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('이날 예정한 할 일', style: Theme.of(context).textTheme.titleSmall),
            for (final task in widget.store.tasksPlannedOn(dayKey(selected!)))
              _plannedTaskCard(context, task, dayKey(selected!)),
          ],
          ...independentTasks
              .where(
                (task) =>
                    task.wasCompletedOn(dayKey(selected!)) &&
                    !widget.store
                        .tasksPlannedOn(dayKey(selected!))
                        .contains(task),
              )
              .map(
                (task) => Text(
                  '✓ ${task.title}',
                  style: TextStyle(color: palette.muted),
                ),
              ),
          ...independentTasks
              .where((task) => task.wasSkippedOn(dayKey(selected!)))
              .map((task) => Text('⏸ ${task.title} · 이번 회차 쉬기')),
          ...independentTasks
              .where(
                (task) => task.movedOccurrences.containsKey(dayKey(selected!)),
              )
              .map(
                (task) => Text(
                  '↗ ${task.title} · ${task.movedOccurrences[dayKey(selected!)]}로 미룸',
                ),
              ),
          ...widget.store.notes
              .where((note) => note.day == dayKey(selected!))
              .map(
                (note) => Text(
                  '✎ ${note.text}',
                  style: TextStyle(color: palette.muted),
                ),
              ),
          if (!allGoals.any(
                (goal) =>
                    goal.isDoneOn(dayKey(selected!)) ||
                    goal.restDays.contains(dayKey(selected!)),
              ) &&
              !independentTasks.any(
                (task) =>
                    task.wasCompletedOn(dayKey(selected!)) ||
                    task.wasSkippedOn(dayKey(selected!)) ||
                    task.movedOccurrences.containsKey(dayKey(selected!)),
              ) &&
              widget.store.tasksPlannedOn(dayKey(selected!)).isEmpty &&
              !widget.store.notes.any((note) => note.day == dayKey(selected!)))
            Text('남긴 기록이 없어요.', style: TextStyle(color: palette.muted)),
        ],
      ],
    );
  }
}
