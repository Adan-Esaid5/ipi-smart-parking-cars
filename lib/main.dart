import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/car_simulator_screen.dart';

/*
 * Car Simulator App
 * אפליקציה המדמה רכבים שנכנסים ויוצאים מחניונים.
 */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xhnmweojfldoexshwqgm.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhobm13ZW9qZmxkb2V4c2h3cWdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyODg1OTQsImV4cCI6MjA4OTg2NDU5NH0.ngr1k2A2dk8CXAIp3F8NAfK4fXVYMzio7EZG79ua2-Y',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Car Simulator',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFDFDFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF188038),
        ),
      ),
      home: const CarSimulatorScreen(),
    );
  }
}