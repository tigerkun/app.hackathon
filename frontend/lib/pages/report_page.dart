import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/report_store.dart';
import '../models/report_model.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
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
  final TextEditingController _manualLocationController = TextEditingController();
  String _locationTag = "Acquiring GPS location...";
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  bool _aadhaarPrompted = false;
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
    final loc = LocationService.instance;
    if (loc.isManualOverride || loc.hasLiveGps) {
      if (mounted) {
        setState(() {
          _latitude = loc.currentLat;
          _longitude = loc.currentLng;
          _locationTag = "${loc.locationLabel} (${loc.currentLat.toStringAsFixed(4)}, ${loc.currentLng.toStringAsFixed(4)})";
        });
      }
      return;
    }

    final success = await loc.detectLiveGps();
    if (success && mounted) {
      setState(() {
        _latitude = loc.currentLat;
        _longitude = loc.currentLng;
        _locationTag = "${loc.locationLabel} (${loc.currentLat.toStringAsFixed(4)}, ${loc.currentLng.toStringAsFixed(4)})";
      });
      return;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _latitude = last.latitude;
          _longitude = last.longitude;
          _locationTag = "${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)} (Last Known GPS)";
        });
      } else if (mounted) {
        setState(() {
          _locationTag = "Tap to choose location";
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationTag = "Tap to choose location";
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _manualLocationController.dispose();
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

    // M2.1: community reports require an authenticated account — guests get
    // an honest sign-in gate instead of a fabricated submission.
    final authService = AuthService.instance;
    if (authService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Sign in with a verified account to submit community reports. "
              "Guests can view alerts but not report them."),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // M2.2: optional Aadhaar-lite abuse-prevention prompt on first report —
    // skipped when already linked. Only a salted hash is stored server-side.
    if (authService.currentUser!.aadhaarLinked == false && !_aadhaarPrompted) {
      _aadhaarPrompted = true;
      final linked = await _showAadhaarConsentDialog();
      if (linked == null) return; // user cancelled — abort submission
      if (linked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Abuse-prevention link saved (salted hash only — never readable)."),
            backgroundColor: Colors.teal,
          ),
        );
      }
      // linked == false → user skipped; continue without blocking the report
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);

    // Backend requires a non-empty location. With no GPS fix the user must
    // type a landmark/area — previously an empty string was sent, the API
    // returned 400, and the UI still claimed "backend unreachable".
    final hasGpsFix = _latitude != null && _longitude != null;
    final manualLocation = _manualLocationController.text.trim();
    final locationPayload = hasGpsFix
        ? "${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}"
        : manualLocation;
    if (locationPayload.isEmpty) {
      setState(() => _isSubmitting = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              "Add a landmark or area name — GPS is unavailable and the report needs a location."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 1. Submit to real backend via AuthService
    final backendReport = await authService.submitReport(
      type: selectedType,
      description: description,
      location: locationPayload,
      latitude: _latitude,
      longitude: _longitude,
      photoBase64: _photoBase64,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (backendReport != null) {
        // 2. Add to local cache only on CONFIRMED backend acceptance — a
        // failed submit must never look like a queued/sent report.
        final localReport = Report(
          id: backendReport['id'] as String? ??
              "rep_${DateTime.now().millisecondsSinceEpoch}_${_localReportSeq++}",
          type: selectedType,
          location: locationPayload,
          description: description,
          time: DateTime.now(),
          photoUrl: _photoBase64,
          status: ReportStatus.pending,
        );
        ReportStore.addReport(localReport);
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Incident report submitted to SafeSphere network successfully."),
            backgroundColor: Colors.green,
          ),
        );
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                "Report was NOT submitted: ${authService.lastReportError ?? 'backend unreachable — retry when connected.'}"),
            backgroundColor: Colors.redAccent,
          ),
        );
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
                  const Expanded(
                    child: Text(
                      "Report Incident",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
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

                        /// LOCATION INFO (tappable to change via LocationService)
                        InkWell(
                          onTap: () {
                            LocationService.showLocationPickerSheet(
                              context,
                              onLocationChanged: () {
                                final loc = LocationService.instance;
                                setState(() {
                                  _latitude = loc.currentLat;
                                  _longitude = loc.currentLng;
                                  _locationTag = "${loc.locationLabel} (${loc.currentLat.toStringAsFixed(4)}, ${loc.currentLng.toStringAsFixed(4)})";
                                });
                              },
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _latitude != null ? Icons.gps_fixed : Icons.edit_location_alt,
                                  color: AppColors.teal,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Tagged: $_locationTag",
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.teal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
                                  ),
                                  child: const Text(
                                    "Change",
                                    style: TextStyle(color: AppColors.teal, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // GPS unavailable → manual landmark is REQUIRED by the
                        // backend (location field is mandatory).
                        if (_latitude == null) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _manualLocationController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: "Landmark / area name *",
                              hintText: "e.g. MG Road, near City Mall",
                              labelStyle: TextStyle(color: Colors.white60),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppColors.teal),
                              ),
                            ),
                          ),
                        ],

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
                              // TODO(REAL_HARDWARE): Native gallery/camera pick requires
                              // image_picker or file_picker in pubspec. Until then we must
                              // NEVER submit a synthetic/placeholder image as evidence.
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Photo attachment isn't available in this build yet — submit without a photo."),
                                  backgroundColor: Colors.orange,
                                ),
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

  /// M2.2: consent dialog — returns true (linked), false (skipped), or
  /// null (cancelled/aborted the report). Plaintext digits never persisted;
  /// only a salted SHA-256 hash goes to the server.
  Future<bool?> _showAadhaarConsentDialog() {
    final last4Controller = TextEditingController();
    // Dispose the dialog-local controller when the dialog closes — leaking it
    // keeps the text field's listeners alive after the route is gone.
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Prevent fake reports",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Help us keep SafeSphere trustworthy. Provide the last 4 digits "
              "of your Aadhaar number — stored ONLY as a keyed hash that "
              "cannot be read back. A weak signal moderators use for abuse "
              "review — not verified identity.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: last4Controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Aadhaar last 4 digits",
                counterText: "",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Optional — you can skip this and still file your report.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Skip"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text("Cancel report"),
          ),
          ElevatedButton(
            onPressed: () async {
              final last4 = last4Controller.text.trim();
              if (last4.length != 4 || int.tryParse(last4) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Enter exactly 4 digits.")),
                );
                return;
              }
              final ok = await AuthService.instance.linkAadhaarLast4(last4);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(ok);
            },
            child: const Text("Link & continue"),
          ),
        ],
      ),
    ).whenComplete(() {
      // Wait for the dialog exit transition to finish unmounting TextField
      // before disposing the controller.
      Future<void>.delayed(const Duration(milliseconds: 400), last4Controller.dispose);
    });
  }

}
