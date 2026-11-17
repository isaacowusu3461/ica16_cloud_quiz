import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SecurityTestScreen extends StatefulWidget {
  const SecurityTestScreen({super.key});

  @override
  State<SecurityTestScreen> createState() => _SecurityTestScreenState();
}

class _SecurityTestScreenState extends State<SecurityTestScreen> {
  final ownerUidController = TextEditingController();
  final roundIdController = TextEditingController(text: '2m4gQqIGPDyetCqQzcSL');

  bool isTesting = false;
  String? readResult;
  String? writeResult;
  String? errorMessage;

  @override
  void dispose() {
    ownerUidController.dispose();
    roundIdController.dispose();
    super.dispose();
  }

  Future<void> runSecurityTest() async {
    if (isTesting) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final ownerUid = ownerUidController.text.trim();
    final roundId = roundIdController.text.trim();

    if (currentUser == null) {
      setState(() {
        errorMessage = 'Please sign in before running this test.';
      });
      return;
    }

    if (ownerUid.isEmpty || roundId.isEmpty) {
      setState(() {
        errorMessage = 'Enter User A UID and the saved round ID.';
      });
      return;
    }

    if (currentUser.uid == ownerUid) {
      setState(() {
        errorMessage =
            'This is a cross-user test. Sign in as User B, '
            'not the owner of this attempt.';
      });
      return;
    }

    setState(() {
      isTesting = true;
      readResult = null;
      writeResult = null;
      errorMessage = null;
    });

    final testingUid = currentUser.uid;

    // This points to User A's document, not User B's document.
    final attemptRef = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('attempts')
        .doc(roundId);

    try {
      // T10-A: User B tries to read User A's document.
      try {
        await attemptRef.get(const GetOptions(source: Source.server));

        readResult =
            'FAIL: Firestore allowed User B to read User A\'s attempt.';
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          readResult = 'PASS: Firestore denied the cross-user read.';
        } else {
          readResult = 'INCONCLUSIVE: Read failed with ${error.code}.';
        }
      } catch (error) {
        readResult = 'INCONCLUSIVE: $error';
      }

      // T10-B: User B tries to create a new document in User A's path.
      // We use a separate test ID so the existing attempt is untouched.
      final testDocumentId =
          'security-test-${DateTime.now().millisecondsSinceEpoch}';

      final testRef = FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .collection('attempts')
          .doc(testDocumentId);

      try {
        await testRef.set({
          'schemaVersion': 1,
          'variant': 'A',
          'categoryId': 9,
          'questionCount': 10,
          'correctCount': 5,
          'submittedAt': FieldValue.serverTimestamp(),
        });

        writeResult = 'FAIL: Firestore allowed User B to write under User A.';
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          writeResult = 'PASS: Firestore denied the cross-user write.';
        } else {
          writeResult = 'INCONCLUSIVE: Write failed with ${error.code}.';
        }
      } catch (error) {
        writeResult = 'INCONCLUSIVE: $error';
      }

      if (!mounted) return;

      // Do not display results from a different authentication session.
      if (FirebaseAuth.instance.currentUser?.uid != testingUid) {
        setState(() {
          errorMessage = 'Authentication changed during testing.';
          readResult = null;
          writeResult = null;
        });
        return;
      }

      setState(() {});
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
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('T10 Security Test'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cross-User Firestore Security',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sign in as User B, then try to access an attempt '
              'that belongs to User A.',
            ),
            const SizedBox(height: 16),
            Text('Current account: ${currentUser?.email ?? "Unknown"}'),
            const SizedBox(height: 6),
            SelectableText('Current UID: ${currentUser?.uid ?? "Unknown"}'),
            const SizedBox(height: 20),
            TextField(
              controller: ownerUidController,
              decoration: const InputDecoration(
                labelText: 'User A UID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roundIdController,
              decoration: const InputDecoration(
                labelText: 'User A Round ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isTesting ? null : runSecurityTest,
              icon: const Icon(Icons.security),
              label: const Text('Run T10 Security Test'),
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
            resultCard('Cross-user read', readResult),
            resultCard('Cross-user write', writeResult),
          ],
        ),
      ),
    );
  }
}
