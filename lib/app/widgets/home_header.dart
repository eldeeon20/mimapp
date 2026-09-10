import 'package:flutter/material.dart';

import '../../colab_cli/colab_dialog.dart';
import '../../toolsec/toolsec_dialog.dart';
import 'top_card.dart';

/// Fila superior del home: tarjetas COLAB y CIFRAR ARCHIVOS.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: TopCard(
                icon: Icons.people_alt_rounded,
                title: 'COLAB',
                subtitle: 'Colabora y comparte\nde forma segura',
                iconColor: Colors.deepPurpleAccent,
                onTap: () => showColabDialog(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TopCard(
                icon: Icons.lock_rounded,
                title: 'CIFRAR ARCHIVOS',
                subtitle: 'Protege tu información\ncon cifrado seguro',
                iconColor: Colors.lightBlueAccent,
                onTap: () => showToolSecDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
