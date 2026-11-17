import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/attempt_repository.dart';

class ConcurrencyTestScreen extends StatefulWidget {
  const ConcurrencyTestScreen({super.key});

  @override
  State<ConcurrencyTestScreen> createState() => _ConcurrencyTestScreenState();
}

class _ConcurrencyTestScreenState extends State<ConcurrencyTestScreen> {
  final repository = AttemptRepository();

  bool isTesting = false;
  String? roundId;
  String? firstResult;
  String? secondResult;
  String? verificationResult;
  String? errorMessage;

  static const int testScore = 6;

  Future<void> runTest() async {
    if (isTesting) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        errorMessage = 'Please sign in before running G01.';
      });
      return;
    }

    final uid = user.uid;
    final id = repository.createRoundId();

    setState(() {
      isTesting = true;
      roundId = id;
      firstResult = null;
      secondResult = null;
      verificationResult = null;
      errorMessage = null;
    });

    try {
      // Both requests use exactly the same UID, ID, and score.
      // Future.wait starts both operations without waiting for
      // the first one to finish.
      final results = await Future.wait([
        repository.submitAttempt(uid: uid, roundId: id, score: testScore),
        repository.submitAttempt(uid: uid, roundId: id, score: testScore),
      ]);

      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        setState(() {
          errorMessage = 'The account changed during G01.';
        });
        return;
      }

      final first = results[0];
      final second = results[1];

      // Check the saved document directly from the server.
      final reference = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attempts')
          .doc(id);

      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );

      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        setState(() {
          errorMessage = 'The account changed during verification.';
        });
        return;
      }

      final data = snapshot.data();

      final validDocument =
          snapshot.exists &&
          !snapshot.metadata.hasPendingWrites &&
          repository.matchesPayload(data, testScore);

      final firstVerified = first.status == AttemptStatus.cloudVerified;

      final secondVerified = second.status == AttemptStatus.cloudVerified;

      setState(() {
        firstResult = firstVerified
            ? 'PASS: First submission was cloud verified.'
            : 'INCONCLUSIVE: ${first.status.name} — ${first.message}';

        secondResult = secondVerified
            ? 'PASS: Second submission was cloud verified.'
            : 'INCONCLUSIVE: ${second.status.name} — ${second.message}';

        verificationResult = validDocument
            ? 'PASS: One document exists at the shared round ID '
                  'with the expected score and server timestamp.'
            : 'FAIL: The saved document did not match the expected data.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'G01 could not finish: $error';
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
              passed ? Icons.check_circle : Icons.info_outline,
              color: passed ? Colors.green : Colors.orange,
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
        title: const Text('G01 Concurrency Test'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Concurrent Firestore Submissions',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This test submits the same round ID and score '
              'twice at nearly the same time.',
            ),
            const SizedBox(height: 16),
            Text('Account: ${user?.email ?? "Unknown"}'),
            const SizedBox(height: 8),
            const Text('Test score: 6 / 10'),
            const SizedBox(height: 8),
            if (roundId != null) SelectableText('Round ID: $roundId'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isTesting ? null : runTest,
              icon: const Icon(Icons.sync),
              label: const Text('Run G01 Test'),
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
            resultCard('First submission', firstResult),
            resultCard('Second submission', secondResult),
            resultCard('Server verification', verificationResult),
          ],
        ),
      ),
    );
  }
}
