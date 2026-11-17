import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/quiz_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Connect Firebase before starting the application.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const CloudQuizApp());
}

class CloudQuizApp extends StatelessWidget {
  const CloudQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICA16 Cloud Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF0F3F8),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to check authentication.')),
          );
        }

        if (snapshot.hasData) {
          return SignedInScreen(key: ValueKey(snapshot.data!.uid));
        }

        return const SignInScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  String? errorMessage;

  Future<void> signIn() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Sign in using an existing Firebase Authentication account.
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      String message;

      if (error.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      } else if (error.code == 'invalid-credential' ||
          error.code == 'wrong-password' ||
          error.code == 'user-not-found') {
        message = 'Incorrect email or password.';
      } else if (error.code == 'network-request-failed') {
        message = 'Please check your internet connection.';
      } else if (error.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      } else {
        message = 'Sign-in failed. Please try again.';
      }

      setState(() {
        errorMessage = message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ICA16 Cloud Quiz'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.quiz_outlined, size: 64, color: Colors.indigo),
                const SizedBox(height: 16),
                const Text(
                  'General Knowledge Quiz',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to start your quiz.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (errorMessage != null) ...[
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: isLoading ? null : signIn,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignedInScreen extends StatefulWidget {
  const SignedInScreen({super.key});

  @override
  State<SignedInScreen> createState() => _SignedInScreenState();
}

class _SignedInScreenState extends State<SignedInScreen> {
  final roundIdController = TextEditingController(text: 'IWS7OnL44j6R7iwIGTZX');

  bool isSigningOut = false;
  bool isVerifying = false;

  String? errorMessage;
  String? verificationMessage;

  Map<String, dynamic>? verifiedAttempt;

  @override
  void dispose() {
    roundIdController.dispose();
    super.dispose();
  }

  Future<void> signOut() async {
    if (isSigningOut || isVerifying) return;

    setState(() {
      isSigningOut = true;
      errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Could not sign out. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isSigningOut = false;
        });
      }
    }
  }

  void startQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QuizScreen()),
    );
  }

  Future<void> verifyPreviousAttempt() async {
    if (isVerifying) return;

    final user = FirebaseAuth.instance.currentUser;
    final roundId = roundIdController.text.trim();

    if (user == null) {
      setState(() {
        errorMessage = 'Please sign in first.';
      });
      return;
    }

    if (roundId.isEmpty) {
      setState(() {
        errorMessage = 'Please enter a round ID.';
      });
      return;
    }

    setState(() {
      isVerifying = true;
      errorMessage = null;
      verificationMessage = null;
      verifiedAttempt = null;
    });

    try {
      // Always read from the server, not the local Firestore cache.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('attempts')
          .doc(roundId)
          .get(const GetOptions(source: Source.server));

      if (!mounted) return;

      // Ignore a result if the signed-in account changed during the read.
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        setState(() {
          errorMessage = 'The signed-in account changed.';
        });
        return;
      }

      if (!snapshot.exists) {
        setState(() {
          errorMessage = 'No saved attempt was found for this round ID.';
        });
        return;
      }

      if (snapshot.metadata.hasPendingWrites) {
        setState(() {
          errorMessage = 'The attempt still has pending writes.';
        });
        return;
      }

      final data = snapshot.data();

      if (data == null ||
          data.length != 6 ||
          data['schemaVersion'] != 1 ||
          data['variant'] != 'A' ||
          data['categoryId'] != 9 ||
          data['questionCount'] != 10 ||
          data['correctCount'] is! int ||
          (data['correctCount'] as int) < 0 ||
          (data['correctCount'] as int) > 10 ||
          data['submittedAt'] is! Timestamp) {
        setState(() {
          errorMessage =
              'The saved document does not match the required schema.';
        });
        return;
      }

      setState(() {
        verifiedAttempt = data;
        verificationMessage =
            'Cloud verified. This attempt was retrieved from the server.';
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        if (error.code == 'permission-denied') {
          errorMessage = 'Permission denied. You cannot read this attempt.';
        } else {
          errorMessage = 'Server verification failed: ${error.code}.';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Unable to retrieve the saved attempt.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isVerifying = false;
        });
      }
    }
  }

  Widget buildPreviousAttemptSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Verify Previous Attempt',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter a saved round ID to retrieve the attempt from Firestore.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: roundIdController,
              decoration: const InputDecoration(
                labelText: 'Round ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isVerifying ? null : verifyPreviousAttempt,
              icon: const Icon(Icons.cloud_sync),
              label: Text(
                isVerifying ? 'Checking Server...' : 'Verify Previous Attempt',
              ),
            ),
            if (isVerifying) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            if (verificationMessage != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verificationMessage!,
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (verifiedAttempt != null) ...[
              const SizedBox(height: 12),
              Text(
                'Score: ${verifiedAttempt!['correctCount']} / '
                '${verifiedAttempt!['questionCount']}',
              ),
              const SizedBox(height: 6),
              Text('Variant: ${verifiedAttempt!['variant']}'),
              const SizedBox(height: 6),
              Text('Category ID: ${verifiedAttempt!['categoryId']}'),
              const SizedBox(height: 6),
              Text(
                'Submitted at: '
                '${(verifiedAttempt!['submittedAt'] as Timestamp).toDate().toLocal()}',
              ),
            ],
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
        title: const Text('ICA16 Cloud Quiz'),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 60,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Signed in successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Account: ${user?.email ?? "Unknown"}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: startQuiz,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Quiz'),
                ),
                const SizedBox(height: 20),
                buildPreviousAttemptSection(),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: isSigningOut || isVerifying ? null : signOut,
                  icon: const Icon(Icons.logout),
                  label: Text(isSigningOut ? 'Signing out...' : 'Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
