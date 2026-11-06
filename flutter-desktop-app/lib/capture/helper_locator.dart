/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:io';

const captureHelperName = 'netscope-capture.exe';

/// Returns the helper next to the running app executable, when present.
String? findCaptureHelper() {
  final directory = File(Platform.resolvedExecutable).parent.path;
  final candidate = '$directory${Platform.pathSeparator}$captureHelperName';
  return File(candidate).existsSync() ? candidate : null;
}
