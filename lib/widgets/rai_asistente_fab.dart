import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/widgets/rai_asistente_launcher.dart';

/// Botón flotante del asistente RAI: arrastrable y recuerda su posición.
class RaiAsistenteFab extends StatefulWidget {
  const RaiAsistenteFab({super.key});

  @override
  State<RaiAsistenteFab> createState() => _RaiAsistenteFabState();
}

class _RaiAsistenteFabState extends State<RaiAsistenteFab> {
  static const String _kPrefX = 'cliente_rai_fab_x';
  static const String _kPrefY = 'cliente_rai_fab_y';
  static const double _fabW = 92;
  static const double _fabH = 48;
  static const double _tapDragThreshold = 14;

  double? _x;
  double? _y;
  double _panDistance = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPosition());
  }

  Future<void> _loadPosition() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final double? x = prefs.getDouble(_kPrefX);
      final double? y = prefs.getDouble(_kPrefY);
      if (!mounted) return;
      if (x != null && y != null) {
        setState(() {
          _x = x;
          _y = y;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePosition(double x, double y) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kPrefX, x);
      await prefs.setDouble(_kPrefY, y);
    } catch (_) {}
  }

  double _bottomBarHeight(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom;
    return kBottomNavigationBarHeight + bottom + 4;
  }

  Offset _defaultPosition(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final double bottomBar = _bottomBarHeight(context);
    return Offset(
      screen.width - _fabW - 16,
      screen.height - bottomBar - _fabH - 20,
    );
  }

  Offset _clamp(BuildContext context, Offset pos) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final double bottomBar = _bottomBarHeight(context);
    return Offset(
      pos.dx.clamp(8.0, screen.width - _fabW - 8),
      pos.dy.clamp(padding.top + 8, screen.height - bottomBar - _fabH - 8),
    );
  }

  Offset _currentPosition(BuildContext context) {
    if (_x != null && _y != null) {
      return _clamp(context, Offset(_x!, _y!));
    }
    return _clamp(context, _defaultPosition(context));
  }

  @override
  Widget build(BuildContext context) {
    final Offset pos = _currentPosition(context);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Semantics(
        button: true,
        label: 'Asistente RAI. Arrastra para mover, toca para abrir.',
        child: GestureDetector(
          onPanStart: (_) => _panDistance = 0,
          onPanUpdate: (DragUpdateDetails details) {
            _panDistance += details.delta.distance;
            final Offset current = Offset(_x ?? pos.dx, _y ?? pos.dy);
            final Offset next =
                _clamp(context, current + details.delta);
            setState(() {
              _x = next.dx;
              _y = next.dy;
            });
          },
          onPanEnd: (_) {
            final double x = _x ?? pos.dx;
            final double y = _y ?? pos.dy;
            unawaited(_savePosition(x, y));
            if (_panDistance < _tapDragThreshold) {
              RaiAsistenteLauncher.abrirAsistente(context);
            }
          },
          child: Material(
            elevation: 6,
            shadowColor: cs.primary.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(28),
            color: cs.primary,
            child: SizedBox(
              height: _fabH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: cs.onPrimary, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      'RAI',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
