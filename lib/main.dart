import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'services/library_repository.dart';
import 'services/player_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final state = AppState(
    repository: LibraryRepository(),
    player: PlayerService(),
  );

  state.init();
  runApp(CrateApp(state: state));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    state.requestNotificationPermission();
  });
}
