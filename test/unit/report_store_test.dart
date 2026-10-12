import 'package:flutter_test/flutter_test.dart';
import 'package:newhere/data/report_store.dart';
import 'package:newhere/models/report_model.dart';

void main() {
  group('ReportStore Unit Tests', () {
    setUp(() {
      ReportStore.clear();
    });

    test('Initial store is empty', () {
      expect(ReportStore.total, equals(0));
      expect(ReportStore.countByStatus(ReportStatus.pending), equals(0));
      expect(ReportStore.countByStatus(ReportStatus.approved), equals(0));
      expect(ReportStore.countByStatus(ReportStatus.rejected), equals(0));
    });

    test('Adding reports updates count and cached status mapping', () {
      final report1 = Report(
        id: '1',
        type: 'Theft',
        location: 'Main St',
        description: 'Stolen phone',
        time: DateTime.now(),
        status: ReportStatus.pending,
      );

      final report2 = Report(
        id: '2',
        type: 'Harassment',
        location: 'Park',
        description: 'Verbal harassment',
        time: DateTime.now(),
        status: ReportStatus.approved,
      );

      ReportStore.addReport(report1);
      ReportStore.addReport(report2);

      expect(ReportStore.total, equals(2));
      expect(ReportStore.countByStatus(ReportStatus.pending), equals(1));
      expect(ReportStore.countByStatus(ReportStatus.approved), equals(1));
      expect(ReportStore.countByStatus(ReportStatus.rejected), equals(0));
    });
  });
}
