import 'dart:ui';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// -----------------------------------------------------------------
///  POPUP INFO  (boîte générique + voile / flou)
/// -----------------------------------------------------------------
class PopupInfo extends StatefulWidget {
  final double backgroundAlpha;
  final String iconPath;
  final String title;
  final String? subtitle;
  final int durationMs;
  final bool tapToClose;

  const PopupInfo({
    Key? key,
    this.backgroundAlpha = 0.0,
    required this.iconPath,
    required this.title,
    this.subtitle,
    this.durationMs = 4000,
    this.tapToClose = true,
  }) : super(key: key);

  @override
  State<PopupInfo> createState() => _PopupInfoOverlayState();
}

class _PopupInfoOverlayState extends State<PopupInfo>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final AnimationController _popCtrl;
  late final Animation<double> _bgAnim;
  late final Animation<double> _popAnim;
  bool _hapticDone = false;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bgAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut),
    );
    _popAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _popCtrl, curve: Curves.easeOutBack),
    );

    _bgCtrl.forward();
    _popCtrl.forward();

    _popCtrl.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !_hapticDone) {
        HapticFeedback.lightImpact();
        _hapticDone = true;
        await Future.delayed(Duration(milliseconds: widget.durationMs));
        _close();
      } else if (status == AnimationStatus.dismissed) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });
  }

  void _close() {
    if (_popCtrl.isCompleted) {
      _popCtrl.reverse();
      _bgCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.tapToClose ? _close : null,
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bgAnim, _popAnim]),
        builder: (_, __) {
          final double veilAlpha = widget.backgroundAlpha * _bgAnim.value;
          return Stack(
            children: [
              // voile + flou
              Positioned.fill(
                child: Stack(
                  children: [
                    Container(color: Colors.black.withOpacity(veilAlpha)),
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 5 * _bgAnim.value,
                          sigmaY: 5 * _bgAnim.value,
                        ),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),
              // boîte popup
              Center(
                child: Transform.scale(
                  scale: _popAnim.value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: 340,
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              widget.iconPath,
                              width: 220,
                              height: 220,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            if (widget.subtitle != null &&
                                widget.subtitle!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  widget.subtitle!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// -----------------------------------------------------------------
///  POPUP GAME OVER
/// -----------------------------------------------------------------
class PopupGameOver extends StatelessWidget {
  /// Quand true, l’image centrale est retournée mais les boutons
  /// restent lisibles.
  final bool flipped;

  const PopupGameOver({super.key, this.flipped = false});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // Contenu réel de la pop‑up
    Widget inner = Stack(
      children: [
        // Removed the first Positioned.fill containing the image as requested
        // voile + flou
        Positioned.fill(
          child: Stack(
            children: [
              Container(color: Colors.black.withOpacity(0.5)),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
        ),
        // boîte centrale
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 600),
            child: AspectRatio(
              aspectRatio: 1024 / 1615,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: flipped ? pi : 0,
                        child: Image.asset(
                          'assets/illustrations/gameover.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(30, 30, 30, 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: Colors.transparent,
                      ),
                      child: Stack(
                        children: [
                          if (!flipped)
                            // Bas
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _glassButton(
                                    label: t.restart,
                                    onTap: () => Navigator.of(context).pop('restart'),
                                  ),
                                  const SizedBox(height: 14),
                                  _glassButton(
                                    label: t.switchCategory,
                                    onTap: () => Navigator.of(context).pop('switch'),
                                  ),
                                ],
                              ),
                            ),
                          if (flipped)
                            // Haut
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RotatedBox(
                                    quarterTurns: 2,
                                    child: _glassButton(
                                      label: t.switchCategory,
                                      onTap: () => Navigator.of(context).pop('switch'),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  RotatedBox(
                                    quarterTurns: 2,
                                    child: _glassButton(
                                      label: t.restart,
                                      onTap: () => Navigator.of(context).pop('restart'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return inner;
  }
}

/// Petit bouton « verre » (arrondi pill)
Widget _glassButton({
  required String label,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(30), // pill shape
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.35),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}