import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

class ToggleDisponibilidad extends StatefulWidget {
  const ToggleDisponibilidad({super.key});

  @override
  State<ToggleDisponibilidad> createState() => _ToggleDisponibilidadState();
}

class _ToggleDisponibilidadState extends State<ToggleDisponibilidad> {
  bool? _valor; // null = cargando
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      RolesService.streamDisponibilidad(u.uid).listen((v) {
        if (!mounted) return;
        setState(() => _valor = v ?? false);
      });
    } else {
      _valor = false;
    }
  }

  Future<void> _cambiar(bool v) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    setState(() => _guardando = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
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
    final cargando = (_valor == null);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Disponibilidad'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : ListTile(
              title: const Text(
                'Taxista disponible',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Switch(
                value: _valor ?? false,
                onChanged: _guardando ? null : _cambiar,
              ),
              subtitle: _guardando
                  ? const Text(
                      'Guardando…',
                      style: TextStyle(color: Colors.white70),
                    )
                  : Text(
                      (_valor ?? false)
                          ? 'Recibirás viajes'
                          : 'No recibirás viajes',
                      style: const TextStyle(color: Colors.white70),
                    ),
            ),
    );
  }
}
