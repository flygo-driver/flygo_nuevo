import 'dart:async';
import 'package:flutter/material.dart';

class DeleteCountdownBanner extends StatefulWidget {
  final DateTime base;                // momento base (creado)
  final Duration window;              // ventana (ej. 60s)
  final VoidCallback onDeletePressed; // acción de borrar
  final VoidCallback? onExpired;      // opcional

  const DeleteCountdownBanner({
    super.key,
    required this.base,
    required this.window,
    required this.onDeletePressed,
    this.onExpired,
  });

  @override
  State<DeleteCountdownBanner> createState() => _DeleteCountdownBannerState();
}

class _DeleteCountdownBannerState extends State<DeleteCountdownBanner> {
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final deadline = widget.base.add(widget.window);
    var left = deadline.difference(DateTime.now());
    if (left.isNegative) {
      left = Duration.zero;
      _timer?.cancel();
      widget.onExpired?.call();
    }
    if (mounted) setState(() => _left = left);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _mmss(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (_left == Duration.zero) return const SizedBox.shrink();

    final total = widget.window.inSeconds.toDouble();
    final left  = _left.inSeconds.clamp(0, widget.window.inSeconds).toDouble();
    final progress = 1.0 - (left / total);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Puedes BORRAR este viaje durante:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              const SizedBox(width: 12),
              Text(
                _mmss(_left),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onDeletePressed,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Borrar viaje ahora'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
