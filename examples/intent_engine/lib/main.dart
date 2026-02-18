import 'package:flutter/material.dart';

import 'theme.dart';

void main() {
  runApp(const IntentEngineApp());
}

/// Intent Engine demo app - on-device smart home control via LLM tool calling.
///
/// This is a placeholder main.dart. The full UI is built in plan 22-02.
class IntentEngineApp extends StatelessWidget {
  const IntentEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intent Engine',
      theme: AppTheme.themeData,
      home: const Scaffold(
        body: Center(
          child: Text('Intent Engine - UI coming in plan 22-02'),
        ),
      ),
    );
  }
}
