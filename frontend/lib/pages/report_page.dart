import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/auth_state.dart';
import '../data/report_store.dart';
import '../models/report_model.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import '../widgets/map_placeholder.dart';
import '../widgets/glass_container.dart';
import '../theme/app_colors.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  /// Detects supported image MIME subtype ('jpeg' or 'png') from magic bytes.
  static String? detectImageMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    return null;
  }

  /// Downscales an image in-memory using `dart:ui` until its PNG encoding fits
  /// within [maxBytes], or returns `null` if it cannot fit / decode.
  static Future<Uint8List?> downscaleToPngUnderLimit(
    Uint8List bytes, {
    int maxBytes = 500 * 1024,
  }) async {
    for (final targetWidth in const [720, 512, 360, 256]) {
      ui.Codec? codec;
      ui.FrameInfo? frame;
      try {
        codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
        frame = await codec.getNextFrame();
        final byteData =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          if (pngBytes.length <= maxBytes) {
            return pngBytes;
          }
        }
      } catch (_) {
        // Ignore and fall through if undecodable or width step fails.
      } finally {
        frame?.image.dispose();
        codec?.dispose();
      }
    }
    return null;
  }

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
  bool _isLocating = false;
  bool _aadhaarPrompted = false;
  String? _photoBase64;
  Uint8List? _photoBytes;
  final ImagePicker _imagePicker = ImagePicker();

  final List<Map<String, dynamic>> incidents = const [
    // Crime & Threats
    {"label": "Theft", "icon": Icons.shopping_bag, "group": "Crime"},
    {"label": "Harassment", "icon": Icons.person_off, "group": "Crime"},
    {"label": "Assault", "icon": Icons.gpp_bad, "group": "Crime"},
    {"label": "Suspicious", "icon": Icons.visibility, "group": "Crime"},
    // Infrastructure & Hazards
    {"label": "Dark Area", "icon": Icons.lightbulb_outline, "group": "Infra"},
    {"label": "Road Hazard", "icon": Icons.construction, "group": "Infra"},
    {"label": "Flooding", "icon": Icons.water_drop_outlined, "group": "Infra"},
    {"label": "Transit Issue", "icon": Icons.directions_bus_outlined, "group": "Infra"},
    {"label": "Accident", "icon": Icons.car_crash, "group": "Infra"},
    {"label": "Other", "icon": Icons.warning_amber_rounded, "group": "Infra"},
  ];

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation({bool forceFreshGps = false}) async {
    if (mounted) setState(() => _isLocating = true);
    final loc = LocationService.instance;
    if (!forceFreshGps && (loc.isManualOverride || loc.hasLiveGps)) {
      if (mounted) {
        setState(() {
          _latitude = loc.currentLat;
          _longitude = loc.currentLng;
          _locationTag = "${loc.locationLabel} (${loc.currentLat.toStringAsFixed(4)}, ${loc.currentLng.toStringAsFixed(4)})";
          _isLocating = false;
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
        _isLocating = false;
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
          _isLocating = false;
        });
      } else if (mounted) {
        setState(() {
          _locationTag = loc.lastLocationError ?? "GPS unavailable — tap to choose location";
          _isLocating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationTag = loc.lastLocationError ?? "GPS unavailable — tap to choose location";
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _showPhotoSourceSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.teal),
              title: const Text("Take Photo with Camera", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.amber),
              title: const Text("Choose Photo from Gallery", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (picked == null || !mounted) return;
      Uint8List bytes = await picked.readAsBytes();
      String? mime = ReportPage.detectImageMime(bytes);
      if (bytes.length > 500 * 1024 || mime == null) {
        final downscaled = await ReportPage.downscaleToPngUnderLimit(
          bytes,
          maxBytes: 500 * 1024,
        );
        if (!mounted) return;
        if (downscaled == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Image exceeds 500KB limit after compression. Please pick a smaller image."),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        bytes = downscaled;
        mime = 'png';
      }
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoBase64 = 'data:image/$mime;base64,${base64Encode(bytes)}';
      });
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Photo picker unavailable on this platform — you can still submit without a photo."),
          backgroundColor: Colors.orange,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not attach photo (${e.message ?? e.code})."),
          backgroundColor: Colors.orange,
        ),
      );
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
    if (!authService.isAuthenticated) {
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

    if (authService.currentUser?.banned == true || AuthState().isBanned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "This account is banned from community submissions after repeated false reports."),
          backgroundColor: Colors.redAccent,
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

    // Combine landmark detail + live GPS coordinates so every report has a
    // human-readable place tag alongside precise pin coordinates.
    final hasGpsFix = _latitude != null && _longitude != null;
    final manualLocation = _manualLocationController.text.trim();
    final String locationPayload;
    if (hasGpsFix && manualLocation.isNotEmpty) {
      final raw = "$manualLocation (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})";
      locationPayload = raw.length > 200 ? raw.substring(0, 200) : raw;
    } else if (hasGpsFix) {
      final areaLabel = LocationService.instance.locationLabel;
      final raw = "$areaLabel (${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)})";
      locationPayload = raw.length > 200 ? raw.substring(0, 200) : raw;
    } else {
      locationPayload = manualLocation;
    }
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
                          "Category (Crimes & Infrastructure)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Anonymous per thread • >=70% votes or Admin verified: +10 Karma | Rejected: -20 Karma",
                          style: TextStyle(color: AppColors.teal, fontSize: 11),
                        ),
                        if (AuthState().isBanned ||
                            AuthService.instance.currentUser?.banned == true) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.redAccent.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.block,
                                    color: Colors.redAccent, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Account restricted from community reports due to repeated rejected submissions. Emergency SOS remains available.",
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),

                        /// INCIDENT SELECTOR
                        SizedBox(
                          height: 50,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: incidents.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final item = incidents[index];
                              final bool active = selectedType == item["label"];
                              final Color chipAccent = item["group"] == "Crime"
                                  ? AppColors.amber
                                  : AppColors.teal;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedType = item["label"] as String;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? chipAccent.withValues(alpha: 0.22)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: active ? chipAccent : Colors.white24,
                                      width: active ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item["icon"] as IconData,
                                        color: chipAccent,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        item["label"] as String,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
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

                        /// LOCATION INFO (tappable to change or refresh live GPS)
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
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
                                        color: _latitude != null ? AppColors.teal : AppColors.amber,
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
                            ),
                            IconButton(
                              icon: _isLocating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                                    )
                                  : const Icon(Icons.my_location, color: AppColors.teal, size: 18),
                              tooltip: "Refresh live GPS",
                              onPressed: _isLocating ? null : () => _detectLocation(forceFreshGps: true),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        TextField(
                          controller: _manualLocationController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: _latitude == null
                                ? "Landmark / area name *"
                                : "Street / landmark detail (optional)",
                            hintText: "e.g. MG Road near City Mall, dark underpass",
                            labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                            enabledBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.teal),
                            ),
                          ),
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
                            label: const Text("Attach Photo (Optional, ≤500KB)"),
                            onPressed: _showPhotoSourceSheet,
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
                                if (_photoBytes != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      _photoBytes!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  const Icon(Icons.check_circle, color: AppColors.teal, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _photoBytes != null
                                        ? "Photo attached (${(_photoBytes!.length / 1024).toStringAsFixed(0)} KB)"
                                        : "Photo attached (≤500KB)",
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                                  tooltip: "Remove photo",
                                  onPressed: () {
                                    setState(() {
                                      _photoBase64 = null;
                                      _photoBytes = null;
                                    });
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
    bool isLinking = false;
    String? inlineError;
    // Dispose the dialog-local controller when the dialog closes — leaking it
    // keeps the text field's listeners alive after the route is gone.
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
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
                enabled: !isLinking,
                decoration: const InputDecoration(
                  labelText: "Aadhaar last 4 digits",
                  counterText: "",
                  border: OutlineInputBorder(),
                ),
              ),
              if (inlineError != null) ...[
                const SizedBox(height: 8),
                Text(
                  inlineError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                "Optional — you can skip this and still file your report.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLinking ? null : () => Navigator.of(ctx).pop(false),
              child: const Text("Skip"),
            ),
            TextButton(
              onPressed: isLinking ? null : () => Navigator.of(ctx).pop(null),
              child: const Text("Cancel report"),
            ),
            ElevatedButton(
              onPressed: isLinking
                  ? null
                  : () async {
                      final last4 = last4Controller.text.trim();
                      if (last4.length != 4 || int.tryParse(last4) == null) {
                        setDialogState(() {
                          inlineError = "Enter exactly 4 digits.";
                        });
                        return;
                      }
                      setDialogState(() {
                        isLinking = true;
                        inlineError = null;
                      });
                      final ok =
                          await AuthService.instance.linkAadhaarLast4(last4);
                      if (!ctx.mounted) return;
                      if (ok) {
                        AuthState().syncUserFromService();
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDialogState(() {
                          isLinking = false;
                          inlineError = AuthService.instance.lastAadhaarError ??
                              "Could not link verification digits. Retry or choose Skip.";
                        });
                      }
                    },
              child: isLinking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Link & continue"),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // Wait for the dialog exit transition to finish unmounting TextField
      // before disposing the controller.
      Future<void>.delayed(const Duration(milliseconds: 400), last4Controller.dispose);
    });
  }

}
