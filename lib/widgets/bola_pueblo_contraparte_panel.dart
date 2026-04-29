import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/bola_pueblo_chat_sheet.dart';

/// Foto, nombre, contacto y chat Bola. Layout apilado para que no haya overflow en pantallas angostas.
class BolaPuebloContrapartePanel extends StatelessWidget {
  const BolaPuebloContrapartePanel({
    super.key,
    required this.bolaId,
    required this.counterpartyUid,
    required this.sectionTitle,

    /// `true` = sos chofer y ves datos del pasajero; `false` = sos cliente y ves al conductor.
    required this.vistaChofer,
  });

  final String bolaId;
  final String counterpartyUid;
  final String sectionTitle;
  final bool vistaChofer;

  static const Color _accent = Color(0xFF12C97A);
  static const Color _waGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    if (counterpartyUid.trim().isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(counterpartyUid)
          .snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? const <String, dynamic>{};
        final nombre = (m['nombre'] ?? 'Usuario').toString().trim();
        final tel = (m['telefono'] ?? '').toString().trim();
        final placa = (m['placa'] ?? '').toString().trim();
        final foto = (m['fotoUrl'] ?? '').toString().trim();
        final rol = (m['rol'] ?? '').toString().toLowerCase();
        final bool esPerfilTaxista = rol == 'taxista' || rol == 'driver';

        Future<void> llamar() async {
          final digits = tel.replaceAll(RegExp(r'\s'), '');
          if (digits.isEmpty) return;
          final uri = Uri.parse('tel:${Uri.encodeComponent(digits)}');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        }

        String? waDigits(String raw) {
          var d = raw.replaceAll(RegExp(r'\D'), '');
          if (d.isEmpty) return null;
          if (d.startsWith('00')) d = d.substring(2);
          if (d.length == 10 && !d.startsWith('1')) d = '1$d';
          if (d.length >= 10) return d;
          return null;
        }

        Future<void> abrirWhatsApp() async {
          final w = waDigits(tel);
          if (w == null) return;
          final uri = Uri.parse(
            'https://wa.me/$w?text=${Uri.encodeComponent('Hola, coordinamos el viaje Bola Ahorro.')}',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }

        void abrirChat() {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: cs.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            builder: (ctx) => Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: BolaPuebloChatSheet(
                bolaId: bolaId,
                otroNombre: nombre.isNotEmpty ? nombre : 'Chat',
              ),
            ),
          );
        }

        final borderColor = cs.outline.withValues(alpha: 0.28);
        final hintBg = vistaChofer
            ? _accent.withValues(
                alpha: cs.brightness == Brightness.dark ? 0.14 : 0.10)
            : cs.primaryContainer.withValues(
                alpha: cs.brightness == Brightness.dark ? 0.35 : 0.55);
        final hintFg = vistaChofer
            ? (cs.brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0D3D2A))
            : cs.onPrimaryContainer;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sectionTitle.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.05,
                  color: cs.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: hintBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: vistaChofer
                        ? _accent.withValues(alpha: 0.35)
                        : cs.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      vistaChofer
                          ? Icons.verified_user_outlined
                          : Icons.key_rounded,
                      size: 22,
                      color: vistaChofer ? _accent : cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vistaChofer
                            ? 'Orden: 1) Ir a buscar al pasajero · 2) Tocá «Cliente a bordo» · 3) Pedí el código de verificación que él ve en su app y tocá «Código del cliente e iniciar». Sin ese código no arranca el viaje.'
                            : 'Tu código está en esta tarjeta (abajo). Dictárselo al conductor solo cuando subas al auto y te lo pida para el paso 3.',
                        style: TextStyle(
                          color: hintFg,
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarCircle(
                    imageUrl: foto.isNotEmpty ? foto : null,
                    name: nombre,
                    size: 56,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre.isNotEmpty ? nombre : 'Perfil',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        if (esPerfilTaxista && placa.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.directions_car,
                                  size: 16, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Placa ${placa.toUpperCase()}',
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (tel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              tel,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Contacto',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: Icons.call_outlined,
                label: 'Llamar por teléfono',
                subtitle: tel.isEmpty ? 'Sin número en perfil' : null,
                enabled: tel.isNotEmpty,
                onTap: tel.isEmpty
                    ? null
                    : () {
                        llamar();
                      },
                outlined: true,
                foreground: cs.onSurface,
                borderColor: borderColor,
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: Icons.message_outlined,
                label: 'WhatsApp',
                subtitle: waDigits(tel) == null && tel.isNotEmpty
                    ? 'Número no válido para WhatsApp'
                    : (tel.isEmpty ? 'Sin número en perfil' : 'Mensaje rápido'),
                enabled: waDigits(tel) != null,
                onTap: waDigits(tel) == null
                    ? null
                    : () {
                        abrirWhatsApp();
                      },
                outlined: true,
                foreground: _waGreen,
                borderColor: _waGreen.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: Icons.forum_outlined,
                label: 'Chat en la app',
                subtitle: 'Mensajes dentro de RAI',
                enabled: true,
                onTap: abrirChat,
                outlined: false,
                filledColor: _accent,
                foreground: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.enabled,
    required this.onTap,
    required this.outlined,
    required this.foreground,
    this.borderColor,
    this.filledColor,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final bool outlined;
  final Color foreground;
  final Color? borderColor;
  final Color? filledColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 22,
              color: enabled ? foreground : foreground.withValues(alpha: 0.38)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.38),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      color: outlined
                          ? foreground.withValues(alpha: enabled ? 0.65 : 0.38)
                          : foreground.withValues(alpha: enabled ? 0.88 : 0.45),
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: foreground.withValues(alpha: enabled ? 0.45 : 0.22),
            size: 22,
          ),
        ],
      ),
    );

    if (outlined) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: enabled
                    ? (borderColor ?? foreground.withValues(alpha: 0.35))
                    : foreground.withValues(alpha: 0.15),
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    return Material(
      color: enabled
          ? (filledColor ?? foreground)
          : filledColor?.withValues(alpha: 0.35),
      borderRadius: radius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: child,
      ),
    );
  }
}
