import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

/// Scrollable legal text page (privacy, terms, etc.).
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.xl),
            SectionLabel(sections[i].heading),
            const SizedBox(height: AppSpace.md),
            GlassCard(
              child: Text(
                sections[i].body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LegalSection {
  const LegalSection({required this.heading, required this.body});
  final String heading;
  final String body;
}