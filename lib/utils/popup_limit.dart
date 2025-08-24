// file: utils/popup_free.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // pour HapticFeedback


/// =============================
///  POPUP ANIMÉE "FREE"
/// =============================
class PopupLimitOverlay extends StatefulWidget {
  final double backgroundAlpha;
  final Widget paywallTarget;

  const PopupLimitOverlay({
    Key? key,
    this.backgroundAlpha = 0.0,
    required this.paywallTarget,
  }) : super(key: key);

  @override
  State<PopupLimitOverlay> createState() => _PopupLimitOverlayState();
}

class _PopupLimitOverlayState extends State<PopupLimitOverlay>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _popCtrl;
  late AnimationController _pulseCtrl;

  late Animation<double> _bgAnim;
  late Animation<double> _popAnim;
  late Animation<double> _pulseAnim;

  bool _hapticDone = false;

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

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Lance les 2 animations
    _bgCtrl.forward();
    _popCtrl.forward();

    // 3) Gère la fermeture automatique après 4,5s
    _popCtrl.addStatusListener((status) async {
      /*
      if (status == AnimationStatus.completed && !_hapticDone) {
        // Petite vibration
        HapticFeedback.lightImpact();
        _hapticDone = true;

        // DUREE D'AFFICHAGE : 5 SECONDES
        await Future.delayed(const Duration(milliseconds: 5000));

        // Puis on ferme la popup
        _closePopupWithAnimation();
      } 
      */
      if (status == AnimationStatus.dismissed) {
        // Totalement fermé
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  /// Fonction de fermeture (reverse l'animation)
  void _closePopupWithAnimation() {
    if (_popCtrl.isCompleted) {
      _popCtrl.reverse();
      _bgCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _popCtrl.dispose();
    _pulseCtrl.dispose();
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
                        width: 300,
                        height: 380,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.50),
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Icône (exemple star)
                            Image.asset(
                              'assets/icons/sad.png',
                              width: 150,
                              height: 150,
                            ),
                            // Titre principal
                            Text(
                              "Daily limit reached",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 26,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Sous-titre
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Text(
                                "Want more debates today?",
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 18,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ScaleTransition(
                              scale: _pulseAnim,
                              child: SizedBox(
                                width: 240,
                                height: 50,
                                child: GestureDetector(
                                  onTap: () async {
                                    HapticFeedback.lightImpact();
                                    _closePopupWithAnimation();
                                    await Future.delayed(const Duration(milliseconds: 350));
                                    if (mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => widget.paywallTarget),
                                      );
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF44F5FB), Color(0xFF025BFE)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Continue',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontSize: 20,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
