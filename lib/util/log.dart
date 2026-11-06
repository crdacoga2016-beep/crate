import 'dart:io';

import 'package:flutter/foundation.dart';

final File _logFile =
    File('${Directory.systemTemp.path}${Platform.pathSeparator}crate.log');

void logLine(String message) {
  final line = '${DateTime.now().toIso8601String()}  $message';
  debugPrint(line);
  try {
    _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}
