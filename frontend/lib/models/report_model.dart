enum ReportStatus { pending, approved, rejected }

class Report {
  final String id;
  final String type;
  final String location;
  final String description;
  final DateTime time;
  final String? photoUrl;
  ReportStatus status;

  Report({
    required this.id,
    required this.type,
    required this.location,
    required this.description,
    required this.time,
    this.photoUrl,
    this.status = ReportStatus.pending,
  });
}
