import 'package:flutter/material.dart';

import '../core/terms.dart';
import '../theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Use')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: SelectableText(
            termsText,
            style: TextStyle(color: p.text, fontSize: 14.5, height: 1.5),
          ),
        ),
      ),
    );
  }
}
