import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/taxista/organizador_giras_configuracion_page.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/shell/organizador_giras_shell.dart';
import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/widgets/cuenta_legal_tiles.dart';

/// Perfil del organizador de giras (sin documentos de chofer).
class OrganizadorGirasPerfilTab extends StatelessWidget {
  const OrganizadorGirasPerfilTab({super.key});

  Future<void> _abrirConfiguracion(BuildContext context) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const OrganizadorGirasConfiguracionPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return OrganizadorGirasPerfilStream(
      builder: (context, data) {
        final nombre = (data['nombre'] ?? '').toString().trim();
        final agencia = (data['agenciaNombre'] ?? '').toString().trim();
        final telefono = (data['telefono'] ?? '').toString().trim();
        final whatsapp = (data['whatsapp'] ?? telefono).toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final cedula =
            (data['cedula'] ?? data['ciTaxista'] ?? '').toString().trim();
        final banco = (data['bancoNombre'] ?? '').toString().trim();
        final cuenta = (data['bancoCuenta'] ?? '').toString().trim();
        final titular = (data['bancoTitular'] ?? '').toString().trim();
        final fotoUrl = (data['fotoUrl'] ?? '').toString().trim();
        final girasCreadas =
            (data['girasCreadasUltimoMes'] as num?)?.toInt() ?? 0;

        final headerGradA = isDark
            ? const Color(0xFF1A2E28)
            : cs.primaryContainer.withValues(alpha: 0.55);
        final headerGradB = isDark
            ? const Color(0xFF0F1419)
            : cs.surface;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mi perfil'),
            centerTitle: true,
            elevation: isDark ? 0 : 0.5,
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + bottomInset),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [headerGradA, headerGradB],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AvatarCircle(
                            imageUrl: fotoUrl.isEmpty ? null : fotoUrl,
                            name: nombre.isNotEmpty ? nombre : agencia,
                            size: 88,
                            onTap: () => _abrirConfiguracion(context),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Material(
                              color: isDark ? Colors.white : cs.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () => _abrirConfiguracion(context),
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 18,
                                    color: isDark
                                        ? const Color(0xFF1B5E20)
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        agencia.isNotEmpty ? agencia : 'Organizador de giras',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: isDark ? Colors.white : cs.onSurface,
                        ),
                      ),
                      if (nombre.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nombre,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          Chip(
                            avatar: Icon(
                              Icons.tour_outlined,
                              size: 18,
                              color: isDark ? Colors.greenAccent : cs.primary,
                            ),
                            label: const Text('Organizador de giras'),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (girasCreadas > 0)
                            Chip(
                              label: Text('$girasCreadas giras este mes'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Mi cuenta'),
                _infoCard(
                  context,
                  children: [
                    _datoTile(
                      context,
                      icon: Icons.badge_outlined,
                      label: 'Cédula / pasaporte',
                      value: cedula,
                    ),
                    if (telefono.isNotEmpty)
                      _datoTile(
                        context,
                        icon: Icons.phone_outlined,
                        label: 'Teléfono',
                        value: telefono,
                      ),
                    if (whatsapp.isNotEmpty && whatsapp != telefono)
                      _datoTile(
                        context,
                        icon: Icons.chat_outlined,
                        label: 'WhatsApp',
                        value: whatsapp,
                      ),
                    if (email.isNotEmpty)
                      _datoTile(
                        context,
                        icon: Icons.email_outlined,
                        label: 'Correo',
                        value: email,
                      ),
                    if (banco.isNotEmpty && cuenta.isNotEmpty)
                      _datoTile(
                        context,
                        icon: Icons.account_balance_outlined,
                        label: 'Cuenta bancaria',
                        value: titular.isNotEmpty
                            ? '$banco · $cuenta\n$titular'
                            : '$banco · $cuenta',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionTitle(context, 'Ajustes'),
                _actionCard(
                  context,
                  children: [
                    ListTile(
                      leading: Icon(Icons.settings_outlined, color: cs.primary),
                      title: const Text(
                        'Configurar perfil',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Foto, agencia, WhatsApp y cuenta bancaria',
                      ),
                      trailing: Icon(Icons.chevron_right, color: cs.outline),
                      onTap: () => _abrirConfiguracion(context),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                    ListTile(
                      leading: Icon(Icons.support_agent_outlined, color: cs.primary),
                      title: const Text('Soporte'),
                      trailing: Icon(Icons.chevron_right, color: cs.outline),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const Soporte(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _infoCard(
                  context,
                  children: [
                    ListTile(
                      leading: Icon(Icons.info_outline, color: cs.tertiary),
                      title: const Text(
                        'Cuenta de organizador',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Creás y gestionás giras por cupos. RAI retiene el 10% '
                        'de asientos vendidos y te liquida el neto a tu banco. '
                        'No operás viajes como chofer.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const CuentaLegalTiles(),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => cerrarSesion(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'Cerrar sesión',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _actionCard(BuildContext context, {required List<Widget> children}) {
    return _infoCard(context, children: children);
  }

  Widget _datoTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary, size: 22),
      title: Text(
        label,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
      ),
    );
  }
}
