import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 

class PopupInfo extends StatefulWidget {
  final double backgroundAlpha;
  final String iconPath;
  final String title;
  final String? subtitle;
  final int durationMs;

  const PopupInfo({
    Key? key,
    this.backgroundAlpha = 0.0,
    required this.iconPath,
    required this.title,
    this.subtitle,
    this.durationMs = 4000,
  }) : super(key: key);

  static void show(
    BuildContext context, {
    required String iconPath,
    required String title,
    String? subtitle,
    int durationMs = 4000,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (_) => PopupInfo(
        iconPath: iconPath,
        title: title,
        subtitle: subtitle ?? '',
        durationMs: durationMs,
      ),
    );
  }

  @override
  State<PopupInfo> createState() => _PopupInfoOverlayState();
}

class _PopupInfoOverlayState extends State<PopupInfo>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _popCtrl;

  late Animation<double> _bgAnim;
  late Animation<double> _popAnim;

  bool _hapticDone = false;
  bool _isDisposed = false;
  late final AnimationStatusListener _statusListener;

  @override
  void initState() {
    super.initState();

    // 1) Contrôleur pour l'arrière-plan (voile + flou)
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bgAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bgCtrl,
        curve: Curves.easeInOut,
      ),
    );

    // 2) Contrôleur pour la popup (scale)
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _popAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _popCtrl,
        curve: Curves.easeOutBack,
      ),
    );

    // Lance les 2 animations
    _bgCtrl.forward();
    _popCtrl.forward();

    // 3) Gère la fermeture automatique après durationMs
    _statusListener = (AnimationStatus status) async {
      if (status == AnimationStatus.completed && !_hapticDone) {
        // Petite vibration
        HapticFeedback.lightImpact();
        _hapticDone = true;

        // DUREE D'AFFICHAGE : widget.durationMs millisecondes
        await Future.delayed(Duration(milliseconds: widget.durationMs));

        // Puis on ferme la popup
        _closePopupWithAnimation();
      } else if (status == AnimationStatus.dismissed) {
        // Totalement fermé
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    };
    _popCtrl.addStatusListener(_statusListener);
  }

  /// Fonction de fermeture (reverse l'animation)
  void _closePopupWithAnimation() {
    if (_isDisposed) return;                           // controller already disposed
    if (_popCtrl.isAnimating ||
        _popCtrl.status == AnimationStatus.dismissed) return;

    try {
      _popCtrl.reverse();
      _bgCtrl.reverse();
    } catch (_) {
      // Controller could already be disposed – ignore safely.
    }
  }

  @override
  void dispose() {
    _isDisposed = true;            // <- guard against late callbacks
    _popCtrl.removeStatusListener(_statusListener);
    _bgCtrl.dispose();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // => 1. Si on clique n'importe où sur l'écran, on ferme la popup
      onTap: () => _closePopupWithAnimation(),
      behavior: HitTestBehavior.translucent, 
      child: AnimatedBuilder(
        animation: Listenable.merge([_bgAnim, _popAnim]),
        builder: (context, child) {
          final bgValue = _bgAnim.value; // [0..1]
          final popValue = _popAnim.value; // [0..1]

          // voile => alpha = widget.backgroundAlpha * bgValue
          final double currentAlpha = widget.backgroundAlpha * bgValue;

          return Stack(
            children: [
              // 1) Fond flou progressif + voile
              Positioned.fill(
                child: Stack(
                  children: [
                    // voile
                    Container(
                      color: Colors.black.withOpacity(currentAlpha),
                    ),
                    // flou
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 5.0 * bgValue,
                          sigmaY: 5.0 * bgValue,
                        ),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),

              // 2) La popup => scale: popValue
              Center(
                child: Transform.scale(
                  scale: popValue,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30.0),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        width: 310,
                        constraints: const BoxConstraints(minHeight: 280),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.50),
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Icône (externe)
                            Image.asset(
                              widget.iconPath,
                              width: 280,
                              height: 280,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 16),

                            // Titre
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),

                            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  widget.subtitle!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
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
