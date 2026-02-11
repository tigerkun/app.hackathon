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

            _drawerItem(Icons.home, "Home", () {
              Navigator.pushReplacementNamed(context, '/');
            }),

            _drawerItem(Icons.report, "Report Near Me", () {
              Navigator.pushReplacementNamed(context, '/report');
            }),

            _drawerItem(Icons.chat, "Community Chat", () {
              Navigator.pop(context); // close drawer FIRST
              Navigator.pushReplacementNamed(context, '/chat');
            }),


            _drawerItem(Icons.warning, "Emergency", () {
              Navigator.pushReplacementNamed(context, '/emergency');
            }),

            _drawerItem(Icons.info, "About", () {
              Navigator.pushReplacementNamed(context, '/about');
            }),

            const Divider(),

          ],
        ),
      ),

      // 👇 PAGE CONTENT GOES HERE
      body: widget.body,
    );
  }

  ListTile _drawerItem(
      IconData icon, String text, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(text),
      onTap: onTap,
    );
  }
}
