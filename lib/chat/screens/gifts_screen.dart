import 'package:flutter/material.dart';

import '../account.dart';
import '../mock_server.dart';
import '../models.dart';
import 'chat_list_screen.dart';

/// Tienda de gifts: grid de regalos que se compran con coins simuladas.
class GiftsScreen extends StatelessWidget {
  const GiftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final server = MockServer.instance;
    return AnimatedBuilder(
      animation: Account.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: Tg.bg,
        appBar: AppBar(
          backgroundColor: Tg.panel,
          title: const Text('Gifts'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('💎 ${Account.instance.coins}',
                    style: const TextStyle(
                        color: Tg.accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        body: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
              childAspectRatio: .95),
          itemCount: server.gifts.length,
          itemBuilder: (_, i) => _gift(context, server.gifts[i]),
        ),
      ),
    );
  }

  Widget _gift(BuildContext context, Gift g) => Container(
        decoration: BoxDecoration(
          color: Tg.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tg.accent.withValues(alpha: .25)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(g.emoji, style: const TextStyle(fontSize: 46)),
          const SizedBox(height: 6),
          Text(g.nombre,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('💎 ${g.precio}',
              style: const TextStyle(color: Tg.subtitulo, fontSize: 12.5)),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Tg.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(110, 34),
            ),
            onPressed: () => _comprar(context, g),
            child: const Text('Enviar'),
          ),
        ]),
      );

  void _comprar(BuildContext context, Gift g) {
    final ok = Account.instance.comprar(g);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '${g.emoji} ${g.nombre} enviado al chat de ejemplo'
          : 'No te alcanzan las coins para ${g.nombre} (💎${g.precio})'),
      backgroundColor: ok ? Tg.accent : Colors.redAccent,
    ));
  }
}
