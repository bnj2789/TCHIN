import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'popup.dart';

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
    _popCtrl.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !_hapticDone) {
        // Petite vibration
        HapticFeedback.lightImpact();
        _hapticDone = true;

        // DUREE D'AFFICHAGE : widget.durationMs millisecondes
        await Future.delayed(Duration(milliseconds: widget.durationMs));

        // Puis on ferme la popup
        _closePopupWithAnimation();
      } 
      else if (status == AnimationStatus.dismissed) {
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
                        constraints: BoxConstraints(
                          maxWidth: 320,
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(26.0),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icône (externe)
                            Image.asset(
                              widget.iconPath,
                              width: 250,
                              height: 250,
                            ),
                            const SizedBox(height: 2),

                            // Titre
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 26,
                                height: 1.2,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),

                            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  widget.subtitle!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    height: 1.1,
                                    color: Colors.black,
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

class PopupEmptyFavorite extends StatelessWidget {
  const PopupEmptyFavorite({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!; // localisation
    return PopupInfo(
      iconPath: 'assets/illustrations/fav.png',
      title: t.popupFavEmptyTitle,
      subtitle: t.popupFavEmptySub,
      backgroundAlpha: 0.5,
    );
  }
}