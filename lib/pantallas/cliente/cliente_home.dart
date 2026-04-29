import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/seleccion_servicio.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';

class ClienteHome extends StatefulWidget {
  const ClienteHome({super.key});

  @override
  State<ClienteHome> createState() => _ClienteHomeState();
}

class _ClienteHomeState extends State<ClienteHome> {
  bool _cerrarBannerRegistro = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SeleccionServicio();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final pendiente =
            data != null && data['registroClienteCompleto'] == false;
        final show = pendiente && !_cerrarBannerRegistro;

        final Widget? banner = show
            ? Material(
                color: const Color(0xFF1A237E),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConfiguracionPerfil(),
                      ),
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note,
                            color: Colors.white70, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Completa nombre, teléfono y foto de perfil cuando quieras — '
                            'es opcional y no impide pedir viajes.',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 20),
                          onPressed: () =>
                              setState(() => _cerrarBannerRegistro = true),
                          tooltip: 'Cerrar',
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null;

        return SeleccionServicio(bannerEncabezado: banner);
      },
    );
  }
}
