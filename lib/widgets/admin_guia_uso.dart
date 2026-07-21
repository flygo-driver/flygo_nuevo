import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';

/// IDs de guía para pantallas del panel Admin.
abstract final class AdminGuiaIds {
  static const centro = 'centro';
  static const torre = 'torre';
  static const alertas = 'alertas';
  static const bola = 'bola';
  static const asistente = 'asistente';
  static const verificarPagos = 'verificar_pagos';
  static const finanzas = 'finanzas';
  static const empresasCorp = 'empresas_corp';
  static const choferesCorp = 'choferes_corp';
  static const tarifasCorp = 'tarifas_corp';
  static const cuentasCorp = 'cuentas_corp';
  static const liquidaciones = 'liquidaciones';
  static const resumenComisiones = 'resumen_comisiones';
  static const comisionEfectivo = 'comision_efectivo';
  static const incentivos = 'incentivos';
  static const tarifas = 'tarifas';
  static const promos = 'promos';
  static const reportes = 'reportes';
  static const incidencias = 'incidencias';
  static const auditoria = 'auditoria';
  static const configRai = 'config_rai';
  static const expedientes = 'expedientes';
  static const usuarios = 'usuarios';
  static const aprobarTurismo = 'aprobar_turismo';
  static const controlTurismo = 'control_turismo';
  static const viajesTurismo = 'viajes_turismo';
  static const girasCupos = 'giras_cupos';
  static const desbloquearGiras = 'desbloquear_giras';
  static const choferesTurismo = 'choferes_turismo';
  static const destinosTurismo = 'destinos_turismo';
  static const rutasCorp = 'rutas_corp';
  static const asignarTurismo = 'asignar_turismo';
}

class AdminGuiaEntry {
  const AdminGuiaEntry({
    required this.titulo,
    required this.paraQue,
    required this.pasos,
    required this.resultado,
  });

  final String titulo;
  final String paraQue;
  final List<String> pasos;
  final String resultado;
}

/// Catálogo de guías resumidas (solo texto; no cambia lógica).
abstract final class AdminGuiaCatalogo {
  static const Map<String, AdminGuiaEntry> _map = {
    AdminGuiaIds.centro: AdminGuiaEntry(
      titulo: 'Centro de operaciones',
      paraQue:
          'Ver de un vistazo qué está pendiente hoy: viajes, pagos, documentos y colas.',
      pasos: [
        'Revisá las tarjetas con número (cola).',
        'Tocá una tarjeta para abrir esa pantalla.',
        'Atendé primero lo rojo / con contador alto.',
      ],
      resultado: 'Operación del día controlada sin buscar menú por menú.',
    ),
    AdminGuiaIds.torre: AdminGuiaEntry(
      titulo: 'Torre de control',
      paraQue: 'Monitorear viajes en vivo y los que buscan chofer.',
      pasos: [
        'Mirar estado de cada viaje (buscando / en curso).',
        'Intervenir solo si hay demora o incidencia.',
      ],
      resultado: 'Sabés qué pasa en la calle en este momento.',
    ),
    AdminGuiaIds.alertas: AdminGuiaEntry(
      titulo: 'Alertas operativas',
      paraQue: 'Ver avisos automáticos por umbrales (demoras, fallos, picos).',
      pasos: [
        'Leé alertas no leídas.',
        'Actuá en la pantalla relacionada (torre, pagos, etc.).',
      ],
      resultado: 'Problemas detectados a tiempo.',
    ),
    AdminGuiaIds.bola: AdminGuiaEntry(
      titulo: 'Bola Pueblo',
      paraQue: 'Administrar pedidos/ofertas pueblo a pueblo y transferencias.',
      pasos: [
        'Revisá publicaciones abiertas.',
        'Validá rutas y pagos asociados si aplica.',
      ],
      resultado: 'Módulo Bola bajo control operativo.',
    ),
    AdminGuiaIds.asistente: AdminGuiaEntry(
      titulo: 'Asistente RAI',
      paraQue: 'Ver uso diario y cuotas del asistente.',
      pasos: [
        'Revisá consumo / límites.',
        'Ajustá solo si hay abuso o necesidad comercial.',
      ],
      resultado: 'Uso del asistente monitoreado.',
    ),
    AdminGuiaIds.verificarPagos: AdminGuiaEntry(
      titulo: 'Verificar pagos',
      paraQue:
          'Aprobar o rechazar recargas prepago, comisiones y transferencias de choferes.',
      pasos: [
        'Abrí la pestaña pendiente.',
        'Revisá el comprobante / monto.',
        'Aprobá (acredita) o rechazá con motivo.',
      ],
      resultado: 'Choferes con saldo correcto; sin pagos falsos.',
    ),
    AdminGuiaIds.finanzas: AdminGuiaEntry(
      titulo: 'Finanzas en vivo',
      paraQue: 'Ver resumen financiero agregado de la plataforma.',
      pasos: [
        'Revisá totales y tendencias.',
        'Cruzá con Verificar pagos / Liquidaciones si hay duda.',
      ],
      resultado: 'Visión rápida de dinero RAI.',
    ),
    AdminGuiaIds.empresasCorp: AdminGuiaEntry(
      titulo: 'Empresas corporativas',
      paraQue: 'Dar de alta empresas B2B, contrato RAI y encargado.',
      pasos: [
        'Creá o abrí la empresa.',
        'Poné RNC, encargado (correo) y activá contrato cuando toque.',
        'Asigná chofer fijo a las rutas desde aquí o en rutas.',
      ],
      resultado: 'Empresa lista para que el encargado opere en /corporativo.',
    ),
    AdminGuiaIds.choferesCorp: AdminGuiaEntry(
      titulo: 'Choferes corporativos',
      paraQue: 'Aprobar, pausar o reactivar choferes del pool corporativo.',
      pasos: [
        'Revisá solicitudes pendientes.',
        'Aprobá solo conductores verificados.',
        'Pausá si hay problema operativo.',
      ],
      resultado: 'Pool corporativo limpio y confiable.',
    ),
    AdminGuiaIds.tarifasCorp: AdminGuiaEntry(
      titulo: 'Tarifas corporativas',
      paraQue: 'Definir precio global B2B (km, base, comisión, transferencia).',
      pasos: [
        'Opcional: «Cargar tarifa justa B2B».',
        'Revisá cada campo.',
        'Guardá para que aplique a rutas nuevas / cálculos.',
      ],
      resultado: 'Tarifa corporativa activa y coherente en toda la red.',
    ),
    AdminGuiaIds.cuentasCorp: AdminGuiaEntry(
      titulo: 'Cuentas corporativas',
      paraQue:
          'Ver deudas por empresa, validar bauches y poner la cuenta en cero al cobrar.',
      pasos: [
        'Abrí la empresa con saldo.',
        'Validá bauche si el encargado lo envió.',
        'Cuando RAI cobró: «poner en cero» / marcar pagado.',
      ],
      resultado: 'Cobranza B2B al día y períodos archivados.',
    ),
    AdminGuiaIds.liquidaciones: AdminGuiaEntry(
      titulo: 'Liquidaciones',
      paraQue: 'Gestionar liquidaciones / comisiones semanales de choferes.',
      pasos: [
        'Filtrá por estado (pendiente / aprobado).',
        'Revisá montos y aprobá o rechazá.',
      ],
      resultado: 'Comisiones de choferes liquidadas correctamente.',
    ),
    AdminGuiaIds.resumenComisiones: AdminGuiaEntry(
      titulo: 'Resumen de comisiones',
      paraQue: 'Ver estadísticas diarias de comisiones.',
      pasos: [
        'Elegí rango o día.',
        'Usá el resumen para control interno.',
      ],
      resultado: 'Números de comisión claros para la operación.',
    ),
    AdminGuiaIds.comisionEfectivo: AdminGuiaEntry(
      titulo: 'Comisión viaje (efectivo)',
      paraQue: 'Cambiar el % global de comisión en viajes de efectivo.',
      pasos: [
        'Poné el porcentaje deseado.',
        'Guardá (impacta viajes nuevos según config).',
      ],
      resultado: '% de comisión de calle actualizado.',
    ),
    AdminGuiaIds.incentivos: AdminGuiaEntry(
      titulo: 'Incentivos comisión taxista',
      paraQue: 'Bajar % de comisión si el chofer hace muchos viajes.',
      pasos: [
        'Definí tramos (viajes → % menor).',
        'Guardá la tabla de incentivos.',
      ],
      resultado: 'Choferes productivos pagan menos % (incentivo).',
    ),
    AdminGuiaIds.tarifas: AdminGuiaEntry(
      titulo: 'Tarifas',
      paraQue: 'Configurar tarifas locales, turismo y tramos de larga distancia.',
      pasos: [
        'Elegí el tipo de tarifa.',
        'Editá montos / km / mínimos.',
        'Guardá cambios.',
      ],
      resultado: 'Precios de app alineados al mercado.',
    ),
    AdminGuiaIds.promos: AdminGuiaEntry(
      titulo: 'Promociones',
      paraQue: 'Crear y administrar promociones MxK u ofertas.',
      pasos: [
        'Creá o editá una promo.',
        'Activá / desactivá según campaña.',
      ],
      resultado: 'Promos visibles para clientes según reglas.',
    ),
    AdminGuiaIds.reportes: AdminGuiaEntry(
      titulo: 'Reportes y estadísticas',
      paraQue: 'Consultar quejas, calificaciones y exportar CSV.',
      pasos: [
        'Elegí el tipo de reporte.',
        'Filtrá fechas si aplica.',
        'Exportá si necesitás auditoría.',
      ],
      resultado: 'Datos para decisiones y soporte.',
    ),
    AdminGuiaIds.incidencias: AdminGuiaEntry(
      titulo: 'Gestión de incidencias',
      paraQue: 'Atender tickets de soporte (no es la estrella del viaje).',
      pasos: [
        'Abrí tickets abiertos.',
        'Respondé / cerrá con estado.',
      ],
      resultado: 'Soporte a clientes y choferes al día.',
    ),
    AdminGuiaIds.auditoria: AdminGuiaEntry(
      titulo: 'Auditoría e historial',
      paraQue: 'Ver cambios de configuración y log del sistema.',
      pasos: [
        'Buscá por fecha o tipo de evento.',
        'Usá para investigar «quién cambió qué».',
      ],
      resultado: 'Trazabilidad interna de Admin.',
    ),
    AdminGuiaIds.configRai: AdminGuiaEntry(
      titulo: 'Configuración RAI',
      paraQue: 'Cuenta bancaria, datos de empresa y parámetros de prepago.',
      pasos: [
        'Actualizá datos bancarios visibles a choferes.',
        'Revisá umbrales de prepago.',
        'Guardá.',
      ],
      resultado: 'Choferes saben a dónde transferir; reglas de prepago claras.',
    ),
    AdminGuiaIds.expedientes: AdminGuiaEntry(
      titulo: 'Expedientes choferes',
      paraQue:
          'Revisar documentos (licencia, vehículo, etc.) de choferes Normal / Motor / Bola.',
      pasos: [
        'Abrí pendientes de revisión.',
        'Aprobá o pedí corrección.',
        'No actives chofer sin papeles en regla.',
      ],
      resultado: 'Flota documentada y segura.',
    ),
    AdminGuiaIds.usuarios: AdminGuiaEntry(
      titulo: 'Gestionar usuarios',
      paraQue: 'Roles, bloqueos por prepago y movimientos de cuenta.',
      pasos: [
        'Buscá por correo o teléfono.',
        'Cambiá rol / desbloqueá / revisá historial.',
      ],
      resultado: 'Usuarios con permisos y estado correctos.',
    ),
    AdminGuiaIds.aprobarTurismo: AdminGuiaEntry(
      titulo: 'Aprobar solicitudes turismo',
      paraQue: 'Aprobar registro y documentos de choferes turísticos.',
      pasos: [
        'Revisá solicitud y papeles.',
        'Aprobá o rechazá.',
      ],
      resultado: 'Chofer turismo habilitado o rechazado con criterio.',
    ),
    AdminGuiaIds.controlTurismo: AdminGuiaEntry(
      titulo: 'Control turismo',
      paraQue: 'Ver pedidos turismo en vivo y mensajes con cliente.',
      pasos: [
        'Monitoreá pedidos activos.',
        'Intervení si hay demora o conflicto.',
      ],
      resultado: 'Turismo supervisado en tiempo real.',
    ),
    AdminGuiaIds.viajesTurismo: AdminGuiaEntry(
      titulo: 'Viajes Turismo — Asignación',
      paraQue: 'Asignar chofer a viaje turismo o liberar al pool.',
      pasos: [
        'Abrí la cola admin.',
        'Asigná chofer o liberá si no hay fijo.',
      ],
      resultado: 'Viaje turismo con chofer o en pool.',
    ),
    AdminGuiaIds.girasCupos: AdminGuiaEntry(
      titulo: 'Salidas por cupos',
      paraQue: 'Administrar giras / excursiones / grupos (viajes_pool).',
      pasos: [
        'Revisá estados y reservas.',
        'Corregí cupos o estados si hay error.',
      ],
      resultado: 'Salidas por cupos ordenadas.',
    ),
    AdminGuiaIds.desbloquearGiras: AdminGuiaEntry(
      titulo: 'Desbloquear salidas por cupos',
      paraQue: 'Liberar choferes/salidas bloqueados por la cola automática RAI.',
      pasos: [
        'Mirá la lista de bloqueados.',
        'Desbloqueá solo si ya se resolvió el motivo.',
      ],
      resultado: 'Chofer puede volver a publicar / operar cupos.',
    ),
    AdminGuiaIds.choferesTurismo: AdminGuiaEntry(
      titulo: 'Choferes Turismo',
      paraQue: 'Listado y gestión de choferes del módulo turismo.',
      pasos: [
        'Buscá chofer.',
        'Revisá estado operativo.',
      ],
      resultado: 'Directorio turismo actualizado.',
    ),
    AdminGuiaIds.destinosTurismo: AdminGuiaEntry(
      titulo: 'Destinos turismo',
      paraQue: 'Mantener el catálogo de destinos en Firestore.',
      pasos: [
        'Agregá o editá destino.',
        'Guardá para que salga en la app.',
      ],
      resultado: 'Catálogo de destinos al día.',
    ),
    AdminGuiaIds.rutasCorp: AdminGuiaEntry(
      titulo: 'Rutas corporativas (empresa)',
      paraQue: 'Ver y apoyar rutas/plantillas de una empresa desde Admin.',
      pasos: [
        'Revisá plantillas y chofer asignado.',
        'Corregí solo si el encargado no puede.',
      ],
      resultado: 'Rutas B2B coherentes con operación.',
    ),
    AdminGuiaIds.asignarTurismo: AdminGuiaEntry(
      titulo: 'Asignar viaje turismo',
      paraQue: 'Elegir chofer concreto para un viaje turismo.',
      pasos: [
        'Seleccioná chofer disponible.',
        'Confirmá asignación.',
      ],
      resultado: 'Viaje turismo asignado.',
    ),
  };

  static AdminGuiaEntry? of(String? id) {
    if (id == null || id.isEmpty) return null;
    return _map[id];
  }

  static void mostrarDialogo(BuildContext context, String guiaId) {
    final g = of(guiaId);
    if (g == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Cómo se usa · ${g.titulo}',
            style: TextStyle(
              color: AdminUi.onCard(ctx),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¿Para qué es?',
                  style: TextStyle(
                    color: AdminUi.onCard(ctx),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  g.paraQue,
                  style: TextStyle(
                    color: AdminUi.secondary(ctx),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Qué hacer',
                  style: TextStyle(
                    color: AdminUi.onCard(ctx),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                ...g.pasos.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key + 1}. ',
                          style: TextStyle(
                            color: AdminUi.accentGreen(ctx),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.value,
                            style: TextStyle(
                              color: AdminUi.secondary(ctx),
                              height: 1.35,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Text(
                  'Qué lográs',
                  style: TextStyle(
                    color: AdminUi.onCard(ctx),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  g.resultado,
                  style: TextStyle(
                    color: AdminUi.secondary(ctx),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }
}

/// Franja bajo el AppBar: resumen + botón «Ver guía».
class AdminGuiaBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminGuiaBar({super.key, required this.guiaId, this.extra});

  final String guiaId;
  final PreferredSizeWidget? extra;

  @override
  Size get preferredSize {
    final extraH = extra?.preferredSize.height ?? 0;
    return Size.fromHeight(40 + extraH);
  }

  @override
  Widget build(BuildContext context) {
    final g = AdminGuiaCatalogo.of(guiaId);
    if (g == null) {
      return extra ?? const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AdminUi.infoFill(context),
          child: InkWell(
            onTap: () => AdminGuiaCatalogo.mostrarDialogo(context, guiaId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 18,
                    color: AdminUi.accentGreen(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      g.paraQue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AdminUi.secondary(context),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        AdminGuiaCatalogo.mostrarDialogo(context, guiaId),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Ver guía',
                      style: TextStyle(
                        color: AdminUi.accentGreen(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (extra != null) extra!,
      ],
    );
  }
}
