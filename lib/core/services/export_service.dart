// lib/core/services/export_service.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ExportService {
  static Future<File> exportPayrollCSV(
    List<Map<String, dynamic>> rows,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln("Employee,Hours,Rate,Total");

    for (final r in rows) {
      buffer.writeln(
        "${r['name']},${r['hours']},${r['rate']},${r['total']}",
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/payroll.csv');

    await file.writeAsString(buffer.toString());

    return file;
  }
}