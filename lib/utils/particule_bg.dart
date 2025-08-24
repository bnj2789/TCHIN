


import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ParticleBackground extends StatefulWidget {
  const ParticleBackground({super.key});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Particle> _particles;
  List<ui.Image>? _images;

  // Liste des assets à charger (modifiez selon vos assets disponibles).
  final List<String> _assetPaths = [
    'assets/blablabla/haha.png',
    'assets/blablabla/hihi.png',
    'assets/blablabla/oops.png',
    'assets/blablabla/oulala.png',
    'assets/blablabla/hoho.png',
    'assets/blablabla/hehe.png',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final List<ui.Image> loadedImages = [];
    for (final asset in _assetPaths) {
      final ByteData data = await rootBundle.load(asset);
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(data.buffer.asUint8List(), (img) {
        completer.complete(img);
      });
      loadedImages.add(await completer.future);
    }
    setState(() {
      _images = loadedImages;
      _particles = List.generate(50, (_) => Particle.random(images: _images));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_images == null) {
      return const SizedBox.expand(); // Or a placeholder
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return CustomPaint(
          painter: ParticlePainter(_particles, _controller.value),
          child: Container(),
        );
      },
    );
  }
}

class Particle {
  Offset position;
  double radius;
  Color color;
  double dx;
  double dy;
  ui.Image? image;

  Particle(this.position, this.radius, this.color, this.dx, this.dy, {this.image});

  factory Particle.random({List<ui.Image>? images}) {
    final rand = Random();
    final position = Offset(rand.nextDouble(), rand.nextDouble());
    final radius = rand.nextDouble() * 20 + 16; // taille raisonnable pour images
    final color = Colors.white.withOpacity(rand.nextDouble() * 0.25 + 0.35);
    final dx = (rand.nextDouble() - 0.5) * 0.001;
    final dy = (rand.nextDouble() - 0.5) * 0.001;
    ui.Image? image;
    if (images != null && images.isNotEmpty) {
      image = images[rand.nextInt(images.length)];
    }
    return Particle(position, radius, color, dx, dy, image: image);
  }

  void update(double progress) {
    position += Offset(dx, dy);
    if (position.dx < 0 || position.dx > 1) dx = -dx;
    if (position.dy < 0 || position.dy > 1) dy = -dy;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  ParticlePainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      p.update(progress);
      final offset = Offset(p.position.dx * size.width, p.position.dy * size.height);
      if (p.image != null) {
        // Dessine l'image centrée sur la position, avec un scale basé sur radius
        final src = Rect.fromLTWH(0, 0, p.image!.width.toDouble(), p.image!.height.toDouble());
        final dst = Rect.fromCenter(
          center: offset,
          width: p.radius * 2,
          height: p.radius * 2,
        );
        paint.color = p.color;
        canvas.saveLayer(dst, paint);
        canvas.drawImageRect(p.image!, src, dst, paint);
        canvas.restore();
      } else {
        paint
          ..color = p.color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(offset, p.radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}