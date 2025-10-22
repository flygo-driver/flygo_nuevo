import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// ---- BOTÓN con loading reutilizable (sin context after await) ----
class _ActionButton extends StatelessWidget {
  final ValueNotifier<bool> loading;
  final Future<void> Function() run;
  final String okMsg;
  final String failMsg;
  final Widget child;
  final ButtonStyle? style;

  const _ActionButton({
    required this.loading,
    required this.run,
    required this.okMsg,
    required this.failMsg,
    required this.child,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: loading,
      builder: (_, isLoading, __) {
        return ElevatedButton(
          style: style,
          onPressed: isLoading
              ? null
              : () async {
                  // Captura el messenger ANTES del await → no hay "use_build_context_synchronously".
                  final messenger = ScaffoldMessenger.of(context);
                  loading.value = true;
                  try {
                    await run();
                    messenger.showSnackBar(SnackBar(content: Text(okMsg)));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$failMsg: $e')));
                  } finally {
                    loading.value = false;
                  }
                },
          child: isLoading
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : child,
        );
      },
    );
  }
}

/// ---- TAXISTA ----
class ViajeActionBarTaxista extends StatelessWidget {
  final String viajeId;
  final String estadoActual;

  ViajeActionBarTaxista({
    super.key,
    required this.viajeId,
    required this.estadoActual,
  });

  // un único notificador para no duplicar clicks
  final ValueNotifier<bool> _loading = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    final uidTaxista = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uidTaxista.isEmpty) return const SizedBox.shrink();

    final e = EstadosViaje.normalizar(estadoActual);
    final acciones = <Widget>[];

    // ACEPTADO -> En camino / Cancelar
    if (e == EstadosViaje.aceptado) {
      acciones.addAll([
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.marcarEnCaminoPickup(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Marcado: en camino',
          failMsg: 'No se pudo marcar en camino',
          child: const Text('Ir a buscar cliente'),
        ),
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.cancelarPorTaxista(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Viaje liberado',
          failMsg: 'No se pudo cancelar',
          child: const Text('Cancelar'),
          style: OutlinedButton.styleFrom().merge(
            ElevatedButton.styleFrom(backgroundColor: Colors.transparent, elevation: 0),
          ),
        ),
      ]);
    }

    // EN_CAMINO_PICKUP -> Cliente a bordo / Cancelar
    if (e == EstadosViaje.enCaminoPickup) {
      acciones.addAll([
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.marcarClienteAbordo(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Cliente a bordo',
          failMsg: 'No se pudo marcar a bordo',
          child: const Text('Cliente a bordo'),
        ),
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.cancelarPorTaxista(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Viaje liberado',
          failMsg: 'No se pudo cancelar',
          child: const Text('Cancelar'),
          style: OutlinedButton.styleFrom().merge(
            ElevatedButton.styleFrom(backgroundColor: Colors.transparent, elevation: 0),
          ),
        ),
      ]);
    }

    // A_BORDO -> Iniciar viaje
    if (e == EstadosViaje.aBordo) {
      acciones.add(
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.iniciarViaje(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Viaje iniciado',
          failMsg: 'No se pudo iniciar',
          child: const Text('Iniciar viaje'),
        ),
      );
    }

    // EN_CURSO -> Completar
    if (e == EstadosViaje.enCurso) {
      acciones.add(
        _ActionButton(
          loading: _loading,
          run: () => ViajesRepo.completarViajePorTaxista(
            viajeId: viajeId,
            uidTaxista: uidTaxista,
          ),
          okMsg: 'Viaje completado',
          failMsg: 'No se pudo completar',
          child: const Text('Completar viaje'),
        ),
      );
    }

    if (acciones.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: acciones,
        ),
      ),
    );
  }
}

/// ---- CLIENTE ----
class ViajeActionBarCliente extends StatelessWidget {
  final String viajeId;
  final String estadoActual;
  final String uidCliente;

  ViajeActionBarCliente({
    super.key,
    required this.viajeId,
    required this.estadoActual,
    required this.uidCliente,
  });

  final ValueNotifier<bool> _loading = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    final e = EstadosViaje.normalizar(estadoActual);

    // cliente puede cancelar mientras NO esté en curso ni completado
    final puedeCancelar = e == EstadosViaje.pendiente ||
        e == EstadosViaje.pendientePago ||
        e == EstadosViaje.aceptado ||
        e == EstadosViaje.enCaminoPickup ||
        e == EstadosViaje.aBordo;

    if (!puedeCancelar) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Center(
          child: _ActionButton(
            loading: _loading,
            run: () => ViajesRepo.cancelarPorCliente(
              viajeId: viajeId,
              uidCliente: uidCliente,
              motivo: 'Cancelado por el cliente',
            ),
            okMsg: 'Viaje cancelado',
            failMsg: 'No se pudo cancelar',
            child: const Text('Cancelar viaje'),
            style: OutlinedButton.styleFrom().merge(
              ElevatedButton.styleFrom(backgroundColor: Colors.transparent, elevation: 0),
            ),
          ),
        ),
      ),
    );
  }
}
