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
        // El botón atrás NUNCA cierra la app: primero cierra los paneles
        // del browser (menú ⋮, pestañas, ajustes, historial); si no hay
        // paneles y el browser está abierto lo cierra (web intacta); si
        // no, se queda en la app.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          final tabs = BrowserTabs.instance;
          if (tabs.closePanels?.call() == true) return;
          if (tabs.isOpen) {
            tabs.closeBrowser();
          }
        },
        child: const HomePage(),
      ),
    );
  }
}
