import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/auth_state.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../pages/auth/login_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = AuthState();

    return ListenableBuilder(
      listenable: authState,
      builder: (context, _) {
        return Drawer(
          backgroundColor: AppColors.bgDark,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ===== DYNAMIC HEADER =====
              _buildHeader(context, authState),

              // ===== MENU ITEMS =====
              _drawerItem(
                context,
                icon: Icons.home,
                title: "Home",
                route: '/home',
              ),

              _drawerItem(
                context,
                icon: Icons.map,
                title: "Safety Map",
                route: '/safety-map',
              ),

              _drawerItem(
                context,
                icon: Icons.campaign,
                title: "Community Alerts",
                route: '/alerts',
              ),

              _drawerItem(
                context,
                icon: Icons.report,
                title: "Report Near Me",
                route: '/report',
              ),

              _drawerItem(
                context,
                icon: Icons.smart_toy,
                title: "AI Assistant",
                route: '/ai-assistant',
              ),

              _drawerItem(
                context,
                icon: Icons.share_location,
                title: "Share Location",
                route: '/share',
              ),

              _drawerItem(
                context,
                icon: Icons.my_location,
                title: "Watch Live Trip",
                route: '/track',
              ),

              _drawerItem(
                context,
                icon: Icons.warning_amber,
                title: "Emergency",
                route: '/emergency',
              ),

              const Divider(color: AppColors.border),

              _drawerItem(
                context,
                icon: Icons.info_outline,
                title: "About",
                route: '/about',
              ),

                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.teal),
                  title: const Text('Privacy & Consent (DPDP)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPrivacyConsentDialog(context, authState);
                  },
                ),
                if (authState.isAuthenticated)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined, color: AppColors.teal),
                    title: const Text('Who can see me', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Privacy hub — every channel open right now', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.privacyHub);
                    },
                  ),

              SwitchListTile(
                secondary: const Icon(Icons.sensors, color: AppColors.teal),
                title: const Text('Emergency Gestures', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Volume-down hold & shake-to-SOS', style: TextStyle(color: Colors.white60, fontSize: 12)),
                value: authState.emergencyGesturesEnabled,
                activeColor: AppColors.teal,
                onChanged: (val) async {
                  try {
                    HapticFeedback.selectionClick();
                  } catch (_) {}
                  await authState.setEmergencyGestures(val);
                },
              ),

              SwitchListTile(
                secondary: const Icon(Icons.phone_in_talk_outlined, color: AppColors.teal),
                title: const Text('Discreet Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Fake call screen & muted SOS visuals (UI-level)', style: TextStyle(color: Colors.white60, fontSize: 12)),
                value: authState.isDiscreetMode,
                activeColor: AppColors.teal,
                onChanged: (val) async {
                  try {
                    HapticFeedback.selectionClick();
                  } catch (_) {}
                  await authState.setDiscreetMode(val);
                },
              ),

              // ===== AUTHENTICATED CITIZEN SECURITY OPTIONS =====
              if (authState.isAuthenticated) ...[
                const Divider(color: AppColors.border),
                if (authState.isPrivileged) ...[
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined, color: AppColors.teal),
                    title: const Text('Review Markers (Admin)', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.reviewMarkers);
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.contact_phone_outlined, color: AppColors.teal),
                  title: const Text('Emergency Contacts', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showContactsDialog(context, authState);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_outlined, color: AppColors.teal),
                  title: const Text('My Circle (Trusted People)', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Safe ID, watchers & scoped live views', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, AppRoutes.circle);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_clock_outlined, color: AppColors.teal),
                  title: const Text('PIN & Biometric Lock', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, AppRoutes.pinLock);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.red),
                  title: const Text('Logout', style: TextStyle(color: AppColors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    await authState.logout();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged out from SafeSphere.')),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AuthState authState) {
    if (authState.isAuthenticated && authState.currentUser != null) {
      final user = authState.currentUser!;
      final contactPhone = user.emergencyContactPhone ??
          (user.emergencyContacts.isNotEmpty ? user.emergencyContacts.first.phone : 'Not set');

      return UserAccountsDrawerHeader(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        currentAccountPicture: CircleAvatar(
          backgroundColor: AppColors.teal,
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        accountName: Row(
          children: [
            Flexible(
              child: Text(
                user.name.isNotEmpty ? user.name : 'Verified Citizen',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.verified, color: AppColors.teal, size: 16),
          ],
        ),
        accountEmail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.email.isNotEmpty ? user.email : user.phone,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (user.safeId != null && user.safeId!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Safe ID: ${user.safeId}',
                style: const TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              'Emergency Contact: $contactPhone',
              style: const TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    } else {
      // Guest or Unauthenticated Header
      return DrawerHeader(
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
        ),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.amber, size: 36),
                  Icon(Icons.account_circle, color: Colors.white70, size: 28),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "SafeSphere",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                "Guest Mode - Limited protection active",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRoutes.login);
                },
                icon: const Icon(Icons.login, size: 16),
                label: const Text("Sign In / Setup PIN"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.black87,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showContactsDialog(BuildContext context, AuthState authState) {
    final user = authState.currentUser;
    final contact = user?.emergencyContactPhone ?? '112 (National Helpline)';
    final contactName = user?.emergencyContactName ?? 'National Emergency';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDark,
        title: const Text('Emergency Contacts', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_in_talk, color: AppColors.red),
              title: Text(contactName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(contact, style: const TextStyle(color: AppColors.amber)),
              trailing: const Icon(Icons.call, color: AppColors.teal, size: 20),
              onTap: () async {
                final cleanPhone = contact.replaceAll(RegExp(r'[^0-9+]'), '');
                final uri = Uri.parse('tel:$cleanPhone');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cannot initiate call to $contact')),
                    );
                  }
                }
              },
            ),
            const Divider(color: AppColors.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent, color: AppColors.teal),
              title: const Text('National Emergency Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('112', style: TextStyle(color: AppColors.teal)),
              trailing: const Icon(Icons.call, color: AppColors.teal, size: 20),
              onTap: () async {
                final uri = Uri.parse('tel:112');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppColors.teal)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyConsentDialog(BuildContext context, AuthState authState) {
    final consentVersion = authState.consentVersion ?? '1.0';
    final consentTime = authState.consentTimestamp != null
        ? authState.consentTimestamp!.replaceFirst('T', ' ').split('.').first
        : 'Recorded on initial consent';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.privacy_tip, color: AppColors.teal, size: 22),
            SizedBox(width: 8),
            Text('Privacy & DPDP Consent', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Compliance with India DPDP Act 2023",
              style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              "• Policy Version: $consentVersion (Active)\n"
              "• Consent Timestamp: $consentTime\n"
              "• Processing Scope: Location and contacts strictly for emergency dispatch and guardian tracking.\n"
              "• Data Retention: You have the right to erase all account records and live telemetry at any time.",
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text(
              "Danger Zone",
              style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            if (authState.isAuthenticated) ...[
              const Text(
                "Delete your SafeSphere account and erase all associated sessions, alerts, and tracking data from backend servers.",
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                ),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text("Delete My Account"),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showDeleteAccountConfirm(context, authState);
                },
              ),
            ] else ...[
              const Text(
                "Clear all cached local session data, emergency tracking tokens, and privacy consent records on this device.",
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.amber,
                  side: const BorderSide(color: AppColors.amber),
                ),
                icon: const Icon(Icons.cleaning_services, size: 18),
                label: const Text("Clear Local Data & Telemetry"),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await authState.clearLocalData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local data and telemetry cleared.')),
                  );
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await authState.completeOnboarding(consentVersion: '1.0');
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('DPDP Privacy consent updated (Policy v1.0)')),
              );
            },
            child: const Text('Re-consent (v1.0)', style: TextStyle(color: AppColors.teal)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirm(BuildContext context, AuthState authState) {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Confirm Account Erasure', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This action is permanent and cannot be undone. All your emergency alerts, sessions, and live tracking records will be permanently erased.",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Enter Security PIN (if configured)",
                labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                counterText: "",
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.red)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () async {
              final pin = pinController.text.trim();
              Navigator.pop(ctx);
              final success = await authState.deleteAccount(pin: pin.isNotEmpty ? pin : null);
              if (!context.mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account and data deleted successfully.')),
                );
                Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete account. Check PIN and network.')),
                );
              }
            },
            child: const Text('Delete Account', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ===== DRAWER TILE BUILDER =====
  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context); // close drawer
        Navigator.pushNamed(context, route);
      },
    );
  }
}
