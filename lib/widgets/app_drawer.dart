import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [

          // ===== HEADER =====
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.shield, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text(
                  "SafeSphere",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Your personal safety companion",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),

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

          const Divider(),

          _drawerItem(
            context,
            icon: Icons.info_outline,
            title: "About",
            route: '/about',
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
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context); // close drawer
        Navigator.pushNamed(context, route);
      },
    );
  }
}
