import 'package:flutter/material.dart';
import 'base_scaffold.dart';

class SafeRoutePage extends StatelessWidget {
  const SafeRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Safe Route Planner',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text(
              "AI-Suggested Safe Route",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                "✔ Avoids recent harassment reports\n"
                    "✔ Uses well-lit main roads\n"
                    "✔ Near police patrol zones\n\n"
                    "Safety Score: HIGH",
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "Why this route?",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            const Text(
              "- Community alert density is low\n"
                  "- Faster access to public spaces\n"
                  "- Reduced isolated stretches",
            ),
          ],
        ),
      ),
    );
  }
}
