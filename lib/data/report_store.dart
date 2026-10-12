import '../models/report_model.dart';

class ReportStore {
  static final List<Report> reports = [];
  // Cache count by status for O(1) lookup instead of O(N) linear scanning
  static final Map<ReportStatus, int> _statusCounts = {};

  static void addReport(Report report) {
    reports.add(report);
    _statusCounts[report.status] = (_statusCounts[report.status] ?? 0) + 1;
  }

  static int get total => reports.length;

  static int countByStatus(ReportStatus status) {
    // O(1) cached lookup
    return _statusCounts[status] ?? 0;
  }
}
