import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/roadmap_plan.dart';

class RoadmapRequest {
  const RoadmapRequest({
    required this.goal,
    required this.currentLevel,
    required this.targetDate,
    required this.availableMinutes,
    required this.preferredPath,
    required this.mini,
    required this.more,
    required this.max,
    required this.firstMilestone,
  });

  final String goal;
  final String currentLevel;
  final String targetDate;
  final int availableMinutes;
  final String preferredPath;
  final String mini;
  final String more;
  final String max;
  final String firstMilestone;

  Map<String, dynamic> toJson() => {
    'goal': goal.trim(),
    'currentLevel': currentLevel.trim(),
    'targetDate': targetDate,
    'availableMinutes': availableMinutes,
    'preferredPath': preferredPath,
    'mini': mini.trim(),
    'more': more.trim(),
    'max': max.trim(),
    'firstMilestone': firstMilestone.trim(),
  };
}

class RoadmapGenerationException implements Exception {
  const RoadmapGenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class RoadmapGenerator {
  Future<List<RoadmapPlan>> generate(RoadmapRequest request);
}

class HttpRoadmapGenerator implements RoadmapGenerator {
  HttpRoadmapGenerator({
    required this.endpoint,
    required this.accessToken,
    required this.client,
    this.publishableKey,
    this.timeout = const Duration(seconds: 40),
  });

  final Uri endpoint;
  final Future<String?> Function() accessToken;
  final http.Client client;
  final String? publishableKey;
  final Duration timeout;

  @override
  Future<List<RoadmapPlan>> generate(RoadmapRequest request) async {
    if (endpoint.scheme != 'https' ||
        !_boundedText(request.goal, 120) ||
        !_boundedText(request.currentLevel, 160) ||
        !_boundedText(request.preferredPath, 60) ||
        !_boundedText(request.mini, 160) ||
        !_boundedText(request.more, 160) ||
        !_boundedText(request.max, 160) ||
        !_boundedText(request.firstMilestone, 120, optional: true) ||
        !_validDay(request.targetDate) ||
        request.availableMinutes < 1 ||
        request.availableMinutes > 10080) {
      throw const RoadmapGenerationException('계획을 요청할 정보를 확인해 주세요.');
    }
    final requestBody = jsonEncode(request.toJson());
    if (utf8.encode(requestBody).length > 4096) {
      throw const RoadmapGenerationException('계획을 요청할 정보를 확인해 주세요.');
    }
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const RoadmapGenerationException('로그인 후 AI 계획을 요청할 수 있어요.');
    }
    try {
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      if (publishableKey != null) headers['apikey'] = publishableKey!;
      final response = await client
          .post(endpoint, headers: headers, body: requestBody)
          .timeout(timeout);
      if (response.statusCode == 429) {
        throw const RoadmapGenerationException(
          '이번 달 AI 계획 사용 한도에 도달했어요. 수동 시작안으로 계속할 수 있어요.',
        );
      }
      if (response.statusCode != 200) {
        throw const RoadmapGenerationException(
          'AI 계획을 가져오지 못했어요. 수동 시작안으로 계속할 수 있어요.',
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map) throw const FormatException('Invalid response');
      return parseAiRoadmapOptions(
        body['plans'],
        availableMinutes: request.availableMinutes,
      );
    } on RoadmapGenerationException {
      rethrow;
    } catch (_) {
      throw const RoadmapGenerationException(
        'AI 계획을 확인하지 못했어요. 수동 시작안으로 계속할 수 있어요.',
      );
    }
  }
}

bool _boundedText(String value, int max, {bool optional = false}) {
  final length = value.trim().length;
  return length <= max && (optional || length > 0);
}

bool _validDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' ==
          value;
}
