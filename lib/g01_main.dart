
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/concurrency_test_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use the same Firebase project as the main quiz app.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const G01TestApp());
}

class G01TestApp extends StatelessWidget {
  const G01TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G01 Concurrency Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
        useMaterial3: true,
      ),
      home: const ConcurrencyTestScreen(),
    );
  }
}
