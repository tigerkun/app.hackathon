import 'package:flutter/material.dart';
import '../widgets/map_placeholder.dart';
import '../widgets/glass_container.dart';
import '../theme/app_colors.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String _selectedType = "Theft";

  // Optimization: Static const list avoids re-allocations on widget rebuilds
  static const List<Map<String, dynamic>> _incidents = [
    {"label": "Theft", "icon": Icons.shopping_bag},
    {"label": "Harassment", "icon": Icons.person_off},
    {"label": "Accident", "icon": Icons.car_crash},
    {"label": "Suspicious", "icon": Icons.visibility},
  ];

  static const List<SafetyMarker> _mapMarkers = [
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// MAP BACKGROUND
          const MapPlaceholder(
            markers: _mapMarkers,
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
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                          itemCount: _incidents.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final item = _incidents[index];
                            final String label = item["label"] as String;
                            final IconData icon = item["icon"] as IconData;
                            final bool active = _selectedType == label;

                            return GestureDetector(
                              onTap: () {
                                if (_selectedType != label) {
                                  setState(() {
                                    _selectedType = label;
                                  });
                                }
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
                                      icon,
                                      color: AppColors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      label,
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
                      const Row(
                        children: [
                          Icon(Icons.location_on,
                              color: AppColors.teal),
                          SizedBox(width: 6),
                          Text(
                            "Using current location",
                            style: TextStyle(
                                color: AppColors.textSecondary),
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
                          onPressed: () {},
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
          )
        ],
      ),
    );
  }
}
