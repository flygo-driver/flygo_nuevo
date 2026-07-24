import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ruta destino tras login (web corporativo, etc.).
abstract final class PostAuthNavigation {
  PostAuthNavigation._();

  static const String _routeKey = 'rai_post_auth_route';

  static Future<void> saveRoute(String route) async {
    final r = route.trim();
    if (r.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeKey, r);
  }

  static Future<String?> consumeRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString(_routeKey);
    if (route != null) {
      await prefs.remove(_routeKey);
    }
    return route;
  }

  static void go(BuildContext context, {String? route}) {
    if (!context.mounted) return;
    final dest = (route ?? '').trim();
    if (dest == '/corporativo') {
      Navigator.of(context).pushNamedAndRemoveUntil(dest, (r) => false);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  static Future<void> goAfterStoredRoute(BuildContext context) async {
    final route = await consumeRoute();
    if (!context.mounted) return;
    go(context, route: route);
  }
}
