import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';   // <-- NEW
import 'package:audioplayers/audioplayers.dart';
import 'package:lottie/lottie.dart';

import '../paywall.dart';

// --- Single SFX player for Life icons (prevents overlapping plays) ---------
AudioPlayer? _lifeSfxPlayer;
String? _lifeSfxCurrentAsset;
bool _lifeSfxIsPlaying = false;
int _lifeSfxNonce = 0;

Future<void> _playLifeSfx(String assetSourcePath) async {
  _lifeSfxPlayer ??= AudioPlayer();
  final int nonce = ++_lifeSfxNonce;

  // If something is already playing
  if (_lifeSfxIsPlaying) {
    if (_lifeSfxCurrentAsset == assetSourcePath) {
      // Same sound still playing → ignore
      return;
    } else {
      // Different sound requested → stop previous before playing new
      try { await _lifeSfxPlayer!.stop(); } catch (_) {}
    }
  }

  _lifeSfxCurrentAsset = assetSourcePath;
  _lifeSfxIsPlaying = true;

  try {
    await _lifeSfxPlayer!.play(AssetSource(assetSourcePath));
  } catch (_) {
    _lifeSfxIsPlaying = false;
    return;
  }

  // Clear flags when playback completes (only if still the latest request)
  _lifeSfxPlayer!.onPlayerComplete.first.then((_) {
    if (nonce != _lifeSfxNonce) return; // an even newer play started
    _lifeSfxIsPlaying = false;
    _lifeSfxCurrentAsset = null;
  });
}

/// ---------------------------------------------------------------------------
///  Centralised game settings  +  ready‑made UI (panel & card)
/// ---------------------------------------------------------------------------
class Settings extends ChangeNotifier {
  // -- singleton ------------------------------------------------------------
  Settings._internal();
  static final Settings instance = Settings._internal();
  static Settings get() => instance; // raccourci

  // -- clés SharedPreferences ----------------------------------------------
  static const _kSoundOn = 'settings_sound_on';
  static const _kSoloOn  = 'settings_solo_on';
  static const _kTimeIdx = 'settings_time_idx';
  static const _kLifeIdx = 'settings_life_idx';
  static const _kLifeIconIdx = 'settings_life_icon_idx';

  // -- valeurs proposées ----------------------------------------------------
  static const List<double> timeValues = [3.3, 6.9, 9.6];
  static const List<int>    lifeValues = [1, 3, 5];
  static const List<String> lifeJsonAssets = [
    'assets/illustrations/fire.json',
    'assets/illustrations/lifeOut.json',
    'assets/illustrations/glass.json',
    'assets/illustrations/star.json',
  ];

  // -- état interne ---------------------------------------------------------
  bool _soundOn = true;
  bool get soundOn => _soundOn;
  set soundOn(bool v) {
    if (v != _soundOn) {
      _soundOn = v;
      _persistBool(_kSoundOn, v);
      notifyListeners();
    }
  }

  bool _soloOn = false;
  bool get soloOn => _soloOn;
  set soloOn(bool v) {
    if (v != _soloOn) {
      _soloOn = v;
      _persistBool(_kSoloOn, v);
      notifyListeners();
    }
  }

  int _timeIdx = 1; // 0 = 3.3 s, 1 = 6.9 s, 2 = 9.6 s
  int get timeIdx => _timeIdx;
  set timeIdx(int idx) {
    idx = idx.clamp(0, timeValues.length - 1);
    if (idx != _timeIdx) {
      _timeIdx = idx;
      _persistInt(_kTimeIdx, idx);
      notifyListeners();
    }
  }

  int _lifeIdx = 1; // 0 = 1, 1 = 3, 2 = 5
  int get lifeIdx => _lifeIdx;
  set lifeIdx(int idx) {
    idx = idx.clamp(0, lifeValues.length - 1);
    if (idx != _lifeIdx) {
      _lifeIdx = idx;
      _persistInt(_kLifeIdx, idx);
      notifyListeners();
    }
  }

  int _lifeIconIdx = 1; // default: lifeOut.json
  int get lifeIconIdx => _lifeIconIdx;
  set lifeIconIdx(int idx) {
    idx = idx.clamp(0, lifeJsonAssets.length - 1);
    if (idx != _lifeIconIdx) {
      _lifeIconIdx = idx;
      _persistInt(_kLifeIconIdx, idx);
      notifyListeners();
    }
  }

  // -- getters pratiques ----------------------------------------------------
  double get selectedTime  => timeValues[_timeIdx];
  int    get selectedLives => lifeValues[_lifeIdx];
  String get selectedLifeJson => lifeJsonAssets[_lifeIconIdx];

  // -- chargement initial ---------------------------------------------------
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _soundOn = prefs.getBool(_kSoundOn) ?? _soundOn;
    _soloOn  = prefs.getBool(_kSoloOn)  ?? _soloOn;
    _timeIdx = prefs.getInt(_kTimeIdx)  ?? _timeIdx;
    _lifeIdx = prefs.getInt(_kLifeIdx)  ?? _lifeIdx;
    _lifeIconIdx = prefs.getInt(_kLifeIconIdx) ?? _lifeIconIdx;
    notifyListeners();
  }

  // -- persistance helpers --------------------------------------------------
  Future<void> _persistBool(String k, bool v) async =>
      (await SharedPreferences.getInstance()).setBool(k, v);
  Future<void> _persistInt (String k, int v) async =>
      (await SharedPreferences.getInstance()).setInt (k, v);
}

/// ---------------------------------------------------------------------------
///  SettingsPanel – bascule « Sound », « Solo », curseurs Time & Life
/// ---------------------------------------------------------------------------
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  // ===============  helpers (only for this panel)  ===============
  Future<void> _launchURL(BuildContext context, String iosUrl, String androidUrl) async {
    final Uri uri = Uri.parse(Platform.isIOS ? iosUrl : androidUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.linkError)),
      );
    }
  }

  Widget _sectionHeader(BuildContext ctx, String title) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
      );

  Widget _simpleRow({
    required BuildContext ctx,
    IconData? icon,
    String? assetIcon,
    required String text,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (assetIcon != null)
              Image.asset(assetIcon, width: 28, height: 28)
            else if (icon != null)
              Icon(icon, color: Colors.white70),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: const TextStyle(color: Colors.white)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t     = AppLocalizations.of(context)!;           // <-- NEW
    // === Slider Colors (easy to tweak) =====================================
    const Color lifeActive = Color.fromARGB(255, 0, 213, 255);
    final Color lifeInactive = Colors.grey.shade700;
    const Color timeActive = Color.fromARGB(255, 0, 200, 235);
    final Color timeInactive = Colors.grey.shade700;
    return AnimatedBuilder(
      animation: Settings.get(),
      builder: (_, __) {
        final s = Settings.get();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- HEADER ---------------------------------------------
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  t.settingsTitle,
                  style: theme.textTheme.titleMedium!
                      .copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.close, color: Colors.white70),
                  ),
                ),
              ],
            ),

            const Divider(height: 20, color: Colors.white24),

            // --- SOUND ------------------------------------------------------
            SizedBox(
              height: 40, // hauteur fixe compacte
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.sound, style: theme.textTheme.bodyMedium),
                  Transform.scale(
                    scale: 0.85,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        switchTheme: SwitchThemeData(
                          // Thumb color (circle)
                          thumbColor: MaterialStateProperty.resolveWith((states) {
                            return states.contains(MaterialState.selected)
                                ? const Color.fromARGB(255, 0, 242, 255)
                                : Colors.grey.shade400;
                          }),
                          // Track color (background)
                          trackColor: MaterialStateProperty.resolveWith((states) {
                            return states.contains(MaterialState.selected)
                                ? lifeActive.withOpacity(0.45)
                                : lifeInactive;
                          }),
                          // No outline on track
                          trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                          // Press/hover overlay tint
                          overlayColor: MaterialStateProperty.all(const Color.fromARGB(255, 0, 167, 200).withOpacity(0.12)),
                        ),
                      ),
                      child: Switch(
                        value: s.soundOn,
                        onChanged: (v) => s.soundOn = v,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 2),

            // --- SOLO -------------------------------------------------------
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.soloMode, style: theme.textTheme.bodyMedium),
                  Transform.scale(
                    scale: 0.85,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        switchTheme: SwitchThemeData(
                          thumbColor: MaterialStateProperty.resolveWith((states) {
                            return states.contains(MaterialState.selected)
                                ? const Color.fromARGB(255, 0, 204, 255)
                                : Colors.grey.shade400;
                          }),
                          trackColor: MaterialStateProperty.resolveWith((states) {
                            return states.contains(MaterialState.selected)
                                ? timeActive.withOpacity(0.45)
                                : lifeInactive;
                          }),
                          trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                          overlayColor: MaterialStateProperty.all(timeActive.withOpacity(0.12)),
                        ),
                      ),
                      child: Switch(
                        value: s.soloOn,
                        onChanged: (v) => s.soloOn = v,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- TIME -------------------------------------------------------
            Center(
              child: Text(
                '${t.speed} (${s.selectedTime.toStringAsFixed(1)} s)',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith( 
                  trackHeight: 2,
                  activeTrackColor: lifeActive,
                  inactiveTrackColor: lifeInactive,

                  // === value‑indicator (label) colours =====================
                  valueIndicatorColor: lifeActive,
                  valueIndicatorTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),

                  thumbColor: lifeActive,
                  overlayColor: lifeActive.withOpacity(.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
                ),
                child: Transform.scale(
                  scale: 1,
                  child: Slider(
                    min: 0,
                    max: (Settings.timeValues.length - 1).toDouble(),
                    divisions: Settings.timeValues.length - 1,
                    value: s.timeIdx.toDouble(),
                    label: '${s.selectedTime.toStringAsFixed(1)} s',
                    onChanged: (v) => s.timeIdx = v.round(),
                  ),
                ),
              ),
            ),

            // --- LIFE (icons) ----------------------------------------------
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  s.selectedLives,
                  (_) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Lottie.asset(
                      Settings.lifeJsonAssets[s.lifeIconIdx],
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                      animate: false,
                      repeat: false,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 1),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: const Color.fromARGB(255, 200, 0, 140),
                  inactiveTrackColor: lifeInactive,
                  thumbColor: const Color.fromARGB(255, 200, 0, 163),
                  overlayColor: const Color.fromARGB(255, 200, 0, 107).withOpacity(.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
                ),
                child: Transform.scale(
                  scale: 1, // encore plus plat
                  child: Slider(
                    min: 0,
                    max: (Settings.lifeValues.length - 1).toDouble(),
                    divisions: Settings.lifeValues.length - 1,
                    value: s.lifeIdx.toDouble(),
                    onChanged: (v) => s.lifeIdx = v.round(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // --- LIFE ICON (Lottie JSON choices; static first frame) -----------------
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  Settings.lifeJsonAssets.length,
                  (i) {
                    final sNow = Settings.get();
                    final bool isSelected = i == sNow.lifeIconIdx;
                    return GestureDetector(
                      onTap: () async {
                        sNow.lifeIconIdx = i;
                        try {
                          // Derive sound path from the json filename
                          final jsonPath = Settings.lifeJsonAssets[i]; // e.g., assets/illustrations/fire.json
                          final fileName = jsonPath.split('/').last;   // fire.json
                          final baseName = fileName.replaceAll('.json', '');
                          final fullSoundPath = 'assets/sound/$baseName.mp3';
                          // For audioplayers AssetSource, strip the leading 'assets/' if present
                          final assetSourcePath = fullSoundPath.startsWith('assets/')
                              ? fullSoundPath.substring('assets/'.length)
                              : fullSoundPath;

                          // Delay 0.5s before playing the sound
                          await Future.delayed(const Duration(milliseconds: 500));
                          // If selection changed during the delay, skip playback
                          if (Settings.get().lifeIconIdx != i) return;

                          await _playLifeSfx(assetSourcePath);
                        } catch (_) {
                          // swallow any audio error silently; selection UI still updates
                        }
                      },
                      child: AnimatedScale(
                        scale: isSelected ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: Colors.white70, width: 1)
                                : null,
                          ),
                          child: _LifeJsonThumb(
                            asset: Settings.lifeJsonAssets[i],
                            size: 48,
                            selected: isSelected,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ========== OTHER =============================================
            _sectionHeader(context, t.sectionOther),
            _simpleRow(
              ctx: context,
              icon: Icons.lock_open,
              text: t.premium,
              subtitle: t.premiumSub,
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PaywallPage(),
              ),
            ),
            _simpleRow(
              ctx: context,
              icon: Icons.star,
              text: t.rateApp,
              subtitle: t.rateAppSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/tchin-party-game/id6751311460',
                'https://play.google.com/store/apps/details?id=com.impactmsg.secs69',
              ),
            ),

            // ========== MY OTHER APPS ======================================
            _sectionHeader(context, t.sectionOtherApps),
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/impactmsg.png',
              text: t.appImpactMsg,
              subtitle: t.appImpactMsgSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/fr/app/impact-msg/id1342647816',
                'https://play.google.com/store/apps/details?id=com.meatboy.impact',
              ),
            ),
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/swipecolorgame.png',
              text: t.appSwipeColor,
              subtitle: t.appSwipeColorSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/swipe-color-game/id1522599744',
                'https://play.google.com/store/apps/details?id=com.impactmsg.swipecolorgame',
              ),
            ),
             _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/lietime.png',
              text: 'LieTime : IMPOSTOR Game',
              subtitle: t.appLieTimeSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/lietime-impostor-game/id6752035991',
                'https://play.google.com/store/apps/details?id=com.impactmsg.impostorGame',
              ),
            ),
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/yadeba.png',
              text: t.appYadeba,
              subtitle: t.appYadebaSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/yadeba-1600-adult-debates/id6741700947',
                'https://play.google.com/store/apps/details?id=com.impactmsg.yadeba',
              ),
            ),
            
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/royaltruth.png',
              text: t.appRoyalTruth,
              subtitle: t.appRoyalTruthSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/fr/app/royal-action-ou-v%C3%A9rit%C3%A9/id6745132843',
                'https://play.google.com/store/apps/details?id=com.impactmsg.royal_truth_or_dare',
              ),
            ),
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/69secs.png',
              text: t.app69Secs,
              subtitle: t.app69SecsSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/fr/app/6-9-secondes-jeu-de-soir%C3%A9e/id6748928134',
                'https://play.google.com/store/apps/details?id=com.impactmsg.secs69',
              ),
            ),
            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/dilemmium.png',
              text: t.appDilemmium,
              subtitle: t.appDilemmiumSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/dilemmium-adult-choices/id6740153076',
                'https://apps.apple.com/us/app/dilemmium-adult-choices/id6740153076',
              ),
            ),


            _simpleRow(
              ctx: context,
              assetIcon: 'assets/icons/lejeuqui.png',
              text: t.appLeJeuQui,
              subtitle: t.appLeJeuQuiSub,
              onTap: () => _launchURL(
                context,
                'https://apps.apple.com/us/app/le-jeu-qui/id6448712204',
                'https://play.google.com/store/apps/details?id=com.lejeuqui',
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------------
///  _LifeJsonThumb – plays the Lottie once when selected, then fades back
/// ---------------------------------------------------------------------------
class _LifeJsonThumb extends StatefulWidget {
  final String asset;
  final double size;
  final bool selected;
  const _LifeJsonThumb({
    required this.asset,
    required this.size,
    required this.selected,
  });

  @override
  State<_LifeJsonThumb> createState() => _LifeJsonThumbState();
}

class _LifeJsonThumbState extends State<_LifeJsonThumb>
    with TickerProviderStateMixin {
  late final AnimationController _lottieCtrl =
      AnimationController(vsync: this);
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 0, // animated overlay hidden by default
  );

  // Completer used to wait for Lottie composition to load (duration known)
  Completer<void>? _compLoaded = Completer<void>();
  // Nonce to cancel previous plays if a new selection occurs
  int _playNonce = 0;

  @override
  void initState() {
    super.initState();
    if (widget.selected) {
      // Run after first frame so the Lottie onLoaded can complete the duration.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playOnceThenFade();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LifeJsonThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.asset != oldWidget.asset) {
      // New asset => wait for its composition to load before playing
      _compLoaded = Completer<void>();
    }
    // If this thumb transitions to selected, play once then fade out
    if (widget.selected && !oldWidget.selected) {
      _playOnceThenFade();
    }
  }

  Future<void> _playOnceThenFade() async {
    final int nonce = ++_playNonce; // capture this play
    try {
      // Ensure animated overlay is visible
      _fadeCtrl.value = 1;
      _lottieCtrl.reset();
      // Wait for composition (duration) to be ready
      if (_compLoaded?.isCompleted != true) {
        await _compLoaded!.future;
      }
      if (!mounted || nonce != _playNonce) return;
      // Play full animation
      await _lottieCtrl.forward(from: 0);
    } catch (_) {
      // ignore any animation error
    } finally {
      // Only fade back if still the latest requested play
      if (mounted && nonce == _playNonce) {
        await _fadeCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _lottieCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Static layer: first frame only (hidden while overlay is visible)
          FadeTransition(
            opacity: ReverseAnimation(_fadeCtrl),
            child: Lottie.asset(
              widget.asset,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              animate: false,
              repeat: false,
            ),
          ),
          // Animated overlay: plays once, then fades out
          FadeTransition(
            opacity: _fadeCtrl,
            child: Lottie.asset(
              widget.asset,
              controller: _lottieCtrl,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              repeat: false,
              onLoaded: (comp) {
                _lottieCtrl.duration = comp.duration;
                final c = _compLoaded;
                if (c != null && !c.isCompleted) {
                  c.complete();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  SettingsCard – carte illustrée recto/verso (flip Y) à placer dans la grille
/// ---------------------------------------------------------------------------
class SettingsCard extends StatefulWidget {
  final String title;
  final String image;
  final LinearGradient gradient;

  const SettingsCard({
    super.key,
    required this.title,
    required this.image,
    required this.gradient,
  });

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_ctrl.isAnimating) return;
    _isFront ? _ctrl.forward() : _ctrl.reverse();
    setState(() => _isFront = !_isFront);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          double angle = _ctrl.value * math.pi; // 0 → π
          bool front = angle <= math.pi / 2;
          if (!front) angle -= math.pi; // remet le dos à l’endroit
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(angle),
            child: front ? _buildFront() : _buildBack(),
          );
        },
      ),
    );
  }

  /// -------------------------------------------------------------------------
  ///  RECTO – illustration et titre
  /// -------------------------------------------------------------------------
  Widget _buildFront() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(widget.image, fit: BoxFit.cover),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'FontBNJ',
                        fontWeight: FontWeight.bold,
                        fontSize: math.min(w * .18, 52),
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 4),
                            blurRadius: 12,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// -------------------------------------------------------------------------
  ///  VERSO – panneau d’options (SettingsPanel)
  /// -------------------------------------------------------------------------
  Widget _buildBack() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 0), // plus d'air en haut
        child: const SettingsPanel(), // <-- toute la logique est ici
      ),
    );
  }
}