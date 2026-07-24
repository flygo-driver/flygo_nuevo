import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

/// Calendario semanal de rutas corporativas de un chofer (todas las empresas).
class AdminCorporativoCalendarioPage extends StatefulWidget {
  const AdminCorporativoCalendarioPage({
    super.key,
    required this.choferUid,
    this.choferNombre = '',
  });

  final String choferUid;
  final String choferNombre;

  @override
  State<AdminCorporativoCalendarioPage> createState() =>
      _AdminCorporativoCalendarioPageState();
}

class _AdminCorporativoCalendarioPageState
    extends State<AdminCorporativoCalendarioPage> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _rutas = const [];

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('adminCalendarioChoferCorporativo')
          .call({'choferUid': widget.choferUid});
      final data = Map<String, dynamic>.from(res.data as Map);
      final raw = (data['rutas'] as List?) ?? const [];
      setState(() {
        _rutas = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  List<Map<String, dynamic>> _rutasDia(int diaIso) {
    return _rutas.where((r) {
      final dias = (r['dias'] as List?)?.map((d) => (d as num).toInt()).toList() ??
          const <int>[];
      return dias.contains(diaIso);
    }).toList()
      ..sort(
        (a, b) => (a['hora'] ?? '').toString().compareTo(
              (b['hora'] ?? '').toString(),
            ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.choferNombre.trim().isEmpty
        ? 'Calendario chofer'
        : 'Calendario · ${widget.choferNombre}';

    return Scaffold(
      appBar: AdminAppBar(title: titulo),
      drawer: const AdminDrawer(),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Rutas asignadas (${_rutas.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(7, (i) {
                        final diaIso = i + 1;
                        final delDia = _rutasDia(diaIso);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ExpansionTile(
                            title: Text(
                              '${_dias[i]} (${delDia.length})',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            children: delDia.isEmpty
                                ? [
                                    const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text('Sin rutas este día'),
                                    ),
                                  ]
                                : delDia.map((r) {
                                    final conflicto = delDia.length > 1;
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        conflicto
                                            ? Icons.warning_amber_rounded
                                            : Icons.check_circle_outline,
                                        color: conflicto
                                            ? Colors.orange
                                            : Colors.green,
                                      ),
                                      title: Text(
                                        '${r['hora']} · ${r['nombre']}',
                                      ),
                                      subtitle: Text(
                                        '${r['empresaNombre']} · ~${r['tiempoEstimadoMin'] ?? 60} min',
                                      ),
                                    );
                                  }).toList(),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
