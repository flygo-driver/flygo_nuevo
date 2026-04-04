import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/contrato_taxista_firma.dart';

class ToggleDisponibilidad extends StatefulWidget {
  const ToggleDisponibilidad({super.key});

  @override
  State<ToggleDisponibilidad> createState() => _ToggleDisponibilidadState();
}

class _ToggleDisponibilidadState extends State<ToggleDisponibilidad> {
  bool _guardando = false;

  Future<void> _cambiar(bool v) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    setState(() => _guardando = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Flujo profesional: activar disponibilidad solo cuando documentos y aprobación están OK.
      if (v) {
        final userSnap = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(u.uid)
            .get();
        final data = userSnap.data() ?? <String, dynamic>{};
        final bool poolOk = taxistaAprobadoParaOperarPool(data);
        final bool contratoOk = taxistaContratoFirmado(data);
        if (!poolOk) {
          final estado = taxistaDocsEstadoDesdeUsuario(data);
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  estado == 'aprobado'
                      ? 'Completa tu perfil/documentos para activar disponibilidad.'
                      : 'Debes subir y aprobar documentos antes de activar disponibilidad.',
                ),
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DocumentosTaxista()),
            );
          }
          return;
        }
        if (!contratoOk) {
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Debes firmar el contrato digital para activar disponibilidad.'),
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContratoTaxistaFirma()),
            );
          }
          return;
        }
      }
      await RolesService.setDisponibilidad(u.uid, v);
      messenger.showSnackBar(
        SnackBar(
          content: Text(v ? 'Ahora estás disponible' : 'Marcado como no disponible'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Disponibilidad'),
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
        ),
        body: Center(
          child: Text(
            'Sesión no válida. Vuelve a iniciar sesión.',
            style: TextStyle(color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Disponibilidad'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('usuarios').doc(u.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar tu perfil.\n${snap.error}',
                  style: TextStyle(color: cs.onSurface),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data?.data() ?? <String, dynamic>{};
          final rawDisp = data['disponible'];
          final bool disponible = rawDisp is bool ? rawDisp : false;
          final poolOk = taxistaAprobadoParaOperarPool(data);
          final estadoDocs = taxistaDocsEstadoDesdeUsuario(data);

          return ListTile(
            title: Text(
              'Taxista disponible',
              style: TextStyle(color: cs.onSurface),
            ),
            trailing: Switch(
              value: disponible,
              onChanged: _guardando ? null : _cambiar,
              thumbColor: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  if (states.contains(WidgetState.disabled)) {
                    return cs.onSurface.withValues(alpha: 0.38);
                  }
                  final selected = states.contains(WidgetState.selected);
                  if (selected) return cs.onPrimaryContainer;
                  return cs.onSurface.withValues(alpha: 0.65);
                },
              ),
              trackColor: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  if (states.contains(WidgetState.disabled)) {
                    return cs.onSurface.withValues(alpha: 0.10);
                  }
                  final selected = states.contains(WidgetState.selected);
                  return selected
                      ? cs.primary.withValues(alpha: 0.45)
                      : cs.onSurface.withValues(alpha: 0.18);
                },
              ),
            ),
            subtitle: _guardando
                ? Text(
                    'Guardando…',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  )
                : Text(
                    poolOk
                        ? (disponible ? 'Recibirás viajes' : 'No recibirás viajes')
                        : 'Estado de documentos: $estadoDocs. Debes completar y aprobar para operar.',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
          );
        },
      ),
    );
  }
}
