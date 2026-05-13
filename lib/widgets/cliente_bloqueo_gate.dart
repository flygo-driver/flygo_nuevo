// lib/widgets/cliente_bloqueo_gate.dart
//
// Gate de SOLO LECTURA que verifica `usuarios/{uid}.bloqueado` antes de
// permitir al cliente acceder a flujos sensibles (programar / pedir un viaje).
//
// Reglas estrictas:
// - NO escribe nada en Firestore (no toca el campo `bloqueado`).
// - NO modifica navegación de la app: si no está bloqueado, retorna [child]
//   tal cual.
// - Si NO hay usuario autenticado, retorna [child] (que la lógica de auth
//   ya existente maneje ese caso, no es responsabilidad del gate).
// - Mientras el snapshot inicial está cargando, retorna [child] para evitar
//   parpadeos en la UI; cuando lleguen los datos reactivos, se renderizará
//   la pantalla de bloqueo si corresponde.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ClienteBloqueoGate extends StatelessWidget {
  const ClienteBloqueoGate({super.key, required this.child});

  /// Contenido normal de la pantalla cliente. Se muestra cuando el usuario
  /// no está bloqueado o no se pudo leer el estado.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Sin sesión: dejamos que el flujo normal de auth siga su curso.
      return child;
    }

    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('usuarios').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        // Mientras no hay datos aún (carga inicial o error transitorio):
        // mostrar contenido normal para no romper el flujo. El stream
        // se actualizará automáticamente cuando llegue el doc.
        if (!snap.hasData) return child;

        final Map<String, dynamic>? data = snap.data?.data();
        final bool bloqueado = (data?['bloqueado'] == true);

        if (!bloqueado) return child;

        final String motivo =
            (data?['bloqueoMotivo'] ?? '').toString().trim();
        return _PantallaCuentaBloqueada(motivo: motivo.isEmpty ? null : motivo);
      },
    );
  }
}

class _PantallaCuentaBloqueada extends StatelessWidget {
  const _PantallaCuentaBloqueada({this.motivo});

  final String? motivo;

  static const String _telefonoSoporte = '+18099000000';
  static const String _whatsappSoporte = '8099000000';

  Future<void> _abrirWhatsApp() async {
    final Uri uri = Uri.parse(
      'https://wa.me/$_whatsappSoporte?text=${Uri.encodeComponent('Hola, mi cuenta RAI aparece bloqueada. ¿Pueden ayudarme?')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _llamarSoporte() async {
    final Uri uri = Uri(scheme: 'tel', path: _telefonoSoporte);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg = Theme.of(context).scaffoldBackgroundColor;
    final Color cardBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;
    final Color borderCol = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE5E7EB);
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF111827);
    final Color textMuted = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF4B5563);
    final Color iconBg = isDark
        ? const Color(0xFF7F1D1D)
        : const Color(0xFFFEE2E2);
    final Color iconColor = isDark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFB91C1C);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderCol),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.32 : 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 36,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Tu cuenta está bloqueada',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Por seguridad, no puedes solicitar viajes en este '
                      'momento. Contacta a soporte para más información.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    if (motivo != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.error.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Motivo: $motivo',
                                style: TextStyle(
                                  color: cs.error,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _abrirWhatsApp,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Contactar soporte por WhatsApp'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _llamarSoporte,
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Llamar a soporte'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: borderCol),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Si crees que es un error, mantén la app abierta: '
                      'cuando soporte desbloquee tu cuenta, esta pantalla '
                      'desaparecerá automáticamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        height: 1.4,
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
