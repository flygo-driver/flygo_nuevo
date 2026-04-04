import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

class GestionarUsuariosAdmin extends StatefulWidget {
  const GestionarUsuariosAdmin({super.key});

  @override
  State<GestionarUsuariosAdmin> createState() => _GestionarUsuariosAdminState();
}

class _GestionarUsuariosAdminState extends State<GestionarUsuariosAdmin> {
  final _db = FirebaseFirestore.instance;
  final _qCtrl = TextEditingController();
  final Set<String> _uidsProcesando = <String>{};

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString();
  bool _b(dynamic v) => (v == true);

  Future<void> _setRol(String uid, String rol) async {
    if (_uidsProcesando.contains(uid)) return;
    setState(() => _uidsProcesando.add(uid));
    try {
      await _db.collection('usuarios').doc(uid).set({
        'rol': rol,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Rol actualizado: $rol')),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  Future<void> _toggleBloqueo(String uid, bool bloqueado) async {
    if (_uidsProcesando.contains(uid)) return;
    setState(() => _uidsProcesando.add(uid));
    final ref = _db.collection('usuarios').doc(uid);
    try {
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};
      final bool docsAprobados = (data['docsEstado'] == 'aprobado') ||
          (data['estadoDocumentos'] == 'aprobado') ||
          (data['documentosCompletos'] == true);
      final bool deudaPendiente = data['tienePagoPendiente'] == true;
      final bool puedeOperarAlDesbloquear = docsAprobados && !deudaPendiente;

      await ref.set({
        'bloqueado': bloqueado,
        // Refuerzo operativo: bloqueo administrativo sí impacta disponibilidad real.
        'disponible': bloqueado ? false : puedeOperarAlDesbloquear,
        'puedeRecibirViajes': bloqueado ? false : puedeOperarAlDesbloquear,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bloqueado ? '🚫 Usuario bloqueado' : '✅ Usuario desbloqueado')),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Gestionar Usuarios', style: TextStyle(color: AdminUi.onCard(context))),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _qCtrl,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email o UID...',
                hintStyle: TextStyle(color: AdminUi.secondary(context).withValues(alpha: 0.85)),
                prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 1.4),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('usuarios')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context)));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Error: ${snap.error}', style: TextStyle(color: AdminUi.secondary(context))),
                  );
                }

                final q = _qCtrl.text.trim().toLowerCase();
                final docs = (snap.data?.docs ?? []).where((d) {
                  if (q.isEmpty) return true;
                  final m = d.data();
                  final uid = d.id.toLowerCase();
                  final nombre = _s(m['nombre']).toLowerCase();
                  final email = _s(m['email']).toLowerCase();
                  final telefono = _s(m['telefono']).toLowerCase();
                  return uid.contains(q) || nombre.contains(q) || email.contains(q) || telefono.contains(q);
                }).toList()
                  ..sort((a, b) {
                    final ma = a.data();
                    final mb = b.data();
                    final ta = (ma['actualizadoEn'] as Timestamp?)?.toDate() ??
                        (ma['updatedAt'] as Timestamp?)?.toDate() ??
                        (ma['creadoEn'] as Timestamp?)?.toDate() ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    final tb = (mb['actualizadoEn'] as Timestamp?)?.toDate() ??
                        (mb['updatedAt'] as Timestamp?)?.toDate() ??
                        (mb['creadoEn'] as Timestamp?)?.toDate() ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    return tb.compareTo(ta);
                  });

                if (docs.isEmpty) {
                  return Center(
                    child: Text('Sin resultados', style: TextStyle(color: AdminUi.secondary(context))),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final m = doc.data();
                    final uid = doc.id;

                    final nombre = _s(m['nombre']).trim();
                    final email = _s(m['email']).trim();
                    final rol = _s(m['rol']).trim();
                    final bloqueado = _b(m['bloqueado']);
                    final procesando = _uidsProcesando.contains(uid);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminUi.card(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AdminUi.borderSubtle(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nombre.isNotEmpty ? nombre : uid,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AdminUi.onCard(context),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      email.isNotEmpty ? email : 'UID: $uid',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bloqueado ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: bloqueado ? Colors.redAccent.withValues(alpha: 0.5) : Colors.greenAccent.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  bloqueado ? 'BLOQUEADO' : 'OK',
                                  style: TextStyle(
                                    color: bloqueado ? Colors.redAccent : Colors.greenAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          Text('Rol: ${rol.isEmpty ? "—" : rol}', style: TextStyle(color: AdminUi.secondary(context))),

                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _rolBtn(uid, 'cliente', rol, procesando),
                              _rolBtn(uid, 'taxista', rol, procesando),
                              _rolBtn(uid, 'admin', rol, procesando),
                              _bloqueoBtn(uid, bloqueado, procesando),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rolBtn(String uid, String target, String rolActual, bool deshabilitado) {
    final selected = rolActual == target;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: deshabilitado ? null : () => _setRol(uid, target),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : AdminUi.card(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AdminUi.borderSubtle(context)),
        ),
        child: Text(
          target,
          style: TextStyle(
            color: selected ? cs.onPrimary : AdminUi.onCard(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _bloqueoBtn(String uid, bool bloqueado, bool deshabilitado) {
    return InkWell(
      onTap: deshabilitado ? null : () => _toggleBloqueo(uid, !bloqueado),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AdminUi.card(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: bloqueado ? Colors.redAccent.withValues(alpha: 0.5) : AdminUi.borderSubtle(context)),
        ),
        child: Text(
          bloqueado ? 'Desbloquear' : 'Bloquear',
          style: TextStyle(
            color: bloqueado ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
