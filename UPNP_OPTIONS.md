# UPnP / NAT-PMP en mimapp — opciones

Objetivo: que la app abra puertos en el router (UPnP-IGD y/o NAT-PMP) para que
servicios como el spider DHT (Mainline, UDP 6881) sean alcanzables desde afuera
de la NAT, y que **cualquier parte de la app pueda pedir un puerto por Dart**.

## Opción A — Dart puro (`port_forwarder`)  [ELEGIDA PRIMERO]

Paquete: https://pub.dev/packages/port_forwarder (mantenido, 2025).

- Soporta **UPnP (IGD)**, **NAT-PMP** y **NAT-PCP**.
- API simple:
  ```dart
  final gw = await Gateway.discover(
      protocols: {GatewayType.upnp, GatewayType.natPmp, GatewayType.natPcp});
  await gw.openPort(protocol: PortProtocol.udp, externalPort: 6881,
      internalPort: 6881, description: 'mimapp DHT spider');
  final wan = await gw.externalAddress;
  await gw.closePort(protocol: PortProtocol.udp, externalPort: 6881);
  ```
- Ventajas: 100% Dart, sin rebuild de bindings FRB, fácil de probar, se integra
  con el resto de la UI Dart (Settings, DHT screen) tal cual pidió el usuario
  ("por dart abran x puerto").
- Desventajas / riesgos:
  - El descubrimiento **UPnP usa multicast SSDP** (239.255.255.250:1900). En
    Android recibir multicast suele requerir `CHANGE_WIFI_MULTICAST_STATE` y
    adquirir `WifiManager.MulticastLock` desde el lado Java.
  - NAT-PMP **no** usa multicast (UDP directo al gateway :5351) → más fiable en
    Android. `port_forwarder` prueba ambos, así que si UPnP falla por multicast
    todavía puede mapear vía NAT-PMP.

Decisión: se implementa **primero** porque es lo primero que falla/prueba y no
toca Rust. Si en dispositivo/CI el multicast de UPnP no funciona, se prioriza
NAT-PMP o se agrega un platform channel para el `MulticastLock`.

## Opción B — Rust (`igd` + `natpmp` vía FRB)  [FALLBACK DOCUMENTADO]

Crates: `igd` (UPnP-IGD, feature `tokio`) y `natpmp` (NAT-PMP), ambos puros-Rust.

- Nuevo módulo `rust/src/api/nat.rs` expuesto con `#[frb]`:
  `nat_open_port`, `nat_close_port`, `nat_close_all`, `nat_discover`,
  `nat_external_ip`, `nat_set_enabled`.
- Ventajas: control fino, se integra con el bind de `mainline` (6881) en el
  mismo proceso Rust, sin depender del stack de red de Dart.
- Desventajas: nuevo módulo, rebuild de bindings FRB (más lento en CI), más
  superficie de código y posible fricción de link en Android.

Se deja documentado como fallback si la opción Dart no abre puertos en la
plataforma objetivo.

## Resumen

| Aspecto            | Dart (`port_forwarder`) | Rust (`igd`+`natpmp`) |
|--------------------|-------------------------|------------------------|
| Lenguaje           | Dart                    | Rust + FRB             |
| Rebuild bindings   | no                      | sí                     |
| UPnP / NAT-PMP     | sí (y NAT-PCP)          | sí                     |
| Multicast Android  | riesgo (ver arriba)     | riesgo (igual)         |
| Esfuerzo           | bajo                    | medio-alto             |
| Estado             | **implementado**        | fallback               |
