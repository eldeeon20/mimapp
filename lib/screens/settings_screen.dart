import 'package:flutter/material.dart';

import '../services/settings.dart';
import 'tor_test_screen.dart';

/// Menú de Configuración.
///
/// Única entrada funcional: "Mostrar URI en media" (persistida cifrada en
/// `config.pr`). El resto son placeholders sin lógica (la estructura queda
/// lista para enlazar después).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _placeholders = [
    _Placeholder(Icons.dark_mode, 'Modo oscuro'),
    _Placeholder(Icons.palette, 'Temas de GUI'),
    _Placeholder(Icons.autorenew, 'Opciones automáticas'),
    _Placeholder(Icons.data_usage, 'Uso de datos'),
    _Placeholder(Icons.download_done, 'Modelo descargado'),
    _Placeholder(Icons.memory, 'Uso de memoria'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final p in _placeholders) _placeholderTile(p),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.link),
            title: const Text('Mostrar URI en media'),
            subtitle: const Text(
                'Muestra la ruta/URI completa del recurso en vez del nombre'),
            value: s.mediaShowUri,
            onChanged: (v) async {
              setState(() => s.mediaShowUri = v);
              await s.save();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.router_rounded),
            title: const Text('Puertos (UPnP/NAT-PMP)'),
            subtitle: const Text(
                'Abre puertos en el router para DHT y otros servicios'),
            value: s.natEnabled,
            onChanged: (v) async {
              setState(() => s.natEnabled = v);
              await s.save();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.vpn_lock_rounded),
            title: const Text('Tor (experimental)'),
            subtitle: const Text(
                'Cliente arti embebido · proxy SOCKS5 local para la app'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TorTestScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Clave de cifrado'),
            subtitle: Text(
                'Los datos se guardan en config.pr cifrados con: ${s.masterKey}'),
            enabled: false,
          ),
        ],
      ),
    );
  }

  Widget _placeholderTile(_Placeholder p) => ListTile(
        leading: Icon(p.icon, color: Colors.grey),
        title: Text(p.title, style: const TextStyle(color: Colors.grey)),
        trailing: const Switch(value: false, onChanged: null),
        enabled: false,
      );
}

class _Placeholder {
  final IconData icon;
  final String title;
  const _Placeholder(this.icon, this.title);
}
