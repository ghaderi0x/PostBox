import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final services = await AppServices.create();
    runApp(PostBoxApp(services: services));
  } on Object catch (e) {
    runApp(StartupErrorApp(error: e));
  }
}
