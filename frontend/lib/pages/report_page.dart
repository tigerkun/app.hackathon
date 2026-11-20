import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/report_store.dart';
import '../models/report_model.dart';
import '../services/auth_service.dart';
import '../widgets/map_placeholder.dart';
import '../widgets/glass_container.dart';
import '../theme/app_colors.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  // Monotonic suffix keeps offline fallback IDs unique even when several
  // reports are submitted within the same millisecond.
  static int _localReportSeq = 0;

  String selectedType = "Theft";
  final TextEditingController _descriptionController = TextEditingController();
  String _locationTag = "Acquiring GPS location...";
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  String? _photoBase64;

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
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        if (mounted) {
          setState(() {
            _latitude = pos.latitude;
            _longitude = pos.longitude;
            _locationTag = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} (GPS Verified)";
          });
        }
        return;
      }
      // Try last known as fallback if permission was already granted before
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _latitude = last.latitude;
          _longitude = last.longitude;
          _locationTag = "${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)} (Last Known GPS)";
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationTag = "GPS unavailable — location will not be attached";
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
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

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);

    // 1. Submit to real backend via AuthService
    final authService = AuthService.instance;
    // Send clean "lat,lng" without the "(GPS Verified)" UI tag in backend payload
    final cleanPayloadLocation = (_latitude != null && _longitude != null)
        ? "${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}"
        : (_locationTag.contains('(') ? _locationTag.split('(').first.trim() : _locationTag);
    final backendReport = await authService.submitReport(
      type: selectedType,
      description: description,
      location: cleanPayloadLocation,
      latitude: _latitude,
      longitude: _longitude,
      photoBase64: _photoBase64,
    );

    // 2. Add to local cache for immediate in-app visibility
    final localReport = Report(
      id: backendReport?['id'] as String? ??
          "rep_${DateTime.now().millisecondsSinceEpoch}_${_localReportSeq++}",
      type: selectedType,
      location: _locationTag,
      description: description,
      time: DateTime.now(),
      photoUrl: _photoBase64,
      status: ReportStatus.pending,
    );
    ReportStore.addReport(localReport);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (backendReport != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Incident report submitted to SafeSphere network successfully."),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Report saved locally. Will sync when backend is reachable."),
            backgroundColor: Colors.orange,
          ),
        );
      }
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

                        const SizedBox(height: 14),

                        /// F5-4: PHOTO ATTACHMENT SECTION
                        if (_photoBase64 == null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.teal,
                              side: BorderSide(color: AppColors.teal.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                            label: const Text("Add Photo (Optional, ≤500KB)"),
                            onPressed: () {
                              // TODO(REAL_HARDWARE): Native gallery/camera pick requires image_picker or file_picker in pubspec.
                              // Attaches simulated JPEG base64 for functional testing.
                              setState(() {
                                _photoBase64 =
                                    "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=";
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Simulated hazard photo attached (≤500KB JPEG).")),
                              );
                            },
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.teal),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: AppColors.teal, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    "Photo attached (JPEG, ≤500KB)",
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                                  tooltip: "Remove photo",
                                  onPressed: () {
                                    setState(() => _photoBase64 = null);
                                  },
                                ),
                              ],
                            ),
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
                            onPressed: _isSubmitting ? null : _submitReport,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text(
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
