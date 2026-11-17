import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/trivia_question.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_service.dart';

enum QuizCloudState {
  playing,
  readyToSubmit,
  submitting,
  verifying,
  saveUnknown,
  verificationUnavailable,
  permissionDenied,
  collision,
  cloudVerified,
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final triviaService = TriviaService();
  final attemptRepository = AttemptRepository();

  List<TriviaQuestion> questions = [];
  List<String?> selectedAnswers = [];

  int currentQuestionIndex = 0;
  int score = 0;

  bool isLoading = false;
  bool isFinished = false;
  bool isWorking = false;
  bool submissionStarted = false;
  bool injectLostAcknowledgement = false;

  String? errorMessage;
  String? cloudMessage;
  String? roundId;
  String? roundUid;

  int? frozenScore;
  DateTime? lastRequestTime;

  QuizCloudState cloudState = QuizCloudState.playing;

  @override
  void initState() {
    super.initState();
    loadQuestions();
  }

  bool get accountMatches {
    return roundUid != null &&
        FirebaseAuth.instance.currentUser?.uid == roundUid;
  }

  bool get needsRecovery {
    return cloudState == QuizCloudState.saveUnknown ||
        cloudState == QuizCloudState.verificationUnavailable;
  }

  bool get hasUnresolvedSubmission {
    return isWorking ||
        cloudState == QuizCloudState.submitting ||
        cloudState == QuizCloudState.verifying ||
        needsRecovery;
  }

  bool get canReplay {
    return !isLoading &&
        !isWorking &&
        (cloudState == QuizCloudState.readyToSubmit && !submissionStarted ||
            cloudState == QuizCloudState.cloudVerified);
  }

  Future<void> loadQuestions() async {
    if (isLoading || hasUnresolvedSubmission) return;

    // A submitted round must be verified before starting another one.
    if (isFinished && !canReplay) return;

    if (lastRequestTime != null) {
      final elapsed = DateTime.now().difference(lastRequestTime!);

      if (elapsed < const Duration(seconds: 5)) {
        setState(() {
          errorMessage =
              'Please wait five seconds before loading another quiz.';
        });
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        errorMessage = 'Please sign in before starting a quiz.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
      cloudMessage = null;
    });

    lastRequestTime = DateTime.now();

    try {
      final loadedQuestions = await triviaService.fetchQuestions();

      if (!mounted) return;

      // Ignore question results from an earlier signed-in account.
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        setState(() {
          isLoading = false;
          errorMessage = 'The signed-in account changed.';
        });
        return;
      }

      setState(() {
        questions = loadedQuestions;
        selectedAnswers = List<String?>.filled(10, null);
        currentQuestionIndex = 0;
        score = 0;
        frozenScore = null;
        isFinished = false;
        isLoading = false;
        isWorking = false;
        submissionStarted = false;
        injectLostAcknowledgement = false;

        // Only a new round receives a new document ID.
        roundId = attemptRepository.createRoundId();
        roundUid = user.uid;
        cloudState = QuizCloudState.playing;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Could not load the quiz: $error';
      });
    }
  }

  void selectAnswer(String answer) {
    if (isLoading || isFinished || !accountMatches) return;
    if (questions.isEmpty) return;
    if (selectedAnswers[currentQuestionIndex] != null) return;

    final question = questions[currentQuestionIndex];

    setState(() {
      selectedAnswers[currentQuestionIndex] = answer;

      if (answer == question.correctAnswer) {
        score++;
      }
    });
  }

  void nextQuestion() {
    if (!accountMatches || questions.isEmpty) return;
    if (selectedAnswers[currentQuestionIndex] == null) return;

    setState(() {
      if (currentQuestionIndex < questions.length - 1) {
        currentQuestionIndex++;
      } else {
        isFinished = true;

        // Freeze the score when the ten-question round ends.
        frozenScore = score;
        cloudState = QuizCloudState.readyToSubmit;
      }
    });
  }

  void applyCloudResult(AttemptResult result) {
    switch (result.status) {
      case AttemptStatus.cloudVerified:
        cloudState = QuizCloudState.cloudVerified;
        break;
      case AttemptStatus.notFound:
        // A server-confirmed absence permits a controlled retry.
        cloudState = QuizCloudState.readyToSubmit;
        break;
      case AttemptStatus.verificationUnavailable:
        cloudState = QuizCloudState.verificationUnavailable;
        break;
      case AttemptStatus.permissionDenied:
        cloudState = QuizCloudState.permissionDenied;
        break;
      case AttemptStatus.collision:
        cloudState = QuizCloudState.collision;
        break;
      case AttemptStatus.saveUnknown:
        cloudState = QuizCloudState.saveUnknown;
        break;
    }

    cloudMessage = result.message;
  }

  Future<void> submitQuiz() async {
    if (isWorking ||
        !isFinished ||
        !accountMatches ||
        roundId == null ||
        frozenScore == null ||
        cloudState != QuizCloudState.readyToSubmit) {
      return;
    }

    final uid = roundUid!;
    final id = roundId!;
    final submittedScore = frozenScore!;

    setState(() {
      isWorking = true;
      submissionStarted = true;
      cloudState = QuizCloudState.submitting;
      cloudMessage = 'Submitting this round to Firestore...';
    });

    final result = await attemptRepository.submitAttempt(
      uid: uid,
      roundId: id,
      score: submittedScore,
      injectLostAcknowledgement: injectLostAcknowledgement,
    );

    if (!mounted) return;

    if (FirebaseAuth.instance.currentUser?.uid != uid || roundId != id) {
      setState(() {
        isWorking = false;
        cloudState = QuizCloudState.saveUnknown;
        cloudMessage =
            'The account changed. The original submission needs recovery.';
      });
      return;
    }

    setState(() {
      isWorking = false;
      applyCloudResult(result);
    });
  }

  Future<void> verifySavedAttempt() async {
    if (isWorking ||
        !isFinished ||
        !accountMatches ||
        roundId == null ||
        frozenScore == null) {
      return;
    }

    final uid = roundUid!;
    final id = roundId!;
    final submittedScore = frozenScore!;

    setState(() {
      isWorking = true;
      cloudState = QuizCloudState.verifying;
      cloudMessage = 'Checking the original round on the server...';
    });

    final result = await attemptRepository.verifyAttempt(
      uid: uid,
      roundId: id,
      score: submittedScore,
    );

    if (!mounted) return;

    if (FirebaseAuth.instance.currentUser?.uid != uid || roundId != id) {
      setState(() {
        isWorking = false;
        cloudState = QuizCloudState.saveUnknown;
        cloudMessage = 'Authentication changed during verification.';
      });
      return;
    }

    setState(() {
      isWorking = false;
      applyCloudResult(result);
    });
  }

  Widget buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading General Knowledge questions...'),
        ],
      ),
    );
  }

  Widget buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 56, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              errorMessage ?? 'Unable to load questions.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: loadQuestions, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget buildQuizScreen() {
    final question = questions[currentQuestionIndex];
    final selected = selectedAnswers[currentQuestionIndex];
    final answered = selected != null;
    final correct = selected == question.correctAnswer;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Question ${currentQuestionIndex + 1} of 10',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: (currentQuestionIndex + 1) / 10),
          const SizedBox(height: 12),
          Text('Current score: $score'),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                question.question,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // The question model already shuffled these answers.
          for (final answer in question.choices) ...[
            OutlinedButton(
              onPressed: answered || !accountMatches
                  ? null
                  : () => selectAnswer(answer),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
              ),
              child: Text(answer),
            ),
            const SizedBox(height: 10),
          ],

          if (answered) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  color: correct ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correct
                        ? 'Correct answer!'
                        : 'Incorrect. Correct answer: '
                              '${question.correctAnswer}',
                    style: TextStyle(
                      color: correct ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: nextQuestion,
              child: Text(
                currentQuestionIndex == 9 ? 'View Results' : 'Next Question',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildCloudSection() {
    final verified = cloudState == QuizCloudState.cloudVerified;
    final canSubmit = cloudState == QuizCloudState.readyToSubmit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Cloud Submission',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SelectableText('Round ID: ${roundId ?? "Not created"}'),
        const SizedBox(height: 8),
        Text('Status: ${cloudState.name}'),
        const SizedBox(height: 12),

        if (cloudMessage != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                verified ? Icons.cloud_done : Icons.info_outline,
                color: verified ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(cloudMessage!)),
            ],
          ),

        const SizedBox(height: 16),

        if (canSubmit)
          FilledButton.icon(
            onPressed: isWorking || !accountMatches ? null : submitQuiz,
            icon: const Icon(Icons.cloud_upload),
            label: Text(
              submissionStarted ? 'Retry Same Round ID' : 'Submit to Firestore',
            ),
          ),

        if (needsRecovery)
          FilledButton.icon(
            onPressed: isWorking || !accountMatches ? null : verifySavedAttempt,
            icon: const Icon(Icons.cloud_sync),
            label: const Text('Recover from Server'),
          ),

        if (verified)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Cloud verified',
              style: TextStyle(
                color: Colors.green,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        if (isWorking) ...[
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],

        // This fault switch is only for the later T09 test.
        if (!submissionStarted &&
            !isWorking &&
            cloudState == QuizCloudState.readyToSubmit)
          SwitchListTile(
            title: const Text('Inject lost acknowledgement'),
            subtitle: const Text('Development test only'),
            value: injectLostAcknowledgement,
            onChanged: (value) {
              setState(() {
                injectLostAcknowledgement = value;
              });
            },
          ),

        if (needsRecovery)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'The save outcome is not confirmed. '
              'Reconnect to the internet and use Recover from Server. '
              'Do not start a new round yet.',
            ),
          ),
      ],
    );
  }

  Widget buildResultsScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: Colors.indigo,
          ),
          const SizedBox(height: 12),
          const Text(
            'Quiz Completed!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Your score: $score / 10',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text(
            'Answer Review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Keep the complete review visible after the round ends.
          for (int i = 0; i < questions.length; i++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${questions[i].question}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Your answer: ${selectedAnswers[i]}'),
                    const SizedBox(height: 4),
                    Text('Correct answer: ${questions[i].correctAnswer}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          selectedAnswers[i] == questions[i].correctAnswer
                              ? Icons.check_circle
                              : Icons.cancel,
                          color:
                              selectedAnswers[i] == questions[i].correctAnswer
                              ? Colors.green
                              : Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          selectedAnswers[i] == questions[i].correctAnswer
                              ? 'Correct'
                              : 'Incorrect',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          buildCloudSection(),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: canReplay ? loadQuestions : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Replay Quiz'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasUnresolvedSubmission,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('General Knowledge Quiz'),
          backgroundColor: Colors.indigo.shade100,
        ),
        body: isLoading
            ? buildLoadingScreen()
            : questions.isEmpty
            ? buildErrorScreen()
            : isFinished
            ? buildResultsScreen()
            : buildQuizScreen(),
      ),
    );
  }
}
