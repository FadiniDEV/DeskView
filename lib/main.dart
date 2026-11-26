import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repositories/local_identity_repository.dart';
import 'platform/native_platform_bridge.dart';
import 'presentation/controllers/app_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  int? customPort;
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') {
      customPort = int.tryParse(args[i + 1]);
    }
  }

  final LocalIdentityRepository identityRepository = LocalIdentityRepository();
  await identityRepository.loadOrCreateIdentity(overridePort: customPort);

  final NativePlatformBridge platformBridge = NativePlatformBridge();
  final AppController controller = AppController(
    identityRepository: identityRepository,
    platformBridge: platformBridge,
  );

  await controller.initialize();

  runApp(DeskViewApp(controller: controller));
}
