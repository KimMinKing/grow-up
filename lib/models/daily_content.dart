class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.title,
    required this.createdDay,
    this.completedDay,
    this.scheduledDay,
    this.scheduledTime,
    this.archived = false,
    List<ChecklistStep>? steps,
    this.repeatPattern = 'none',
    List<int>? repeatWeekdays,
    this.repeatIntervalDays = 2,
    List<String>? completedOccurrences,
    List<String>? skippedOccurrences,
    Map<String, String>? movedOccurrences,
    this.priority = 'normal',
    List<String>? tags,
    this.goalId,
    this.reminderEnabled = false,
    this.roadmapLinked = false,
  }) : steps = steps ?? [],
       repeatWeekdays = repeatWeekdays ?? [],
       completedOccurrences = completedOccurrences ?? [],
       skippedOccurrences = skippedOccurrences ?? [],
       movedOccurrences = movedOccurrences ?? {},
       tags = tags ?? [];

  final String id;
  String title;
  final String createdDay;
  String? completedDay;
  String? scheduledDay;
  String? scheduledTime;
  bool archived;
  final List<ChecklistStep> steps;
  String repeatPattern;
  final List<int> repeatWeekdays;
  int repeatIntervalDays;
  final List<String> completedOccurrences;
  final List<String> skippedOccurrences;
  final Map<String, String> movedOccurrences;
  String priority;
  final List<String> tags;
  String? goalId;
  bool reminderEnabled;
  final bool roadmapLinked;

  bool get repeats => repeatPattern != 'none';

  bool occursOn(String day) {
    if (!repeats || !validDailyKey(day)) return false;
    final anchor = scheduledDay ?? createdDay;
    if (skippedOccurrences.contains(day) || movedOccurrences.containsKey(day)) {
      return false;
    }
    if (movedOccurrences.containsValue(day)) return true;
    if (day.compareTo(anchor) < 0) return false;
    return _baseOccursOn(day, anchor);
  }

  bool _baseOccursOn(String day, String anchor) {
    if (repeatPattern == 'daily') return true;
    final date = _dateUtc(day);
    if (repeatPattern == 'weekly') return repeatWeekdays.contains(date.weekday);
    final start = _dateUtc(anchor);
    return date.difference(start).inDays % repeatIntervalDays == 0;
  }

  bool wasCompletedOn(String day) =>
      completedDay == day || completedOccurrences.contains(day);

  bool wasSkippedOn(String day) => skippedOccurrences.contains(day);

  String? nextOccurrenceAfter(String day) {
    if (!repeats || !validDailyKey(day)) return null;
    var date = _dateUtc(day).add(const Duration(days: 1));
    final anchor = _dateUtc(scheduledDay ?? createdDay);
    final excluded = {...skippedOccurrences, ...movedOccurrences.keys};
    final moved =
        movedOccurrences.values
            .where(
              (value) => value.compareTo(day) > 0 && !excluded.contains(value),
            )
            .toSet()
            .toList()
          ..sort();
    if (repeatPattern == 'weekly' && repeatWeekdays.isEmpty) {
      return moved.firstOrNull;
    }
    if (date.isBefore(anchor)) date = anchor;
    // Jump between scheduled candidates rather than imposing a 31-day horizon.
    // Each excluded candidate must be accounted for by a stored exception.
    for (
      var attempt = 0;
      attempt <= skippedOccurrences.length + movedOccurrences.length;
      attempt++
    ) {
      if (repeatPattern == 'weekly') {
        while (!repeatWeekdays.contains(date.weekday)) {
          date = date.add(const Duration(days: 1));
        }
      } else if (repeatPattern == 'interval') {
        final remainder = date.difference(anchor).inDays % repeatIntervalDays;
        if (remainder != 0) {
          date = date.add(Duration(days: repeatIntervalDays - remainder));
        }
      }
      final key = _dateKey(date);
      if (!excluded.contains(key)) {
        return moved.isNotEmpty && moved.first.compareTo(key) < 0
            ? moved.first
            : key;
      }
      date = date.add(const Duration(days: 1));
    }
    return moved.firstOrNull;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdDay': createdDay,
    'completedDay': completedDay,
    'scheduledDay': scheduledDay,
    'scheduledTime': scheduledTime,
    'archived': archived,
    'steps': steps.map((step) => step.toJson()).toList(),
    'repeatPattern': repeatPattern,
    'repeatWeekdays': repeatWeekdays,
    'repeatIntervalDays': repeatIntervalDays,
    'completedOccurrences': completedOccurrences,
    'skippedOccurrences': skippedOccurrences,
    'movedOccurrences': movedOccurrences,
    'priority': priority,
    'tags': tags,
    'goalId': goalId,
    'reminderEnabled': reminderEnabled,
    'roadmapLinked': roadmapLinked,
  };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final createdDay = json['createdDay'];
    final completedDay = json['completedDay'];
    final scheduledDay = json['scheduledDay'];
    final scheduledTime = json['scheduledTime'];
    final archived = json['archived'] ?? false;
    final rawSteps = json['steps'] ?? const [];
    final repeatPattern = json['repeatPattern'] ?? 'none';
    final rawWeekdays = json['repeatWeekdays'] ?? const [];
    final repeatIntervalDays = json['repeatIntervalDays'] ?? 2;
    final rawOccurrences = json['completedOccurrences'] ?? const [];
    final rawSkipped = json['skippedOccurrences'] ?? const [];
    final rawMoved = json['movedOccurrences'] ?? const <String, String>{};
    final priority = json['priority'] ?? 'normal';
    final rawTags = json['tags'] ?? const [];
    final goalId = json['goalId'];
    final reminderEnabled = json['reminderEnabled'] ?? false;
    final roadmapLinked = json['roadmapLinked'] ?? false;
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 160 ||
        createdDay is! String ||
        !validDailyKey(createdDay) ||
        (completedDay != null &&
            (completedDay is! String || !validDailyKey(completedDay))) ||
        (scheduledDay != null &&
            (scheduledDay is! String || !validDailyKey(scheduledDay))) ||
        (scheduledTime != null &&
            (scheduledTime is! String || !validTaskTime(scheduledTime))) ||
        archived is! bool ||
        rawSteps is! List ||
        rawSteps.length > 20 ||
        repeatPattern is! String ||
        !{'none', 'daily', 'weekly', 'interval'}.contains(repeatPattern) ||
        rawWeekdays is! List ||
        rawWeekdays.length > 7 ||
        repeatIntervalDays is! int ||
        repeatIntervalDays < 2 ||
        repeatIntervalDays > 30 ||
        rawOccurrences is! List ||
        rawOccurrences.length > 3660 ||
        rawSkipped is! List ||
        rawSkipped.length > 3660 ||
        rawMoved is! Map ||
        rawMoved.length > 3660 ||
        priority is! String ||
        !{'low', 'normal', 'high'}.contains(priority) ||
        rawTags is! List ||
        rawTags.length > 3 ||
        (goalId != null &&
            (goalId is! String || goalId.isEmpty || goalId.length > 120)) ||
        reminderEnabled is! bool ||
        roadmapLinked is! bool ||
        (roadmapLinked &&
            (goalId == null ||
                scheduledDay == null ||
                repeatPattern != 'none')) ||
        (reminderEnabled &&
            (scheduledTime == null ||
                (repeatPattern == 'none' && scheduledDay == null)))) {
      throw const FormatException('할 일 자료가 올바르지 않아요.');
    }
    final weekdays = rawWeekdays.cast<int>();
    final occurrences = rawOccurrences.cast<String>();
    final skipped = rawSkipped.cast<String>();
    final moved = Map<String, String>.from(rawMoved);
    final tags = rawTags.cast<String>();
    if (weekdays.toSet().length != weekdays.length ||
        weekdays.any((day) => day < 1 || day > 7) ||
        (repeatPattern == 'weekly' && weekdays.isEmpty) ||
        occurrences.toSet().length != occurrences.length ||
        occurrences.any((day) => !validDailyKey(day)) ||
        skipped.toSet().length != skipped.length ||
        skipped.any((day) => !validDailyKey(day)) ||
        tags.any(
          (tag) => tag.trim() != tag || tag.isEmpty || tag.length > 24,
        ) ||
        tags.map((tag) => tag.toLowerCase()).toSet().length != tags.length ||
        moved.entries.any(
          (entry) =>
              !validDailyKey(entry.key) ||
              !validDailyKey(entry.value) ||
              entry.key == entry.value,
        )) {
      throw const FormatException('반복 할 일 자료가 올바르지 않아요.');
    }
    final steps = rawSteps
        .map(
          (value) =>
              ChecklistStep.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    if (steps.map((step) => step.id).toSet().length != steps.length) {
      throw const FormatException('할 일 단계가 중복됐어요.');
    }
    return ChecklistItem(
      id: id,
      title: title.trim(),
      createdDay: createdDay,
      completedDay: completedDay as String?,
      scheduledDay: scheduledDay as String?,
      scheduledTime: scheduledTime as String?,
      archived: archived,
      steps: steps,
      repeatPattern: repeatPattern,
      repeatWeekdays: weekdays,
      repeatIntervalDays: repeatIntervalDays,
      completedOccurrences: occurrences,
      skippedOccurrences: skipped,
      movedOccurrences: moved,
      priority: priority,
      tags: tags,
      goalId: goalId as String?,
      reminderEnabled: reminderEnabled,
      roadmapLinked: roadmapLinked,
    );
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _dateUtc(String day) {
  final date = DateTime.parse(day);
  return DateTime.utc(date.year, date.month, date.day);
}

class ChecklistStep {
  ChecklistStep({
    required this.id,
    required this.title,
    this.completed = false,
    List<String>? completedDays,
  }) : completedDays = completedDays ?? [];

  final String id;
  String title;
  bool completed;
  final List<String> completedDays;

  bool isCompletedOn(String day, {required bool repeated}) =>
      repeated ? completedDays.contains(day) : completed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
    'completedDays': completedDays,
  };

  factory ChecklistStep.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final completed = json['completed'];
    final rawCompletedDays = json['completedDays'] ?? const [];
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 120 ||
        completed is! bool ||
        rawCompletedDays is! List ||
        rawCompletedDays.length > 3660) {
      throw const FormatException('할 일 단계가 올바르지 않아요.');
    }
    final completedDays = rawCompletedDays.cast<String>();
    if (completedDays.toSet().length != completedDays.length ||
        completedDays.any((day) => !validDailyKey(day))) {
      throw const FormatException('할 일 단계 날짜가 올바르지 않아요.');
    }
    return ChecklistStep(
      id: id,
      title: title.trim(),
      completed: completed,
      completedDays: completedDays,
    );
  }
}

bool validTaskTime(String value) =>
    RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

class DailyNote {
  DailyNote({required this.id, required this.day, required this.text});

  final String id;
  String day;
  String text;

  Map<String, dynamic> toJson() => {'id': id, 'day': day, 'text': text};

  factory DailyNote.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final day = json['day'];
    final text = json['text'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 80 ||
        day is! String ||
        !validDailyKey(day) ||
        text is! String ||
        text.trim().isEmpty ||
        text.length > 1000) {
      throw const FormatException('메모 자료가 올바르지 않아요.');
    }
    return DailyNote(id: id, day: day, text: text.trim());
  }
}

bool validDailyKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null &&
      '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}' ==
          value;
}
