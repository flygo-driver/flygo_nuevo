// Bandeja de operaciones: mensajes del cliente cuando espera conductor.
// Antes solo llegaba una alerta suelta y nadie podía contestar.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicios/operaciones_mensajes_adm_repo.dart';
import '../../widgets/admin_app_bar.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminMensajesOperacionesPage extends StatefulWidget {
  const AdminMensajesOperacionesPage({super.key});

  @override
  State<AdminMensajesOperacionesPage> createState() =>
      _AdminMensajesOperacionesPageState();
}

enum _FiltroMensajes { pendientes, todos }

class _AdminMensajesOperacionesPageState
    extends State<AdminMensajesOperacionesPage> {
  _FiltroMensajes _filtro = _FiltroMensajes.pendientes;
  final Set<String> _ocupados = <String>{};

  bool _pendiente(Map<String, dynamic> m) =>
      (m['respuesta'] ?? '').toString().trim().isEmpty;

  String _cuando(dynamic ts) {
    if (ts is! Timestamp) return '';
    final DateTime dt = ts.toDate().toLocal();
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} $hh:$mm';
  }

  Future<void> _responder(String id, Map<String, dynamic> m) async {
    final TextEditingController ctrl = TextEditingController();
    final String? texto = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Responder al cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              (m['mensaje'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              autofocus: true,
              maxLength: OperacionesMensajesAdmRepo.maxRespuestaChars,
              decoration: const InputDecoration(
                hintText:
                    'Ej.: Ya tenemos un conductor en camino, llega en 5 minutos.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Enviar respuesta'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (texto == null || texto.trim().isEmpty || !mounted) return;

    setState(() => _ocupados.add(id));
    try {
      await OperacionesMensajesAdmRepo.responderComoAdm(
        mensajeId: id,
        respuesta: texto,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respuesta enviada al cliente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo responder: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupados.remove(id));
    }
  }

  Future<void> _marcarLeido(String id) async {
    try {
      await OperacionesMensajesAdmRepo.marcarLeidoPorAdm(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo marcar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: const AdminAppBar(title: 'Mensajes de clientes (espera conductor)'),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Sin responder'),
                  selected: _filtro == _FiltroMensajes.pendientes,
                  onSelected: (_) =>
                      setState(() => _filtro = _FiltroMensajes.pendientes),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _filtro == _FiltroMensajes.todos,
                  onSelected: (_) =>
                      setState(() => _filtro = _FiltroMensajes.todos),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: OperacionesMensajesAdmRepo.streamMensajesAdmin(),
              builder: (
                BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
              ) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    (snap.data?.docs ?? const []).where((d) {
                  if (_filtro == _FiltroMensajes.todos) return true;
                  return _pendiente(d.data());
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _filtro == _FiltroMensajes.pendientes
                          ? 'Nada pendiente. Todos los clientes están respondidos.'
                          : 'Todavía no hay mensajes de clientes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, int i) {
                    final doc = docs[i];
                    final Map<String, dynamic> m = doc.data();
                    final bool pendiente = _pendiente(m);
                    final bool ocupado = _ocupados.contains(doc.id);
                    final String respuesta =
                        (m['respuesta'] ?? '').toString().trim();

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminUi.card(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: pendiente
                              ? Colors.orangeAccent.withValues(alpha: 0.5)
                              : AdminUi.borderSubtle(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                pendiente
                                    ? Icons.mark_email_unread_rounded
                                    : Icons.mark_email_read_rounded,
                                size: 20,
                                color: pendiente
                                    ? Colors.orangeAccent
                                    : AdminUi.accentGreen(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (m['clienteNombre'] ?? 'Cliente RAI')
                                      .toString(),
                                  style: TextStyle(
                                    color: AdminUi.onCard(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _cuando(m['createdAt']),
                                style: TextStyle(
                                  color: AdminUi.muted(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(m['tipoServicio'] ?? 'normal')} · '
                            '${(m['ruta'] ?? 'Viaje RAI')}',
                            style: TextStyle(
                              color: AdminUi.secondary(context),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (m['mensaje'] ?? '').toString(),
                            style: TextStyle(
                              color: AdminUi.onCard(context),
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                          ),
                          if (respuesta.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AdminUi.accentGreen(context)
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Respondido: $respuesta',
                                style: TextStyle(
                                  color: AdminUi.secondary(context),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed:
                                    ocupado ? null : () => _responder(doc.id, m),
                                icon: const Icon(Icons.reply_rounded, size: 18),
                                label: Text(
                                  respuesta.isEmpty ? 'Responder' : 'Responder otra vez',
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (m['leidoPorAdm'] != true)
                                TextButton(
                                  onPressed: () => _marcarLeido(doc.id),
                                  child: const Text('Marcar leído'),
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
}
