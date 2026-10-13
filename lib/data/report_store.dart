import '../models/report_model.dart';

class ReportStore {
  static final List<Report> reports = [];
  static final Map<ReportStatus, int> _statusCounts = {};

  static void addReport(Report report) {
    reports.add(report);
    _statusCounts[report.status] = (_statusCounts[report.status] ?? 0) + 1;
  }

  static int get total => reports.length;

  static int countByStatus(ReportStatus status) {
    return _statusCounts[status] ?? 0;
  }

  static void clear() {
    reports.clear();
    _statusCounts.clear();
  }
}
