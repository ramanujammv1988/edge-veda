import 'package:flutter/material.dart';

import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthAdvisorApp());
}

class HealthAdvisorApp extends StatelessWidget {
  const HealthAdvisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Advisor',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Main screen -- will be completed with full UI in Task 2.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Health Advisor'),
      ),
    );
  }
}
