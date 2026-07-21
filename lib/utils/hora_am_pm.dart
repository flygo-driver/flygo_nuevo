import 'package:flutter/material.dart';

/// Reloj 12 h con AM/PM (evita confusión 09:00 vs 21:00).
String fmtHoraAmPm(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $ampm';
}

/// Normaliza cualquier hora corporativa a `"HH:mm"` 24 h.
/// Acepta `7:00`, `07:00`, `07:00:00`, `7:00 AM`, `7:00PM`.
String? normalizarHoraHHmm(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  var esPm = false;
  var esAm = false;
  final upper = s.toUpperCase();
  if (upper.contains('PM')) {
    esPm = true;
    s = s.replaceAll(RegExp(r'\s*[AaPp][Mm]\s*'), '').trim();
  } else if (upper.contains('AM')) {
    esAm = true;
    s = s.replaceAll(RegExp(r'\s*[AaPp][Mm]\s*'), '').trim();
  }

  final parts = s.split(RegExp(r'[:.]'));
  if (parts.length < 2) return null;
  var h = int.tryParse(parts[0].trim());
  final mRaw = parts[1].trim();
  final mMatch = RegExp(r'^(\d{1,2})').firstMatch(mRaw);
  final m = mMatch != null ? int.tryParse(mMatch.group(1)!) : null;
  if (h == null || m == null) return null;
  if (m < 0 || m > 59) return null;

  if (esPm || esAm) {
    if (h < 1 || h > 12) return null;
    if (esPm && h < 12) h += 12;
    if (esAm && h == 12) h = 0;
  } else if (h < 0 || h > 23) {
    return null;
  }

  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// `"HH:mm"` (24 h) — para chofer corporativo (nunca AM/PM).
String fmtHoraStr24(String raw) => normalizarHoraHHmm(raw) ?? raw.trim();

String fmtHoraDeDateTime24(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// `lun 11 jul · 16:50` (24 h, sin AM/PM).
String fmtFechaHora24(
  DateTime dt, {
  bool conAnio = false,
  String sep = '·',
}) {
  const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  final dia = dias[dt.weekday - 1];
  final mes = meses[dt.month - 1];
  final hora = fmtHoraDeDateTime24(dt);
  if (conAnio) {
    return '$dia ${dt.day} $mes ${dt.year} $sep $hora';
  }
  return '$dia ${dt.day} $mes $sep $hora';
}

/// Convierte `"HH:mm"` (24 h) a texto `7:00 AM` (UI encargado; storage sigue 24h).
String fmtHoraStrAmPm(String raw) {
  final norm = normalizarHoraHHmm(raw);
  if (norm == null) return raw;
  final parts = norm.split(':');
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  return fmtHoraAmPm(TimeOfDay(hour: h, minute: m));
}

String fmtHoraDeDateTimeAmPm(DateTime dt) =>
    fmtHoraAmPm(TimeOfDay.fromDateTime(dt));

/// `lun 11 jul · 7:00 AM` — con año: `lun 11 jul 2026 · 7:00 AM`
String fmtFechaHoraAmPm(
  DateTime dt, {
  bool conAnio = false,
  String sep = '·',
}) {
  const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  final dia = dias[dt.weekday - 1];
  final mes = meses[dt.month - 1];
  final hora = fmtHoraDeDateTimeAmPm(dt);
  if (conAnio) {
    return '$dia ${dt.day} $mes ${dt.year} $sep $hora';
  }
  return '$dia ${dt.day} $mes $sep $hora';
}

/// `11 jul · 7:00 AM`
String fmtDiaMesHoraAmPm(DateTime dt, {String sep = '·'}) {
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${dt.day} ${meses[dt.month - 1]} $sep ${fmtHoraDeDateTimeAmPm(dt)}';
}

/// `11/07 7:00 AM`
String fmtDdMmHoraAmPm(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  return '$d/$m ${fmtHoraDeDateTimeAmPm(dt)}';
}

TimeOfDay _toTimeOfDay({
  required int hour12,
  required int minute,
  required bool isAm,
}) {
  var h = hour12 % 12;
  if (!isAm) h += 12;
  return TimeOfDay(hour: h, minute: minute.clamp(0, 59));
}

/// Selector propio: hora + minuto + botones AM/PM (siempre elegibles).
Future<TimeOfDay?> elegirHoraAmPm(
  BuildContext context, {
  required TimeOfDay initial,
  String helpText = 'Elegí la hora (AM / PM)',
  Widget Function(BuildContext context, Widget child)? wrapChild,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) {
      Widget dialog = _ElegirHoraAmPmDialog(
        initial: initial,
        helpText: helpText,
      );
      if (wrapChild != null) {
        dialog = wrapChild(ctx, dialog);
      }
      return dialog;
    },
  );
}

class _ElegirHoraAmPmDialog extends StatefulWidget {
  const _ElegirHoraAmPmDialog({
    required this.initial,
    required this.helpText,
  });

  final TimeOfDay initial;
  final String helpText;

  @override
  State<_ElegirHoraAmPmDialog> createState() => _ElegirHoraAmPmDialogState();
}

class _ElegirHoraAmPmDialogState extends State<_ElegirHoraAmPmDialog> {
  late int _hora12;
  late int _minuto;
  late bool _esAm;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _hora12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    _minuto = t.minute;
    _esAm = t.period == DayPeriod.am;
  }

  TimeOfDay get _actual => _toTimeOfDay(
        hour12: _hora12,
        minute: _minuto,
        isAm: _esAm,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.helpText,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fmtHoraAmPm(_actual),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hora',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _hora12,
                        isExpanded: true,
                        items: [
                          for (var h = 1; h <= 12; h++)
                            DropdownMenuItem(value: h, child: Text('$h')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _hora12 = v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _minuto,
                        isExpanded: true,
                        items: [
                          for (var m = 0; m < 60; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(m.toString().padLeft(2, '0')),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _minuto = v);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('AM'),
                    icon: Icon(Icons.wb_sunny_outlined, size: 18),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('PM'),
                    icon: Icon(Icons.nights_stay_outlined, size: 18),
                  ),
                ],
                selected: {_esAm},
                onSelectionChanged: (s) {
                  setState(() => _esAm = s.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.comfortable,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tocá AM o PM para cambiar el turno.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _actual),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
