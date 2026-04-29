import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';

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

  String _normalizarRolUi(String raw) {
    final r = raw.trim().toLowerCase();
    if (r == 'administrador') return Roles.admin;
    if (r == 'driver') return Roles.taxista;
    if (r == 'user') return Roles.cliente;
    if (r == Roles.admin || r == Roles.taxista || r == Roles.cliente) return r;
    return r;
  }

  /// Escribe rol en `usuarios` y `roles`. Prioridad: que `usuarios` quede bien (es lo que usa la app).
  Future<void> _setRol(String uid, String rol) async {
    if (_uidsProcesando.contains(uid)) return;
    final canon = rol.trim().toLowerCase();
    setState(() => _uidsProcesando.add(uid));
    try {
      final payload = <String, dynamic>{
        'rol': canon,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      final uRef = _db.collection('usuarios').doc(uid);
      final rRef = _db.collection('roles').doc(uid);

      // 1) Intento atómico (producción: ambos docs coherentes si las reglas lo permiten).
      try {
        final batch = _db.batch();
        batch.set(uRef, payload, SetOptions(merge: true));
        batch.set(rRef, payload, SetOptions(merge: true));
        await batch.commit();
      } on FirebaseException catch (e, st) {
        // 2) Batch falla entero si una regla o la red falla: asegurar al menos `usuarios` (fuente principal).
        debugPrint(
            'GestionarUsuarios: batch rol falló (${e.code}), reintento secuencial: $e\n$st');
        await uRef.set(payload, SetOptions(merge: true));
        try {
          await rRef.set(payload, SetOptions(merge: true));
        } catch (e2, st2) {
          debugPrint('GestionarUsuarios: sync roles/$uid omitida: $e2\n$st2');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Rol actualizado: $canon')),
      );
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'Sin permiso para cambiar el rol. Revisa reglas Firestore (admin en usuarios/roles).'
                  : 'No se pudo cambiar el rol: ${e.code}',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('GestionarUsuarios _setRol: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar el rol: $e')),
        );
      }
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
      // `tienePagoPendiente` en Firestore = solo comisión efectivo ≥ tope (no incluye pago semanal).
      final bool bloqueoOperativoComision = data['tienePagoPendiente'] == true;
      final bool puedeOperarAlDesbloquear =
          docsAprobados && !bloqueoOperativoComision;

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
        SnackBar(
            content: Text(
                bloqueado ? '🚫 Usuario bloqueado' : '✅ Usuario desbloqueado')),
      );
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'Sin permiso para bloquear/desbloquear (reglas Firestore).'
                  : 'No se pudo actualizar: ${e.code}',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('GestionarUsuarios _toggleBloqueo: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  /// Tras verificar transferencia por comisión en efectivo (recarga): baja deuda en billetera y desbloquea.
  Future<void> _dialogLiquidarComisionEfectivo(
      String uid, String nombreMostrar) async {
    if (_uidsProcesando.contains(uid)) return;
    double pendiente = 0;
    try {
      final b = await _db.collection('billeteras_taxista').doc(uid).get();
      pendiente = PagosTaxistaRepo.comisionPendienteDesdeBilletera(b.data());
    } catch (e, st) {
      debugPrint('GestionarUsuarios leer billetera: $e\n$st');
    }
    if (!mounted) return;
    if (pendiente < 1e-6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Sin comisión en efectivo pendiente en billetera (o doc sin datos).'),
        ),
      );
      return;
    }

    final ctrl = TextEditingController(text: pendiente.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.card(context),
        title: Text(
          'Liquidar comisión efectivo',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                nombreMostrar,
                style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Pendiente en billetera: RD\$${pendiente.toStringAsFixed(2)}',
                style: TextStyle(color: AdminUi.onCard(context)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AdminUi.onCard(context)),
                decoration: InputDecoration(
                  labelText: 'Monto liquidado (RD\$)',
                  labelStyle: TextStyle(color: AdminUi.secondary(context)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: refCtrl,
                style: TextStyle(color: AdminUi.onCard(context)),
                decoration: InputDecoration(
                  labelText: 'Ref. banco / nota (opcional)',
                  labelStyle: TextStyle(color: AdminUi.secondary(context)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: TextStyle(color: AdminUi.secondary(context))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar pago'),
          ),
        ],
      ),
    );
    final montoStr = ctrl.text.trim().replaceAll(',', '.');
    final refStr = refCtrl.text.trim();
    ctrl.dispose();
    refCtrl.dispose();

    if (ok != true || !mounted) return;
    final m = double.tryParse(montoStr) ?? 0;
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto inválido.')),
      );
      return;
    }

    setState(() => _uidsProcesando.add(uid));
    try {
      await PagosTaxistaRepo.adminLiquidarComisionEfectivoVerificado(
        uidTaxista: uid,
        montoLiquidarRd: m,
        referenciaBanco: refStr.isEmpty ? null : refStr,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Liquidación registrada. Se actualizó bloqueo y pools del taxista.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  String _fmtFecha(dynamic v) {
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    if (dt == null) return 'sin fecha';
    final d = dt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${d.year} $hh:$mi';
  }

  String _rd(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    return 'RD\$${n.toStringAsFixed(2)}';
  }

  Future<void> _dialogMovimientosPrepago(
      String uid, String nombreMostrar) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.8,
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Movimientos prepago\n$nombreMostrar',
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: AdminUi.onCard(context)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db
                      .collection('billeteras_taxista')
                      .doc(uid)
                      .collection('movimientos_prepago')
                      .orderBy('createdAt', descending: true)
                      .limit(120)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                            color: AdminUi.progressAccent(context)),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'No se pudo cargar movimientos: ${snap.error}',
                          style: TextStyle(color: AdminUi.secondary(context)),
                        ),
                      );
                    }
                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'Sin movimientos prepago todavía.',
                          style: TextStyle(color: AdminUi.secondary(context)),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final m = docs[i].data();
                        final tipo = _s(m['tipo']).trim();
                        final fuente = _s(m['fuente']).trim();
                        final fecha = _fmtFecha(m['createdAt']);
                        final com = _rd(m['comisionTotalRd']);
                        final rec = _rd(m['montoAcreditadoRd']);
                        final p0 = _rd(m['comisionPendienteAntes']);
                        final p1 = _rd(m['comisionPendienteDespues']);
                        final s0 = _rd(m['saldoPrepagoAntes']);
                        final s1 = _rd(m['saldoPrepagoDespues']);
                        final viajeId = _s(m['viajeId']).trim();
                        final recargaId = _s(m['recargaId']).trim();
                        final bolaId = _s(m['bolaId']).trim();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AdminUi.scaffold(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AdminUi.borderSubtle(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tipo.isEmpty ? 'movimiento' : tipo,
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$fecha • ${fuente.isEmpty ? 'sin_fuente' : fuente}',
                                style: TextStyle(
                                    color: AdminUi.muted(context),
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              if (m['comisionTotalRd'] != null)
                                Text('Comisión: $com',
                                    style: TextStyle(
                                        color: AdminUi.onCard(context))),
                              if (m['montoAcreditadoRd'] != null)
                                Text('Recarga: $rec',
                                    style: const TextStyle(
                                        color: Colors.greenAccent)),
                              Text('Pendiente: $p0 -> $p1',
                                  style: TextStyle(
                                      color: AdminUi.onCard(context),
                                      fontSize: 12.5)),
                              Text('Prepago: $s0 -> $s1',
                                  style: TextStyle(
                                      color: AdminUi.onCard(context),
                                      fontSize: 12.5)),
                              if (viajeId.isNotEmpty)
                                Text('Viaje: $viajeId',
                                    style: TextStyle(
                                        color: AdminUi.muted(context),
                                        fontSize: 12)),
                              if (recargaId.isNotEmpty)
                                Text('RecargaID: $recargaId',
                                    style: TextStyle(
                                        color: AdminUi.muted(context),
                                        fontSize: 12)),
                              if (bolaId.isNotEmpty)
                                Text('BolaID: $bolaId',
                                    style: TextStyle(
                                        color: AdminUi.muted(context),
                                        fontSize: 12)),
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
      },
    );
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
        title: Text('Gestionar Usuarios',
            style: TextStyle(color: AdminUi.onCard(context))),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _qCtrl,
                  style: TextStyle(color: AdminUi.onCard(context)),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, email o UID...',
                    hintStyle: TextStyle(
                        color:
                            AdminUi.secondary(context).withValues(alpha: 0.85)),
                    prefixIcon:
                        Icon(Icons.search, color: AdminUi.secondary(context)),
                    filled: true,
                    fillColor: AdminUi.inputFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AdminUi.borderSubtle(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AdminUi.borderSubtle(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.primary, width: 1.4),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Taxistas: la bandera (tienePagoPendiente) bloquea pool y tomar viajes si falta saldo prepago '
                  '(mín. RD\$${PagosTaxistaRepo.minSaldoPrepagoComisionRd.toStringAsFixed(0)} tras el 1.er viaje en efectivo) '
                  'o si comisión legacy ≥ RD\$${PagosTaxistaRepo.umbralComisionLegacyBloqueoRd.toStringAsFixed(0)}. '
                  'El cobro semanal va en Verificar pagos, no en esta bandera.',
                  style: TextStyle(
                      color: AdminUi.muted(context),
                      fontSize: 11.5,
                      height: 1.35),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('usuarios').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: AdminUi.progressAccent(context)));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Error: ${snap.error}',
                        style: TextStyle(color: AdminUi.secondary(context))),
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
                  return uid.contains(q) ||
                      nombre.contains(q) ||
                      email.contains(q) ||
                      telefono.contains(q);
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
                    child: Text('Sin resultados',
                        style: TextStyle(color: AdminUi.secondary(context))),
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
                    final rol = _normalizarRolUi(_s(m['rol']));
                    final bloqueado = _b(m['bloqueado']);
                    final procesando = _uidsProcesando.contains(uid);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminUi.card(context),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AdminUi.borderSubtle(context)),
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
                                      style: TextStyle(
                                          color: AdminUi.muted(context),
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: bloqueado
                                      ? Colors.red.withValues(alpha: 0.15)
                                      : Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: bloqueado
                                        ? Colors.redAccent
                                            .withValues(alpha: 0.5)
                                        : Colors.greenAccent
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  bloqueado ? 'BLOQUEADO' : 'OK',
                                  style: TextStyle(
                                    color: bloqueado
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Rol: ${rol.isEmpty ? "—" : rol}',
                              style:
                                  TextStyle(color: AdminUi.secondary(context))),
                          if (rol == Roles.taxista &&
                              _b(m['tienePagoPendiente'])) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.amberAccent
                                        .withValues(alpha: 0.45)),
                              ),
                              child: Text(
                                'Bloqueo automático (pool/viajes): prepago bajo o comisión legacy ≥ RD\$'
                                '${PagosTaxistaRepo.umbralComisionLegacyBloqueoRd.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _rolBtn(uid, 'cliente', rol, procesando),
                              _rolBtn(uid, 'taxista', rol, procesando),
                              _rolBtn(uid, 'admin', rol, procesando),
                              _bloqueoBtn(uid, bloqueado, procesando),
                              if (rol == Roles.taxista)
                                _liquidarComisionBtn(
                                  uid,
                                  nombre.isNotEmpty ? nombre : uid,
                                  procesando,
                                ),
                              if (rol == Roles.taxista)
                                _movimientosPrepagoBtn(
                                  uid,
                                  nombre.isNotEmpty ? nombre : uid,
                                  procesando,
                                ),
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

  Widget _rolBtn(
      String uid, String target, String rolActual, bool deshabilitado) {
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

  Widget _liquidarComisionBtn(
      String uid, String nombreMostrar, bool deshabilitado) {
    return InkWell(
      onTap: deshabilitado
          ? null
          : () => _dialogLiquidarComisionEfectivo(uid, nombreMostrar),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AdminUi.card(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.55)),
        ),
        child: const Text(
          'Recarga comisión (efectivo)',
          style:
              TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _movimientosPrepagoBtn(
      String uid, String nombreMostrar, bool deshabilitado) {
    return InkWell(
      onTap: deshabilitado
          ? null
          : () => _dialogMovimientosPrepago(uid, nombreMostrar),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AdminUi.card(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AdminUi.borderSubtle(context)),
        ),
        child: Text(
          'Movimientos prepago',
          style: TextStyle(
              color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
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
          border: Border.all(
              color: bloqueado
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : AdminUi.borderSubtle(context)),
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
