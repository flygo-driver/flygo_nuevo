import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/configuracion_globals_service.dart';
import 'package:flygo_nuevo/servicios/giras_abuso_admin_service.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Cola ADM: taxistas que RAI bloqueó por cancelar muchas salidas por cupos.
class AdminRegularizarGirasTaxista extends StatefulWidget {
  const AdminRegularizarGirasTaxista({
    super.key,
    this.uidTaxistaInicial,
    this.nombreTaxistaInicial,
  });

  final String? uidTaxistaInicial;
  final String? nombreTaxistaInicial;

  @override
  State<AdminRegularizarGirasTaxista> createState() =>
      _AdminRegularizarGirasTaxistaState();
}

class _AdminRegularizarGirasTaxistaState
    extends State<AdminRegularizarGirasTaxista> {
  String? _uidSeleccionado;
  bool _loadingAccion = false;
  double _ratioMax = 0.5;
  int _minCreadas = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_cargarUmbral());
    final uid = (widget.uidTaxistaInicial ?? '').trim();
    if (uid.isNotEmpty) {
      _uidSeleccionado = uid;
    }
  }

  Future<void> _cargarUmbral() async {
    final abuso = await ConfiguracionGlobalsService.fetchGiraAbusoUmbral();
    if (!mounted) return;
    setState(() {
      _ratioMax = abuso.ratioMax;
      _minCreadas = abuso.minCreadas;
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade800 : null,
      ),
    );
  }

  String _motivoAutomatico(Map<String, dynamic> data, String uid) {
    final admin = FirebaseAuth.instance.currentUser?.email ?? 'admin';
    final nombre = (data['nombre'] ?? widget.nombreTaxistaInicial ?? '')
        .toString()
        .trim();
    final email = (data['email'] ?? '').toString().trim();
    return 'Desbloqueo ADM salidas por cupos — $admin — '
        '${nombre.isNotEmpty ? nombre : email.isNotEmpty ? email : uid}';
  }

  Future<void> _desbloquear(String uid, Map<String, dynamic> data) async {
    if (_loadingAccion) return;
    setState(() => _loadingAccion = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(
        'adminRegularizarGirasTaxista',
      );
      final res = await fn.call(<String, dynamic>{
        'uidTaxista': uid,
        'motivo': _motivoAutomatico(data, uid),
      });
      final out = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      _snack(
        '✅ ${(data['nombre'] ?? data['email'] ?? uid).toString()} desbloqueado. '
        'Antes: ${out['girasCanceladasAntes']} canceladas / '
        '${out['girasCreadasAntes']} creadas.',
      );
      if (_uidSeleccionado == uid) {
        setState(() => _uidSeleccionado = null);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final hint = e.code == 'not-found'
          ? ' Despliega functions en flygo-rd.'
          : '';
      _snack('${(e.message ?? e.code).trim()}$hint', error: true);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingAccion = false);
    }
  }

  Widget _tileBloqueado(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool seleccionado,
  }) {
    final data = doc.data();
    final uid = doc.id;
    final nombre = (data['nombre'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final c = (data['girasCreadasUltimoMes'] as num?)?.toInt() ?? 0;
    final x = (data['girasCanceladasAntesDeIniciar'] as num?)?.toInt() ?? 0;
    final ts = data[GirasAbusoAdminService.kCampoBloqueadoEn];
    String cuando = '';
    if (ts is Timestamp) {
      final d = ts.toDate();
      cuando =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    final titulo = nombre.isNotEmpty
        ? nombre
        : email.isNotEmpty
            ? email
            : uid;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: seleccionado
          ? Colors.green.withValues(alpha: 0.12)
          : AdminUi.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: seleccionado
              ? Colors.greenAccent
              : Colors.orangeAccent.withValues(alpha: 0.45),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _loadingAccion
            ? null
            : () => setState(() {
                  _uidSeleccionado = seleccionado ? null : uid;
                }),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.block,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (seleccionado)
                    const Icon(Icons.check_circle, color: Colors.greenAccent),
                ],
              ),
              if (email.isNotEmpty && nombre.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(email,
                    style: TextStyle(
                        color: AdminUi.muted(context), fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Text(
                'RAI bloqueó por cancelaciones: $x canceladas / $c creadas (30 días)',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              if (cuando.isNotEmpty)
                Text(
                  'Bloqueado: $cuando',
                  style: TextStyle(
                    color: AdminUi.muted(context),
                    fontSize: 11,
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loadingAccion
                      ? null
                      : () => _desbloquear(uid, data),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Desbloquear'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: const AdminAppBar(
        guiaId: AdminGuiaIds.desbloquearGiras,
        title: 'Desbloquear salidas por cupos',
      ),
      drawer: const AdminDrawer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Choferes que RAI bloqueó al cancelar muchas salidas por cupos. '
              'Aparecen solos aquí; solo pulsa Desbloquear.',
              style: TextStyle(color: AdminUi.muted(context), height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Umbral actual: ≥$_minCreadas creadas y más del '
              '${(_ratioMax * 100).round()}% canceladas sin confirmar comisión.',
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: GirasAbusoAdminService.streamColaBloqueados(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error al cargar cola: ${snap.error}\n'
                        'Si es índice Firestore, despliega firestore:indexes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AdminUi.secondary(context)),
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nadie bloqueado por cancelaciones ahora.\n\n'
                        'Cuando un chofer pase el límite, saldrá aquí automáticamente. '
                        'Casos viejos (antes de esta actualización): desbloquea desde '
                        'Gestionar usuarios → Desbloquear salidas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AdminUi.muted(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    return _tileBloqueado(
                      doc,
                      seleccionado: _uidSeleccionado == doc.id,
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
}
