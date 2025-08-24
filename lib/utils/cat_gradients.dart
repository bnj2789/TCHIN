
import 'package:flutter/material.dart';

/// Dégradés par catégorie — source de vérité unique.
final Map<String, Gradient> catGradients = {
  'lifestyle': const RadialGradient(
        colors: [Color.fromARGB(255, 0, 191, 230), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,
  ),
  'couple': const RadialGradient(
    colors: [Color.fromARGB(255, 227, 0, 117), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,

  ),
  'fun': const RadialGradient(
    colors: [Color.fromARGB(255, 0, 207, 31), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,

  ),
  'chaos': const RadialGradient(
    colors: [Color(0xFF034E92), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,
  ),
  'hot': const RadialGradient(
    colors: [Color.fromARGB(255, 221, 0, 0), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,

  ),
  'hardcore': const RadialGradient(
    colors: [Color.fromARGB(255, 158, 0, 197), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,
  ),
  'glitch': const RadialGradient(
    colors: [Color.fromARGB(255, 0, 157, 255), Color.fromARGB(255, 0, 0, 0)],
    center: Alignment.center,
    radius: 1.15,

  ),
};

/// Utilitaire : certains écrans veulent un LinearGradient.
LinearGradient asLinearGradient(Gradient g) {
  if (g is LinearGradient) return g;
  if (g is RadialGradient) {
    return LinearGradient(
      colors: g.colors,
      stops: g.stops,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
  if (g is SweepGradient) {
    return LinearGradient(
      colors: g.colors,
      stops: g.stops,
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }
  return const LinearGradient(
    colors: [Colors.black, Colors.black],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}