import 'package:flutter/material.dart';

/// Navegador global: permite volver a la bienvenida cuando la sesión vence
/// (respuesta 401 del backend) desde fuera de una pantalla.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
