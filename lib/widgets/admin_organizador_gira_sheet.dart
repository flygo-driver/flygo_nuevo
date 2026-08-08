import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';

/// Ficha del organizador de giras para validación en ADM (incluye cédula).
Future<void> mostrarOrganizadorGiraAdm(
  BuildContext context, {
  required String ownerUid,
  String? nombreFallback,
}) async {
  if (ownerUid.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Esta salida no tiene organizador asociado.')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(ownerUid)
              .get(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final d = snap.data?.data() ?? <String, dynamic>{};
            final nombre = (d['nombre'] ?? nombreFallback ?? '').toString().trim();
            final agencia = (d['agenciaNombre'] ?? '').toString().trim();
            final cedula =
                (d['cedula'] ?? d['ciTaxista'] ?? '').toString().trim();
            final tel = (d['telefono'] ?? '').toString().trim();
            final wa = (d['whatsapp'] ?? tel).toString().trim();
            final banco = (d['bancoNombre'] ?? '').toString().trim();
            final cuenta = (d['bancoCuenta'] ?? '').toString().trim();
            final titular = (d['bancoTitular'] ?? '').toString().trim();
            final fotoUrl = (d['cedulaFotoUrl'] ?? d['documentoIdentidadUrl'] ?? '')
                .toString()
                .trim();
            final registroOk = d['registroOrganizadorGirasCompleto'] == true;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Organizador de giras',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nombre.isEmpty ? ownerUid : nombre,
                    style: TextStyle(color: AdminUi.muted(ctx)),
                  ),
                  const SizedBox(height: 16),
                  _fila('Agencia', agencia.isEmpty ? '—' : agencia),
                  _fila('Cédula / pasaporte', cedula.isEmpty ? '—' : cedula),
                  _fila('Teléfono', tel.isEmpty ? '—' : tel),
                  _fila('WhatsApp', wa.isEmpty ? '—' : wa),
                  _fila('Registro completo', registroOk ? 'Sí' : 'No'),
                  _fila('Banco', banco.isEmpty ? '—' : banco),
                  _fila('Cuenta', cuenta.isEmpty ? '—' : cuenta),
                  _fila('Titular', titular.isEmpty ? '—' : titular),
                  const SizedBox(height: 16),
                  Text(
                    'Documento de identidad',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AdminUi.secondary(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (fotoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        fotoUrl,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 120,
                          alignment: Alignment.center,
                          color: AdminUi.muted(ctx).withValues(alpha: 0.12),
                          child: Text(
                            'No se pudo cargar la foto. Verifica permisos Storage.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AdminUi.muted(ctx)),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminUi.muted(ctx).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Sin foto de cédula en el perfil. El organizador debe completar registro.',
                        style: TextStyle(color: AdminUi.muted(ctx), height: 1.35),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'UID: $ownerUid',
                    style: TextStyle(
                      fontSize: 11,
                      color: AdminUi.muted(ctx),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Widget _fila(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
