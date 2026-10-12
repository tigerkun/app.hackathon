import 'package:flutter/material.dart';

class BaseScaffold extends StatefulWidget {
  final String title;
  final Widget body;

  const BaseScaffold({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  State<BaseScaffold> createState() => _BaseScaffoldState();
}

class _BaseScaffoldState extends State<BaseScaffold> {
  final bool isDarkMode = true;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF0B1220) : const Color(0xFFF4F6FA);
    final drawerColor = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          widget.title,
          style: TextStyle(color: textColor),
        ),
      ),

      // 🌟 COMMON DRAWER
      drawer: Drawer(
        backgroundColor: drawerColor,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Text(
                "SafeSphere",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),

            _DrawerItem(
              icon: Icons.home,
              text: "Home",
              onTap: () {
                Navigator.pushReplacementNamed(context, '/');
              },
            ),

            _DrawerItem(
              icon: Icons.report,
              text: "Report Near Me",
              onTap: () {
                Navigator.pushReplacementNamed(context, '/report');
              },
            ),

            _DrawerItem(
              icon: Icons.chat,
              text: "Community Chat",
              onTap: () {
                Navigator.pop(context); // close drawer FIRST
                Navigator.pushReplacementNamed(context, '/chat');
              },
            ),

            _DrawerItem(
              icon: Icons.warning,
              text: "Emergency",
              onTap: () {
                Navigator.pushReplacementNamed(context, '/emergency');
              },
            ),

            _DrawerItem(
              icon: Icons.info,
              text: "About",
              onTap: () {
                Navigator.pushReplacementNamed(context, '/about');
              },
            ),

            const Divider(),
          ],
        ),
      ),

      body: widget.body,
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(text),
      onTap: onTap,
    );
  }
}
