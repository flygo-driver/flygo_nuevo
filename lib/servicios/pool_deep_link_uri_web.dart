// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// URL actual en Flutter Web (query `?id=` o path /pool).
Uri? poolDeepLinkUriFromPlatform() {
  try {
    return Uri.parse(html.window.location.href);
  } catch (_) {
    return null;
  }
}
