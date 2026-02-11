import '../models/report_model.dart';

class ReportStore {
  static final List<Report> reports = [];

  static void addReport(Report report) {
    reports.add(report);
  }

  static int get total => reports.length;

  static int countByStatus(ReportStatus status) {
    return reports.where((r) => r.status == status).length;
  }
}
