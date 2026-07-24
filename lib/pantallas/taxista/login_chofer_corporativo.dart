import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/servicios/solicitud_corporativo_repo.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

/// Taxista solicita entrar al pool de choferes corporativos RAI.
class LoginChoferCorporativo extends StatefulWidget {
  const LoginChoferCorporativo({super.key});

  @override
  State<LoginChoferCorporativo> createState() => _LoginChoferCorporativoState();
}

class _LoginChoferCorporativoState extends State<LoginChoferCorporativo> {
  final _notaCtrl = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await SolicitudCorporativoRepo.enviarSolicitud(nota: _notaCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada. RAI la revisará pronto.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _salir() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) root.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: RaiDsColors.bg,
      appBar: RaiShellTabHeader(
        title: 'Chofer corporativo RAI',
        backTooltip: 'Volver a Servicios',
        onBack: _salir,
      ),
      body: user == null
          ? const Center(child: Text('Inicia sesión como taxista'))
          : StreamBuilder<EstadoRegistroCorporativo>(
              stream: SolicitudCorporativoRepo.streamEstadoRegistro(user.uid),
              builder: (context, snap) {
                final estado = snap.data;
                if (snap.connectionState == ConnectionState.waiting &&
                    estado == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (estado?.fase == 'aprobado') {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_outlined,
                            size: 56, color: cs.primary),
                        const SizedBox(height: 16),
                        const Text(
                          'Estás en el pool corporativo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'RAI te asignará rutas fijas de empresas. '
                          'No aparecen en el pool público.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _salir,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Volver a Servicios'),
                        ),
                      ],
                    ),
                  );
                }

                if (estado?.fase == 'pendiente_adm') {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.hourglass_top, size: 56, color: cs.tertiary),
                        const SizedBox(height: 16),
                        const Text(
                          'Solicitud en revisión',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Administración RAI revisará tu perfil de taxista.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _salir,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Volver a Servicios'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Rutas fijas para empresas',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Como turismo, corporativo es un servicio aparte. '
                      'RAI te asigna manualmente cada ruta de empresa.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    if (estado?.fase == 'rechazado') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Solicitud rechazada'
                          '${estado!.motivoRechazo != null && estado.motivoRechazo!.isNotEmpty ? ': ${estado.motivoRechazo}' : ''}',
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _notaCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Nota para RAI (opcional)',
                        hintText: 'Ej: Disponible lun–vie 6am–4pm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: cs.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _enviando ? null : _enviar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text('Enviar solicitud'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
