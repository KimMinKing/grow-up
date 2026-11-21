/// Editable starting points; selecting one never creates or completes a task.
class TaskTemplate {
  const TaskTemplate(
    this.title,
    this.description,
    this.tag, {
    this.weekdays = const [],
  });

  final String title;
  final String description;
  final String tag;
  final List<int> weekdays;

  String get repeatPattern => weekdays.isEmpty ? 'daily' : 'weekly';
}

const taskTemplates = [
  TaskTemplate('책 한 쪽 읽기', '매일 · 펼치는 것부터 가볍게', '독서'),
  TaskTemplate('몸 풀기 2분', '매일 · 편한 범위에서 움직이기', '움직임'),
  TaskTemplate('오늘의 생각 한 줄 적기', '매일 · 길게 쓰지 않아도 괜찮아요', '기록'),
  TaskTemplate(
    '책상 한 곳 정리하기',
    '평일 · 작은 공간 하나만',
    '정리',
    weekdays: [1, 2, 3, 4, 5],
  ),
  TaskTemplate('이번 주 할 일 살펴보기', '일요일 · 남은 일을 다시 계획하기', '돌아보기', weekdays: [7]),
];
