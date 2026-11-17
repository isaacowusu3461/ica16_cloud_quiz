import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trivia_question.dart';

class TriviaService {
  static const String apiUrl =
      'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple';

  Future<List<TriviaQuestion>> fetchQuestions() async {
    // Fetch exactly 10 easy General Knowledge questions.
    final response = await http
        .get(Uri.parse(apiUrl))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'The question service returned HTTP ${response.statusCode}.',
      );
    }

    // A successful HTTP request can still contain an API error.
    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid API response.');
    }

    if (decoded['response_code'] != 0) {
      throw Exception('The question service returned an API error.');
    }

    final results = decoded['results'];

    if (results is! List || results.length != 10) {
      throw const FormatException(
        'The quiz must contain exactly 10 questions.',
      );
    }

    // Reject the entire round if any question is invalid.
    final questions = <TriviaQuestion>[];

    for (final item in results) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid question structure.');
      }

      questions.add(TriviaQuestion.fromJson(item));
    }

    return questions;
  }
}
