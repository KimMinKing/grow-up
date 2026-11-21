import 'package:flutter/material.dart';

import 'theme/app_palette.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required String title,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppPalette.of(context).paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _AppDatePicker(
      title: title,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _AppDatePicker extends StatefulWidget {
  const _AppDatePicker({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<_AppDatePicker> {
  late final DateTime first = _dateOnly(widget.firstDate);
  late final DateTime last = _dateOnly(widget.lastDate);
  late DateTime selected = _clamp(_dateOnly(widget.initialDate));
  late DateTime month = DateTime(selected.year, selected.month);

  DateTime _clamp(DateTime date) {
    if (date.isBefore(first)) return first;
    if (date.isAfter(last)) return last;
    return date;
  }

  bool _inRange(DateTime date) => !date.isBefore(first) && !date.isAfter(last);

  void _changeMonth(int difference) {
    final next = DateTime(month.year, month.month + difference);
    if (next.isBefore(DateTime(first.year, first.month)) ||
        next.isAfter(DateTime(last.year, last.month))) {
      return;
    }
    setState(() => month = next);
  }

  Future<void> _chooseYear() async {
    final yearListController = ScrollController(
      initialScrollOffset: ((month.year - first.year - 2).clamp(
        0,
        last.year - first.year,
      )) * 56.0,
    );
    final year = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('연도 선택'),
        content: SizedBox(
          width: 280,
          height: 300,
          child: ListView.builder(
            controller: yearListController,
            itemExtent: 56,
            itemCount: last.year - first.year + 1,
            itemBuilder: (context, index) {
              final value = first.year + index;
              return ListTile(
                selected: value == month.year,
                title: Text('$value년'),
                onTap: () => Navigator.pop(dialogContext, value),
              );
            },
          ),
        ),
      ),
    );
    yearListController.dispose();
    if (year == null || !mounted) return;
    final next = DateTime(year, month.month);
    final firstMonth = DateTime(first.year, first.month);
    final lastMonth = DateTime(last.year, last.month);
    setState(() {
      month = next.isBefore(firstMonth)
          ? firstMonth
          : next.isAfter(lastMonth)
          ? lastMonth
          : next;
    });
  }

  void _select(DateTime date) {
    if (!_inRange(date)) return;
    setState(() {
      selected = date;
      month = DateTime(date.year, date.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final today = _dateOnly(DateTime.now());
    final firstWeekday = DateTime(month.year, month.month).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    final previousMonthAvailable = month.isAfter(
      DateTime(first.year, first.month),
    );
    final nextMonthAvailable = month.isBefore(DateTime(last.year, last.month));
    final weekday = const [
      '월',
      '화',
      '수',
      '목',
      '금',
      '토',
      '일',
    ][selected.weekday - 1];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  '날짜를 고른 뒤 아래에서 선택해 주세요.',
                  style: TextStyle(color: palette.muted),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.line),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '이전 달',
                            onPressed: previousMonthAvailable
                                ? () => _changeMonth(-1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: _chooseYear,
                              child: Text(
                                '${month.year}년 ${month.month}월',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '다음 달',
                            onPressed: nextMonthAvailable
                                ? () => _changeMonth(1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          for (final label in const [
                            '월',
                            '화',
                            '수',
                            '목',
                            '금',
                            '토',
                            '일',
                          ])
                            Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cellCount,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          final day = index - firstWeekday + 1;
                          if (day < 1 || day > daysInMonth) {
                            return const SizedBox.shrink();
                          }
                          final date = DateTime(month.year, month.month, day);
                          final active = _inRange(date);
                          final chosen = date == selected;
                          final current = date == today;
                          return Padding(
                            padding: const EdgeInsets.all(2),
                            child: Material(
                              color: chosen ? palette.pine : Colors.transparent,
                              shape: CircleBorder(
                                side: current && !chosen
                                    ? BorderSide(color: palette.pine)
                                    : BorderSide.none,
                              ),
                              child: InkWell(
                                key: ValueKey(
                                  'date-${date.year}-${date.month}-$day',
                                ),
                                customBorder: const CircleBorder(),
                                onTap: active ? () => _select(date) : null,
                                child: Center(
                                  child: Text(
                                    '$day',
                                    style: TextStyle(
                                      fontWeight: chosen || current
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: chosen
                                          ? Colors.white
                                          : active
                                          ? palette.ink
                                          : palette.muted.withValues(alpha: .4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (_inRange(today))
                      ActionChip(
                        label: const Text('오늘'),
                        onPressed: () => _select(today),
                      ),
                    if (_inRange(today.add(const Duration(days: 1))))
                      ActionChip(
                        label: const Text('내일'),
                        onPressed: () =>
                            _select(today.add(const Duration(days: 1))),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '선택한 날짜 · ${selected.year}년 ${selected.month}월 ${selected.day}일 ($weekday)',
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('날짜 선택'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
