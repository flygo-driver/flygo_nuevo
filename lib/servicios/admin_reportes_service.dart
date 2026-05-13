import 'package:cloud_functions/cloud_functions.dart';

class AdminReportResult {
  final String reportType;
  final String path;
  final String downloadUrl;
  final int expiresAt;

  const AdminReportResult({
    required this.reportType,
    required this.path,
    required this.downloadUrl,
    required this.expiresAt,
  });
}

class AdminReportesService {
  static final FirebaseFunctions _fx = FirebaseFunctions.instance;

  static Future<AdminReportResult> generarCsv({
    required String reportType,
    required DateTime from,
    required DateTime to,
  }) async {
    final callable = _fx.httpsCallable('generateAdminReport');
    final r = await callable.call(<String, dynamic>{
      'reportType': reportType,
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    final m = (r.data as Map).cast<String, dynamic>();
    return AdminReportResult(
      reportType: (m['reportType'] ?? '').toString(),
      path: (m['path'] ?? '').toString(),
      downloadUrl: (m['downloadUrl'] ?? '').toString(),
      expiresAt: ((m['expiresAt'] ?? 0) as num).toInt(),
    );
  }
}
