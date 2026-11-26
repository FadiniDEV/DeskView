import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/controllers/app_controller.dart';
import 'presentation/screens/adaptive_shell_screen.dart';

/// Widget raiz da aplicação DeskView configurando o Material Design 3 e o tema personalizado.
class DeskViewApp extends StatelessWidget {
  final AppController controller;

  const DeskViewApp({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskView — Acesso Remoto Global & Controle de Periféricos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: AdaptiveShellScreen(controller: controller),
    );
  }
}
