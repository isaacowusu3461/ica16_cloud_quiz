import 'package:html_unescape/html_unescape.dart';

class TriviaQuestion {
  final String question;
  final String correctAnswer;
  final List<String> choices;

  TriviaQuestion({
    required this.question,
    required this.correctAnswer,
    required this.choices,
  });

  factory TriviaQuestion.fromJson(Map<String, dynamic> json) {
    final decoder = HtmlUnescape();

    // Check that the API returned the correct question type.
    if (json['category'] != 'General Knowledge' ||
        json['difficulty'] != 'easy' ||
        json['type'] != 'multiple') {
      throw const FormatException('Invalid question category or type.');
    }

    final rawQuestion = json['question'];
    final rawCorrectAnswer = json['correct_answer'];
    final rawIncorrectAnswers = json['incorrect_answers'];

    if (rawQuestion is! String ||
        rawCorrectAnswer is! String ||
        rawIncorrectAnswers is! List ||
        rawIncorrectAnswers.length != 3) {
      throw const FormatException('Incomplete question data.');
    }

    if (rawIncorrectAnswers.any((answer) => answer is! String)) {
      throw const FormatException('Invalid answer format.');
    }

    // Decode HTML characters before checking and displaying answers.
    final question = decoder.convert(rawQuestion).trim();
    final correctAnswer = decoder.convert(rawCorrectAnswer).trim();

    final incorrectAnswers = rawIncorrectAnswers
        .cast<String>()
        .map((answer) => decoder.convert(answer).trim())
        .toList();

    final allAnswers = [correctAnswer, ...incorrectAnswers];

    if (question.isEmpty || allAnswers.any((answer) => answer.isEmpty)) {
      throw const FormatException('Empty question or answer.');
    }

    // Duplicate answers would make a multiple-choice question confusing.
    if (allAnswers.toSet().length != 4) {
      throw const FormatException('Duplicate answer choices.');
    }

    // Shuffle once so the answers do not move during screen rebuilds.
    final choices = List<String>.from(allAnswers)..shuffle();

    return TriviaQuestion(
      question: question,
      correctAnswer: correctAnswer,
      choices: List.unmodifiable(choices),
    );
  }
}
