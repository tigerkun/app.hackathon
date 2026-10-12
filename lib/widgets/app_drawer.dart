import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: const [
          // ===== HEADER =====
          DrawerHeader(
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
          _DrawerItem(
            icon: Icons.home,
            title: "Home",
            route: '/home',
          ),
          _DrawerItem(
            icon: Icons.map,
            title: "Safety Map",
            route: '/safety-map',
          ),
          _DrawerItem(
            icon: Icons.report,
            title: "Report Near Me",
            route: '/report',
          ),
          _DrawerItem(
            icon: Icons.notifications,
            title: "Community Alerts",
            route: '/alerts',
          ),
          _DrawerItem(
            icon: Icons.smart_toy,
            title: "AI Safety Assistant",
            route: '/ai-assistant',
          ),
          _DrawerItem(
            icon: Icons.alt_route,
            title: "Safe Route Planner",
            route: '/safe-route',
          ),
          _DrawerItem(
            icon: Icons.share_location,
            title: "Share Location",
            route: '/share',
          ),
          _DrawerItem(
            icon: Icons.warning_amber,
            title: "Emergency",
            route: '/emergency',
          ),

          Divider(),

          _DrawerItem(
            icon: Icons.info_outline,
            title: "About",
            route: '/about',
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String route;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context); // close drawer
        final currentRoute = ModalRoute.of(context)?.settings.name;
        if (currentRoute != route) {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }
}
