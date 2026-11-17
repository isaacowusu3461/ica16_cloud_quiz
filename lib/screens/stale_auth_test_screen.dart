import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StaleAuthTestScreen extends StatefulWidget {
  const StaleAuthTestScreen({super.key});

  @override
  State<StaleAuthTestScreen> createState() => _StaleAuthTestScreenState();
}

class _StaleAuthTestScreenState extends State<StaleAuthTestScreen> {
  final FirebaseAuth auth = FirebaseAuth.instance;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isTesting = false;
  bool waitingForSwitch = false;
  bool responseApplied = false;

  String? originalUid;
  String? resultMessage;
  String? testStatus;

  Completer<void>? responseGate;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    // Release any pending test operation when leaving the screen.
    if (responseGate != null && !responseGate!.isCompleted) {
      responseGate!.complete();
    }

    super.dispose();
  }

  Future<void> startTest() async {
    if (isTesting) return;

    final user = auth.currentUser;

    if (user == null) {
      setState(() {
        testStatus = 'FAIL';
        resultMessage = 'Sign in as User A before starting G03.';
      });
      return;
    }

    final uid = user.uid;
    final gate = Completer<void>();

    responseGate = gate;

    setState(() {
      isTesting = true;
      waitingForSwitch = true;
      responseApplied = false;
      originalUid = uid;
      testStatus = 'WAITING';
      resultMessage =
          'A simulated response for User A is waiting. '
          'Sign in as User B to release it.';
    });

    // This models a response that was requested under User A.
    // The gate lets us decide exactly when it returns.
    final delayedResponse = () async {
      await gate.future;

      return {
        'requestedUid': uid,
        'correctCount': 6,
        'roundId': 'g03-simulated-response',
      };
    }();

    final response = await delayedResponse;

    if (!mounted) return;

    final currentUid = auth.currentUser?.uid;
    final requestedUid = response['requestedUid'];

    // This is the same type of UID guard used in the quiz flow.
    if (currentUid != requestedUid) {
      setState(() {
        isTesting = false;
        waitingForSwitch = false;
        responseApplied = false;
        testStatus = 'PASS';
        resultMessage =
            'The old response was rejected because the '
            'authenticated UID changed.';
      });
      return;
    }

    setState(() {
      isTesting = false;
      waitingForSwitch = false;
      responseApplied = true;
      testStatus = 'FAIL';
      resultMessage =
          'The response was applied because the UID did not change.';
    });
  }

  Future<void> switchAccount() async {
    if (!waitingForSwitch || responseGate == null) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        resultMessage = 'Enter User B email and password.';
      });
      return;
    }

    try {
      // Sign out User A and authenticate User B.
      await auth.signOut();

      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (credential.user?.uid == originalUid) {
        setState(() {
          resultMessage =
              'You signed in as the same user. '
              'Use a different account for G03.';
        });
        return;
      }

      setState(() {
        resultMessage =
            'User B signed in. Releasing User A\'s delayed response...';
      });

      // The simulated response now arrives under User B's session.
      if (!responseGate!.isCompleted) {
        responseGate!.complete();
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        resultMessage = 'Authentication error: ${error.code}.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        resultMessage = 'Could not switch accounts: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('G03 Stale Auth Test'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Stale Authentication Response',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start a delayed response under User A, '
              'then sign in as User B before releasing it.',
            ),
            const SizedBox(height: 16),
            Text('Current account: ${user?.email ?? "Signed out"}'),
            const SizedBox(height: 8),
            Text('Original UID: ${originalUid ?? "Not started"}'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isTesting ? null : startTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start G03 Test'),
            ),
            if (waitingForSwitch) ...[
              const SizedBox(height: 24),
              const Text(
                'Sign in as User B',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'User B Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'User B Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: switchAccount,
                child: const Text('Switch Account and Release Response'),
              ),
            ],
            if (testStatus != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: $testStatus',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: testStatus == 'PASS'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(resultMessage ?? ''),
                    ],
                  ),
                ),
              ),
            ],
            if (responseApplied)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Warning: A stale response was applied.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
