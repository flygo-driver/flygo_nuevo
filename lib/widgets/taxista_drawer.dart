// lib/widgets/taxista_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/avatar_circle.dart';
import 'package:flygo_nuevo/servicios/auth_service.dart';

// Pantallas Taxista
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viaje_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/ganancia_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/toggle_disponibilidad.dart';

// NUEVO: Viajes por cupos (consular/tour)
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';

// Pantalla común
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';

// Fallback login
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';

class TaxistaDrawer extends StatelessWidget {
  const TaxistaDrawer({super.key});

  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  static const _subStyle = TextStyle(color: Colors.white54);
  static const _iconColor = Colors.white;

  Future<void> _logout(BuildContext context) async {
    final nav = Navigator.of(context); // capturado antes del await
    if (nav.canPop()) nav.pop(); // cierra drawer si está abierto
    try {
      await AuthService().logout();
    } catch (_) {}
    if (!nav.mounted) return;
    // Intentamos ir al login de taxista; si no existe la ruta, fallback
    try {
      nav.pushNamedAndRemoveUntil('/login_taxista', (_) => false);
    } catch (_) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SeleccionUsuario()),
        (_) => false,
      );
    }
  }

  void _go(BuildContext context, Widget page, {bool replace = false}) {
    Navigator.pop(context); // cierra drawer
    final route = MaterialPageRoute(builder: (_) => page);
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  // Header con nombre/foto en tiempo real (correo oculto)
  Widget _header() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const UserAccountsDrawerHeader(
        decoration: BoxDecoration(color: Colors.black),
        accountName: Text(
          'Taxista',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        accountEmail: SizedBox.shrink(),
        currentAccountPicture: CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(Icons.person, color: Colors.green),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
      builder: (_, s) {
        final data = s.data?.data() ?? {};
        final nombre = (data['nombre'] ?? '').toString().trim();
        final foto = (data['fotoUrl'] ?? '').toString().trim();

        return UserAccountsDrawerHeader(
          decoration: const BoxDecoration(color: Colors.black),
          accountName: Text(
            nombre.isEmpty ? 'Taxista' : nombre,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          accountEmail: const SizedBox.shrink(), // correo oculto
          currentAccountPicture: AvatarCircle(
            imageUrl: foto,
            name: nombre.isEmpty ? 'Taxista' : nombre,
            size: 64,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(),

            // ==== Operación diaria ====
            ListTile(
              leading: const Icon(Icons.list_alt_outlined, color: _iconColor),
              title: const Text('Viajes disponibles', style: _titleStyle),
              subtitle: const Text('Llegan en tiempo real + timbre', style: _subStyle),
              onTap: () => _go(context, const ViajeDisponible(), replace: true),
            ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined, color: _iconColor),
              title: const Text('Viaje en curso', style: _titleStyle),
              subtitle: const Text('Mapa y destino del cliente', style: _subStyle),
              onTap: () => _go(context, const ViajeEnCursoTaxista()),
            ),
            ListTile(
              leading: const Icon(Icons.toggle_on, color: _iconColor),
              title: const Text('Disponibilidad', style: _titleStyle),
              subtitle: const Text('Recibir viajes: ON / OFF', style: _subStyle),
              onTap: () => _go(context, const ToggleDisponibilidad()),
            ),

            const Divider(color: Colors.white24),

            // ==== Viajes por cupos (consular / tour) ====
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Text('Viajes por cupos', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.people_alt_outlined, color: _iconColor),
              title: const Text('Mis viajes por cupos', style: _titleStyle),
              subtitle: const Text('Ver ocupación, pagos y reservas', style: _subStyle),
              onTap: () => _go(context, const PoolsTaxistaLista()),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: _iconColor),
              title: const Text('Crear viaje por cupos', style: _titleStyle),
              subtitle: const Text('Consular o Tour, ida o ida/vuelta', style: _subStyle),
              onTap: () => _go(context, const PoolsTaxistaCrear()),
            ),

            const Divider(color: Colors.white24),

            // ==== Finanzas / Docs / Soporte ====
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined, color: _iconColor),
              title: const Text('Billetera', style: _titleStyle),
              subtitle: const Text('Saldo 80 %, comisión 20 %', style: _subStyle),
              onTap: () => _go(context, const BilleteraTaxista()),
            ),
            ListTile(
              leading: const Icon(Icons.history, color: _iconColor),
              title: const Text('Historial de viajes', style: _titleStyle),
              onTap: () => _go(context, const HistorialViajesTaxista()),
            ),
            ListTile(
              leading: const Icon(Icons.monetization_on_outlined, color: _iconColor),
              title: const Text('Ganancias', style: _titleStyle),
              subtitle: const Text('Totales y cálculo 80/20', style: _subStyle),
              onTap: () => _go(context, const GananciaTaxista()),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: _iconColor),
              title: const Text('Documentos', style: _titleStyle),
              subtitle: const Text('Licencia, cédula, seguro', style: _subStyle),
              onTap: () => _go(context, const DocumentosTaxista()),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent, color: _iconColor),
              title: const Text('Soporte', style: _titleStyle),
              onTap: () => _go(context, const Soporte()),
            ),

            const Divider(color: Colors.white24),

            // ==== Cuenta ====
            ListTile(
              leading: const Icon(Icons.person, color: _iconColor),
              title: const Text('Configuración de perfil', style: _titleStyle),
              subtitle: const Text('Foto y nombre', style: _subStyle),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/configuracion_perfil');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _logout(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
