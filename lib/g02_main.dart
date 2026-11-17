
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/collision_test_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use the existing Firebase project and signed-in account.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const G02TestApp());
}

class G02TestApp extends StatelessWidget {
  const G02TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G02 Collision Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
        useMaterial3: true,
      ),
      home: const CollisionTestScreen(),
    );
  }
}
