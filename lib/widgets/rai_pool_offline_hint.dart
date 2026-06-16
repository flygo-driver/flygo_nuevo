import 'package:flutter/material.dart';

import '../servicios/rai_connectivity_service.dart';

/// Aviso contextual en el pool del taxista cuando no hay internet.
class RaiPoolOfflineHint extends StatefulWidget {
  const RaiPoolOfflineHint({super.key});

  @override
  State<RaiPoolOfflineHint> createState() => _RaiPoolOfflineHintState();
}

class _RaiPoolOfflineHintState extends State<RaiPoolOfflineHint> {
  @override
  void initState() {
    super.initState();
    RaiConnectivityService.instance.ensureStarted();
    RaiConnectivityService.instance.offline.addListener(_onOfflineChanged);
  }

  @override
  void dispose() {
    RaiConnectivityService.instance.offline.removeListener(_onOfflineChanged);
    super.dispose();
  }

  void _onOfflineChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!RaiConnectivityService.instance.isOffline) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.sync_disabled_rounded, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sin internet no llegarán viajes nuevos al pool. '
                'Cuando vuelva la conexión, el listado se actualiza solo.',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
