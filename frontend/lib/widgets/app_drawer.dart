import 'package:flutter/material.dart';
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

              // ===== AUTHENTICATED CITIZEN SECURITY OPTIONS =====
              if (authState.isAuthenticated) ...[
                const Divider(color: AppColors.border),
                ListTile(
                  leading: const Icon(Icons.contact_phone_outlined, color: AppColors.teal),
                  title: const Text('Emergency Contacts', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showContactsDialog(context, authState);
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
            ),
            const Divider(color: AppColors.border),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.support_agent, color: AppColors.teal),
              title: Text('National Emergency Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('112', style: TextStyle(color: AppColors.teal)),
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
