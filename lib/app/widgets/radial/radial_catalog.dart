import 'package:flutter/material.dart';

import 'radial_item.dart';

/// Catálogo ÚNICO del menú radial: el único lugar donde se agregan,
/// quitan o reordenan entradas. Las capas se cortan acá (de a 8).
///
/// 'ring' (Nostringer) era el botón central fijo; con el menú por capas
/// pasó a item normal del anillo.
abstract final class RadialCatalog {
  static const items = <RadialMenuItem>[
    RadialMenuItem(
        key: 'dm',
        label: 'Nostr DM',
        icon: Icons.chat_bubble_rounded,
        color: Colors.cyanAccent),
    RadialMenuItem(
        key: 'obs',
        label: 'Nostr Obs',
        icon: Icons.visibility_rounded,
        color: Colors.deepPurpleAccent),
    RadialMenuItem(
        key: 'shamir',
        label: 'Shamir',
        icon: Icons.call_split_rounded,
        color: Colors.orangeAccent),
    RadialMenuItem(
        key: 'kem',
        label: 'KEM',
        icon: Icons.enhanced_encryption_rounded,
        color: Colors.greenAccent),
    RadialMenuItem(
        key: 'hf',
        label: 'HuggingFace',
        icon: Icons.hub_rounded,
        color: Colors.lightBlueAccent),
    RadialMenuItem(
        key: 'gpu',
        label: 'GPU',
        icon: Icons.memory_rounded,
        color: Colors.pinkAccent),
    RadialMenuItem(
        key: 'dl',
        label: 'Descargas',
        icon: Icons.download_rounded,
        color: Colors.tealAccent),
    RadialMenuItem(
        key: 'bt',
        label: 'Torrent',
        icon: Icons.bolt_rounded,
        color: Colors.amberAccent),
    RadialMenuItem(
        key: 'ag',
        label: 'Agentes IA',
        icon: Icons.psychology_rounded,
        color: Colors.lightGreenAccent),
    RadialMenuItem(
        key: 'rv',
        label: 'Voto BLSAG',
        icon: Icons.how_to_vote_rounded,
        color: Colors.green),
    RadialMenuItem(
        key: 'ip',
        label: 'IPFS',
        icon: Icons.hub_rounded,
        color: Colors.tealAccent),
    RadialMenuItem(
        key: 'ua',
        label: 'Unarc',
        icon: Icons.folder_zip_rounded,
        color: Colors.blueAccent),
    RadialMenuItem(
        key: 'ub',
        label: 'Nostr Busca',
        icon: Icons.search_rounded,
        color: Colors.indigoAccent),
    RadialMenuItem(
        key: 'nn',
        label: 'Nostrn+',
        icon: Icons.mark_email_unread_rounded,
        color: Colors.orangeAccent),
    RadialMenuItem(
        key: 'up',
        label: 'Pkarr',
        icon: Icons.dns_rounded,
        color: Colors.purpleAccent),
    RadialMenuItem(
        key: 'tr',
        label: 'Tor',
        icon: Icons.vpn_lock_rounded,
        color: Color(0xFFAB47BC)),
    RadialMenuItem(
        key: 'dh',
        label: 'DHT Busca',
        icon: Icons.radar_rounded,
        color: Colors.deepOrangeAccent),
    RadialMenuItem(
        key: 'ir',
        label: 'Iroh P2P',
        icon: Icons.lan_rounded,
        color: Colors.lightBlueAccent),
    RadialMenuItem(
        key: 'ic',
        label: 'Iroh Chat',
        icon: Icons.forum_rounded,
        color: Color(0xFF4DD0E1)),
    RadialMenuItem(
        key: 'ring',
        label: 'Nostringer',
        icon: Icons.fingerprint_rounded,
        color: Color(0xFFB57CFF)),

  ];
}
