import 'package:flutter/material.dart';

import 'radial/radial_catalog.dart';
import 'radial/radial_layer.dart';

export 'radial/radial_item.dart';
export 'radial/radial_catalog.dart';

/// Máximo de botones por anillo. Lo que no entra pasa a la capa
/// siguiente (el centro [+] cambia de menú circular).
const int kMaxPorAnillo = 8;

/// Menú circular POR CAPAS: tocá el logo del home → capa 1 con hasta 8
/// botones; el centro [+] apila el anillo siguiente con los que no
/// entraron; y así. Tocar afuera vuelve UNA capa (o cierra todo si ya
/// estás en la primera).
class RadialMenu extends StatefulWidget {
  final void Function(String key) onSelect;

  const RadialMenu({super.key, required this.onSelect});

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _paginas => (RadialCatalog.items.length / kMaxPorAnillo).ceil();

  void _avanzar() {
    setState(() => _page = (_page + 1) % _paginas);
    _ctrl.forward(from: 0);
  }

  void _afuera() {
    // Tocar afuera cierra TODO el menú de una: rápido. El [+] central
    // cicla los anillos; no hay gesto de "volver una capa".
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _page * kMaxPorAnillo;
    final chunk = RadialCatalog.items
        .skip(inicio)
        .take(kMaxPorAnillo)
        .toList(growable: false);

    final hayMas = _paginas > 1;
    final centro = hayMas
        ? RadialCenterSpec(
            icon: Icons.add_rounded,
            label: 'Más (${_page + 2 > _paginas ? 1 : _page + 2}/$_paginas)',
            color: Colors.cyanAccent,
            onTap: _avanzar,
          )
        : RadialCenterSpec(
            icon: Icons.close_rounded,
            label: 'Cerrar',
            color: Colors.white70,
            onTap: () => Navigator.of(context).pop(),
          );
    final hint = hayMas
        ? 'tocá afuera para cerrar · + cambia de anillo'
        : 'tocá afuera para cerrar';

    return Material(
      color: Colors.black.withValues(alpha: .82),
      child: GestureDetector(
        onTap: _afuera,
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: RadialLayerView(
              items: chunk,
              ctrl: _ctrl,
              center: centro,
              hint: hint,
              onPick: (item) {
                // ÚNICO pop de todo el flujo: cerrar el overlay del menú.
                // Antes la capa también popeaba → doble pop → cuando no
                // quedaba ruta Android cerraba la app entera.
                Navigator.of(context).pop();
                widget.onSelect(item.key);
              },
            ),
          ),
        ),
      ),
    );
  }
}
