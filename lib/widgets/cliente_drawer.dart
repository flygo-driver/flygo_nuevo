// lib/widgets/cliente_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/avatar_circle.dart';
// ⬇️ Usa el logout centralizado
import 'package:flygo_nuevo/servicios/logout.dart';

class ClienteDrawer extends StatelessWidget {
  const ClienteDrawer({super.key});

  static const TextStyle _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle _subtitleStyle = TextStyle(color: Colors.white54);
  static const Color _iconColor = Colors.white;

  static const TextStyle _headerTitle = TextStyle(
    color: Colors.greenAccent,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  Future<void> _logout(BuildContext context) async {
    // Cierra el Drawer primero
    Navigator.pop(context);
    // Usa tu servicio unificado (firma, Google y navega a /auth_check)
    await cerrarSesion(context);
  }

  void _goNamed(BuildContext context, String route, {bool replace = false}) {
    Navigator.pop(context);
    if (replace) {
      Navigator.pushReplacementNamed(context, route);
    } else {
      Navigator.pushNamed(context, route);
    }
  }

  Widget _header({required String nombre, String? fotoUrl}) {
    return UserAccountsDrawerHeader(
      decoration: const BoxDecoration(color: Colors.black),
      accountName: Text(nombre, style: _headerTitle),
      accountEmail: const SizedBox.shrink(),
      currentAccountPicture: AvatarCircle(
        imageUrl: (fotoUrl ?? '').trim(),
        name: nombre.isEmpty ? 'Usuario' : nombre,
        size: 64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    return Drawer(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            if (uid == null)
              _header(nombre: 'Cliente')
            else
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final nombre = (() {
                    final n = (data?['nombre'] as String?)?.trim();
                    if (n != null && n.isNotEmpty) return n;
                    final dn = user?.displayName?.trim();
                    return (dn != null && dn.isNotEmpty) ? dn : 'Cliente';
                  })();
                  final foto = (() {
                    final f = (data?['fotoUrl'] as String?)?.trim();
                    if (f != null && f.isNotEmpty) return f;
                    final fu = user?.photoURL?.trim();
                    return (fu != null && fu.isNotEmpty) ? fu : null;
                  })();
                  return _header(nombre: nombre, fotoUrl: foto);
                },
              ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.rocket_launch_outlined, color: _iconColor),
                    title: const Text('Solicitar viaje ahora', style: _titleStyle),
                    subtitle: const Text('Usar mi ubicación actual', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/solicitar_viaje_ahora', replace: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined, color: _iconColor),
                    title: const Text('Programar viaje', style: _titleStyle),
                    subtitle: const Text('Elegir fecha u origen manual', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/programar_viaje', replace: true),
                  ),

                  const Divider(color: Colors.white24, height: 28),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                    child: Text('Servicios', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.alt_route, color: _iconColor),
                    title: const Text('Múltiples paradas', style: _titleStyle),
                    subtitle: const Text('Deja/pasa por varias direcciones', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/programar_viaje_multi'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance, color: _iconColor),
                    title: const Text('Servicios consulares', style: _titleStyle),
                    subtitle: const Text('Traslados programados por pueblos → ciudad', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/servicios_consulares'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.park, color: _iconColor),
                    title: const Text('Tours / Giras turísticas', style: _titleStyle),
                    subtitle: const Text('Organiza recorridos y excursiones', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/tours_turisticos'),
                  ),

                  if (uid != null)
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('viajes')
                          .where('uidCliente', isEqualTo: uid)
                          .where('estado', whereIn: [
                            'pendiente',
                            'asignado',
                            'aceptado',
                            'en_curso',
                            'enCurso',
                            'enCaminoPickup',
                            'en_camino_pickup',
                            'a_bordo',
                            'aBordo',
                          ])
                          .limit(1)
                          .snapshots(),
                      builder: (context, s) {
                        final activo = (s.data?.docs.isNotEmpty ?? false);
                        return ListTile(
                          leading: const Icon(Icons.directions_car, color: _iconColor),
                          title: const Text('Mi viaje en curso', style: _titleStyle),
                          subtitle: Text(
                            activo ? 'Tienes un viaje activo' : 'Estado y detalles en tiempo real',
                            style: _subtitleStyle,
                          ),
                          trailing: activo
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0x7FFFEB3B), // ~50% alpha
                                    ),
                                  ),
                                  child: const Text(
                                    'Activo',
                                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700),
                                  ),
                                )
                              : null,
                          onTap: () => _goNamed(context, '/viaje_en_curso_cliente'),
                        );
                      },
                    ),

                  ListTile(
                    leading: const Icon(Icons.history, color: _iconColor),
                    title: const Text('Historial de viajes', style: _titleStyle),
                    subtitle: const Text('Completados y pendientes', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/historial_viajes_cliente'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined, color: _iconColor),
                    title: const Text('Pagos', style: _titleStyle),
                    subtitle: const Text('Métodos de pago e historial', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/metodos_pago'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.support_agent, color: _iconColor),
                    title: const Text('Soporte', style: _titleStyle),
                    subtitle: const Text('Ayuda y contacto', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/soporte'),
                  ),

                  const Divider(color: Colors.white24, height: 28),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                    child: Text('Cuenta', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person, color: _iconColor),
                    title: const Text('Configuración de perfil', style: _titleStyle),
                    subtitle: const Text('Foto y nombre', style: _subtitleStyle),
                    onTap: () => _goNamed(context, '/configuracion_perfil'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _logout(context),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
