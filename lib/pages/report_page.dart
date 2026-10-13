import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/report_store.dart';
import '../models/report_model.dart';
import '../widgets/map_placeholder.dart';
import '../widgets/glass_container.dart';
import '../theme/app_colors.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String selectedType = "Theft";
  final TextEditingController _descriptionController = TextEditingController();
  String _locationTag = "28.6139, 77.2090 (GPS Verified)";

  final incidents = const [
    {"label": "Theft", "icon": Icons.shopping_bag},
    {"label": "Harassment", "icon": Icons.person_off},
    {"label": "Accident", "icon": Icons.car_crash},
    {"label": "Suspicious", "icon": Icons.visibility},
  ];

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() {
          _locationTag = "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)} (GPS Verified)";
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _submitReport() {
    final description = _descriptionController.text;
    if (description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a description for the incident."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final newReport = Report(
      id: "rep_${DateTime.now().millisecondsSinceEpoch}",
      type: selectedType,
      location: _locationTag,
      description: description,
      time: DateTime.now(),
      status: ReportStatus.pending,
    );

    ReportStore.addReport(newReport);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Incident report submitted successfully"),
          backgroundColor: Colors.green,
        ),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          /// MAP BACKGROUND
          MapPlaceholder(
            markers: const [
              SafetyMarker(
                position: Offset(0.25, 0.35),
                icon: Icons.local_police,
                color: AppColors.blue,
                label: "Police",
              ),
              SafetyMarker(
                position: Offset(0.55, 0.45),
                icon: Icons.local_hospital,
                color: AppColors.red,
                label: "Hospital",
              ),
              SafetyMarker(
                position: Offset(0.7, 0.3),
                icon: Icons.security,
                color: AppColors.teal,
                label: "Safe Zone",
              ),
            ],
          ),



          /// TOP BAR
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    "Report Incident",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                ],
              ),
            ),
          ),

          /// BOTTOM GLASS PANEL
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 14,
                  bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: GlassContainer(
                  borderColor: AppColors.amber,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Incident Type",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),

                        /// INCIDENT SELECTOR
                        SizedBox(
                          height: 54,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: incidents.length,
                            separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final item = incidents[index];
                              final bool active =
                                  selectedType == item["label"];

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedType = item["label"] as String;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration:
                                  const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.amber
                                        .withValues(alpha: 0.18)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: active
                                          ? AppColors.amber
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item["icon"] as IconData,
                                        color: AppColors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        item["label"] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 14),

                        /// DESCRIPTION
                        TextField(
                          controller: _descriptionController,
                          maxLines: 3,
                          style:
                          const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText:
                            "Describe what happened...",
                            hintStyle: const TextStyle(
                                color: Colors.white38),
                            filled: true,
                            fillColor:
                            Colors.black.withValues(alpha: 0.25),
                            border: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        /// LOCATION INFO
                        Row(
                          children: [
                            const Icon(Icons.gps_fixed,
                                color: AppColors.teal, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Tagged Location: $_locationTag",
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          ],
                        ),

                        const SizedBox(height: 16),

                        /// SUBMIT BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.amber,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(16),
                              ),
                              elevation: 10,
                              shadowColor:
                              AppColors.amber.withValues(alpha: 0.5),
                            ),
                            onPressed: _submitReport,
                            child: const Text(
                              "Submit Report",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
