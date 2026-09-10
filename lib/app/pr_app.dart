import 'package:flutter/material.dart';

import '../browser/browser_tabs.dart';
import 'home_page.dart';

/// App principal: tema oscuro + HomePage.
class PrApp extends StatelessWidget {
  const PrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure App',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: PopScope(
        // El botón atrás NUNCA cierra la app: si el browser está abierto lo
        // cierra (web intacta); si no, se queda en la app.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (BrowserTabs.instance.isOpen) {
            BrowserTabs.instance.closeBrowser();
          }
        },
        child: const HomePage(),
      ),
    );
  }
}
