import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import 'gui/engine_shell.dart';
import 'services/colab_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  MediaKit.ensureInitialized();

  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('Rust init error: $e');
  }

  try {
    await ColabService().init();
  } catch (e) {
    debugPrint('ColabService init error: $e');
  }

  runApp(const PrApp());
}
