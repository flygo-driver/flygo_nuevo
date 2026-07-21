import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/servicios/admin_usuarios_lista_service.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

import 'admin_ui_theme.dart';

/// ADM solo lectura: confirmación periódica (selfie) de clientes.
class AdminVerificacionIdentidadCliente extends StatefulWidget {
  const AdminVerificacionIdentidadCliente({super.key});

  @override
  State<AdminVerificacionIdentidadCliente> createState() =>
      _AdminVerificacionIdentidadClienteState();
}

class _AdminVerificacionIdentidadClienteState
    extends State<AdminVerificacionIdentidadCliente> {
  final _buscarCtrl = TextEditingController();
  String _buscar = '';
  String _filtro = 'todos';

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString();

  bool _pasaFiltro(ClienteVerificacionIdentidadEstado estado) {
    switch (_filtro) {
      case 'vigente':
        return estado == ClienteVerificacionIdentidadEstado.vigente;
      case 'vencida':
        return estado == ClienteVerificacionIdentidadEstado.vencida;
      case 'sin':
        return estado == ClienteVerificacionIdentidadEstado.sinSelfie;
      default:
        return true;
    }
  }

  bool _pasaBusqueda(Map<String, dynamic> m, String uid) {
    final q = _buscar.trim().toLowerCase();
    if (q.isEmpty) return true;
    final nombre = _s(m['nombre']).toLowerCase();
    final email = _s(m['email']).toLowerCase();
    final tel = _s(m['telefono']).toLowerCase();
    return uid.toLowerCase().contains(q) ||
        nombre.contains(q) ||
        email.contains(q) ||
        tel.contains(q);
  }

  Future<void> _abrirSelfie(String? url) async {
    final u = Uri.tryParse((url ?? '').trim());
    if (u == null ||
        !(u.hasScheme && (u.scheme == 'http' || u.scheme == 'https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay selfie guardada para este cliente.')),
      );
      return;
    }
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la selfie.')),
      );
    }
  }

  Widget _chipFiltro(String id, String label) {
    final sel = _filtro == id;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filtro = id),
      selectedColor: AdminUi.accentGreen(context).withValues(alpha: 0.2),
      checkmarkColor: AdminUi.accentGreen(context),
    );
  }

  Widget _tileCliente(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};
    final uid = doc.id;
    final estado = ClienteVerificacionIdentidadService.estadoDesde(m);
    final color = ClienteVerificacionIdentidadService.colorEstado(
      estado,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
    final nombre = _s(m['nombre']).trim();
    final email = _s(m['email']).trim();
    final selfieUrl = ClienteVerificacionIdentidadService.urlSelfieDesde(m);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                child: Text(
                  nombre.isNotEmpty ? nombre : uid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Text(
                  ClienteVerificacionIdentidadService.etiquetaEstado(estado),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            email.isNotEmpty ? email : 'UID: $uid',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            ClienteVerificacionIdentidadService.detalleEstadoParaAdmin(m),
            style: TextStyle(
              color: AdminUi.secondary(context),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (selfieUrl != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _abrirSelfie(selfieUrl),
              icon: const Icon(Icons.photo_outlined, size: 18),
              label: const Text('Ver última selfie'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: const AdminAppBar(
        title: 'Confirmación selfie clientes',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Solo lectura. Estado de la selfie periódica del pasajero '
              '(no es verificación con documento ni liveness).',
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _buscarCtrl,
              style: TextStyle(color: AdminUi.onCard(context)),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email, teléfono o UID',
                prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
                suffixIcon: _buscar.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscarCtrl.clear();
                          setState(() => _buscar = '');
                        },
                      ),
                filled: true,
                fillColor: AdminUi.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
              ),
              onChanged: (v) => setState(() => _buscar = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipFiltro('todos', 'Todos'),
                _chipFiltro('vigente', 'Selfie al día'),
                _chipFiltro('vencida', 'Vencida'),
                _chipFiltro('sin', 'Sin confirmación'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AdminUsuariosListaService.streamLista(
                modo: 'clientes',
                campoOrden: 'updatedAt',
                limite: AdminUsuariosListaService.limiteInicial,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar clientes: ${snap.error}',
                      style: TextStyle(color: AdminUi.muted(context)),
                    ),
                  );
                }
                final docs = (snap.data?.docs ?? const [])
                    .where((d) {
                      final m = d.data();
                      final estado =
                          ClienteVerificacionIdentidadService.estadoDesde(m);
                      return _pasaFiltro(estado) && _pasaBusqueda(m, d.id);
                    })
                    .toList(growable: false);

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No hay clientes con este filtro.',
                      style: TextStyle(color: AdminUi.muted(context)),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _tileCliente(docs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
