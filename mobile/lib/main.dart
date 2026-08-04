import 'package:flutter/material.dart';

import 'src/bridgepad_home.dart';

void main() => runApp(const BridgepadApp());

class BridgepadApp extends StatelessWidget {
  const BridgepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xff111417);
    const surface = Color(0xff1b2025);
    const amber = Color(0xffffb547);
    const cyan = Color(0xff63d8e5);
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(primary: cyan, secondary: amber, error: const Color(0xffff746c));
    return MaterialApp(
      title: 'BridgePad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          color: surface,
          margin: EdgeInsets.zero,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff242a30),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const BridgepadHome(),
    );
  }
}
