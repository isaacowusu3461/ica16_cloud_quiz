import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ValidationTestScreen extends StatefulWidget {
  const ValidationTestScreen({super.key});

  @override
  State<ValidationTestScreen> createState() => _ValidationTestScreenState();
}

class _ValidationTestScreenState extends State<ValidationTestScreen> {
  final roundIdController = TextEditingController(text: '2m4gQqIGPDyetCqQzcSL');

  bool isTesting = false;

  String? errorMessage;
  String? scoreResult;
  String? extraFieldResult;
  String? updateResult;
  String? preservationResult;

  @override
  void dispose() {
    roundIdController.dispose();
    super.dispose();
  }

  Map<String, dynamic> validPayload(int score) {
    return {
      'schemaVersion': 1,
      'variant': 'A',
      'categoryId': 9,
      'questionCount': 10,
      'correctCount': score,
      'submittedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<String> expectPermissionDenied(
    Future<void> Function() operation,
  ) async {
    try {
      await operation().timeout(const Duration(seconds: 12));

      return 'FAIL: Firestore allowed the operation.';
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return 'PASS: Firestore rejected the operation.';
      }

      return 'INCONCLUSIVE: Firestore returned ${error.code}.';
    } catch (error) {
      return 'INCONCLUSIVE: $error';
    }
  }

  Future<void> runValidationTests() async {
    if (isTesting) return;

    final user = FirebaseAuth.instance.currentUser;
    final roundId = roundIdController.text.trim();

    if (user == null) {
      setState(() {
        errorMessage = 'Please sign in before testing.';
      });
      return;
    }

    if (roundId.isEmpty) {
      setState(() {
        errorMessage = 'Please enter an existing round ID.';
      });
      return;
    }

    setState(() {
      isTesting = true;
      errorMessage = null;
      scoreResult = null;
      extraFieldResult = null;
      updateResult = null;
      preservationResult = null;
    });

    final uid = user.uid;

    final attempts = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attempts');

    final existingRef = attempts.doc(roundId);

    try {
      // First confirm that the original attempt exists on the server.
      final before = await existingRef.get(
        const GetOptions(source: Source.server),
      );

      if (!before.exists ||
          before.metadata.hasPendingWrites ||
          before.data() == null) {
        if (!mounted) return;

        setState(() {
          errorMessage =
              'The original attempt was not found or is not verified.';
        });
        return;
      }

      final originalData = before.data()!;
      final originalScore = originalData['correctCount'];
      final originalTimestamp = originalData['submittedAt'];

      if (originalScore is! int || originalTimestamp is! Timestamp) {
        if (!mounted) return;

        setState(() {
          errorMessage = 'The original attempt has invalid data.';
        });
        return;
      }

      // T11-A: Score 11 is outside the permitted range of 0 to 10.
      final invalidScoreRef = attempts.doc();

      final invalidScoreResult = await expectPermissionDenied(() {
        return invalidScoreRef.set(validPayload(11));
      });

      // T11-B: The rules must reject fields outside the six-field schema.
      final extraFieldRef = attempts.doc();

      final payloadWithExtraField = validPayload(5);
      payloadWithExtraField['studentNote'] = 'not allowed';

      final invalidFieldResult = await expectPermissionDenied(() {
        return extraFieldRef.set(payloadWithExtraField);
      });

      // T11-C: Try to update the already saved attempt.
      // The rules must reject updates, even from the document owner.
      final immutableResult = await expectPermissionDenied(() {
        return existingRef.update({
          'correctCount': originalScore == 10 ? 9 : 10,
        });
      });

      // Read the original attempt again to confirm it was preserved.
      final after = await existingRef.get(
        const GetOptions(source: Source.server),
      );

      String preservedResult;

      if (!after.exists || after.metadata.hasPendingWrites) {
        preservedResult = 'FAIL: The original attempt could not be verified.';
      } else {
        final afterData = after.data();

        final preserved =
            afterData != null &&
            afterData.length == originalData.length &&
            afterData['schemaVersion'] == originalData['schemaVersion'] &&
            afterData['variant'] == originalData['variant'] &&
            afterData['categoryId'] == originalData['categoryId'] &&
            afterData['questionCount'] == originalData['questionCount'] &&
            afterData['correctCount'] == originalScore &&
            afterData['submittedAt'] == originalTimestamp;

        preservedResult = preserved
            ? 'PASS: The original score and timestamp are unchanged.'
            : 'FAIL: The original attempt changed.';
      }

      if (!mounted) return;

      // Do not show old results after switching Firebase accounts.
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        setState(() {
          errorMessage = 'Authentication changed during testing.';
        });
        return;
      }

      setState(() {
        scoreResult = invalidScoreResult;
        extraFieldResult = invalidFieldResult;
        updateResult = immutableResult;
        preservationResult = preservedResult;
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Firestore test failed: ${error.code}.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Unable to finish T11: $error';
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
    if (result == null) {
      return const SizedBox.shrink();
    }

    final passed = result.startsWith('PASS:');
    final failed = result.startsWith('FAIL:');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              passed
                  ? Icons.check_circle
                  : failed
                  ? Icons.cancel
                  : Icons.info_outline,
              color: passed
                  ? Colors.green
                  : failed
                  ? Colors.red
                  : Colors.orange,
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
        title: const Text('T11 Validation Test'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Firestore Validation and Immutability',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'This test checks whether Firestore rejects invalid '
              'attempt data and prevents changes to saved attempts.',
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
            const SizedBox(height: 12),
            const Text(
              'Use a round ID belonging to the currently signed-in user.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isTesting ? null : runValidationTests,
              icon: const Icon(Icons.fact_check),
              label: const Text('Run T11 Validation Tests'),
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
            resultCard('Invalid score: 11', scoreResult),
            resultCard('Unauthorized extra field', extraFieldResult),
            resultCard('Update existing attempt', updateResult),
            resultCard('Original attempt preserved', preservationResult),
          ],
        ),
      ),
    );
  }
}
