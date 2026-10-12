import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';

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
      drawer: const AppDrawer(),

      // 👇 PAGE CONTENT GOES HERE
      body: widget.body,
    );
  }
}
