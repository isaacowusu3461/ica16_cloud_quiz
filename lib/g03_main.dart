import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/stale_auth_test_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use the same Firebase configuration as the quiz application.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const G03TestApp());
}

class G03TestApp extends StatelessWidget {
  const G03TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G03 Stale Auth Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const StaleAuthTestScreen(),
    );
  }
}
