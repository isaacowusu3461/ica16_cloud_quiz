import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/attempt_repository.dart';

class CollisionTestScreen extends StatefulWidget {
  const CollisionTestScreen({super.key});

  @override
  State<CollisionTestScreen> createState() => _CollisionTestScreenState();
}

class _CollisionTestScreenState extends State<CollisionTestScreen> {
  final repository = AttemptRepository();

  final roundIdController = TextEditingController();

  bool isTesting = false;

  String? errorMessage;
  String? collisionResult;
  String? scoreResult;
  String? timestampResult;
  String? documentResult;

  @override
  void dispose() {
    roundIdController.dispose();
    super.dispose();
  }

  Future<void> runCollisionTest() async {
    if (isTesting) return;

    final user = FirebaseAuth.instance.currentUser;
    final roundId = roundIdController.text.trim();

    if (user == null) {
      setState(() {
        errorMessage = 'Please sign in before running G02.';
      });
      return;
    }

    if (roundId.isEmpty) {
      setState(() {
        errorMessage = 'Enter an existing round ID.';
      });
      return;
    }

    final uid = user.uid;

    setState(() {
      isTesting = true;
      errorMessage = null;
      collisionResult = null;
      scoreResult = null;
      timestampResult = null;
      documentResult = null;
    });

    try {
      final reference = repository.attemptRef(uid, roundId);

      // Read the original record directly from the server.
      final before = await reference.get(
        const GetOptions(source: Source.server),
      );

      if (!before.exists ||
          before.metadata.hasPendingWrites ||
          before.data() == null) {
        if (!mounted) return;

        setState(() {
          errorMessage = 'No server-verified attempt was found for this ID.';
        });
        return;
      }

      final originalData = before.data()!;
      final originalScore = originalData['correctCount'];
      final originalTimestamp = originalData['submittedAt'];

      if (originalScore is! int ||
          originalScore < 0 ||
          originalScore > 10 ||
          originalTimestamp is! Timestamp) {
        if (!mounted) return;

        setState(() {
          errorMessage = 'The original attempt has invalid data.';
        });
        return;
      }

      // Change the score without changing the round ID.
      final differentScore = originalScore == 10 ? 9 : originalScore + 1;

      // The repository should detect the existing document and
      // reject the different payload without modifying Firestore.
      final submission = await repository.submitAttempt(
        uid: uid,
        roundId: roundId,
        score: differentScore,
      );

      // Read the document again to check whether it changed.
      final after = await reference.get(
        const GetOptions(source: Source.server),
      );

      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        setState(() {
          errorMessage = 'Authentication changed during G02.';
        });
        return;
      }

      final afterData = after.data();

      final collisionDetected = submission.status == AttemptStatus.collision;

      final scorePreserved =
          after.exists &&
          !after.metadata.hasPendingWrites &&
          afterData?['correctCount'] == originalScore;

      final timestampPreserved =
          after.exists &&
          !after.metadata.hasPendingWrites &&
          afterData?['submittedAt'] == originalTimestamp;

      final schemaPreserved =
          afterData != null &&
          afterData.length == 6 &&
          repository.matchesPayload(afterData, originalScore);

      setState(() {
        collisionResult = collisionDetected
            ? 'PASS: The repository detected the score collision.'
            : 'FAIL: Expected collision, received '
                  '${submission.status.name}.';

        scoreResult = scorePreserved
            ? 'PASS: Original score $originalScore/10 was preserved.'
            : 'FAIL: The original score changed.';

        timestampResult = timestampPreserved
            ? 'PASS: Original server timestamp was preserved.'
            : 'FAIL: The server timestamp changed.';

        documentResult = schemaPreserved
            ? 'PASS: The original six-field document is intact.'
            : 'FAIL: The saved document does not match the schema.';
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Firestore error: ${error.code}.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'G02 could not finish: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isTesting = false;
        });
      }
    }
  }

  Widget resultCard(String title, String? result) {
    if (result == null) return const SizedBox.shrink();

    final passed = result.startsWith('PASS:');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              passed ? Icons.check_circle : Icons.cancel,
              color: passed ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(result),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('G02 Collision Test'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Same-Round ID Collision Test',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This test tries to submit a different score '
              'using an existing round ID.',
            ),
            const SizedBox(height: 16),
            Text('Current account: ${user?.email ?? "Unknown"}'),
            const SizedBox(height: 20),
            TextField(
              controller: roundIdController,
              decoration: const InputDecoration(
                labelText: 'Existing Round ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the round ID created during G01, '
              'or another verified attempt belonging to this account.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isTesting ? null : runCollisionTest,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Run G02 Collision Test'),
            ),
            if (isTesting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            resultCard('Collision detection', collisionResult),
            resultCard('Score preservation', scoreResult),
            resultCard('Timestamp preservation', timestampResult),
            resultCard('Document integrity', documentResult),
          ],
        ),
      ),
    );
  }
}
