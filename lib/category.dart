import 'dart:ui';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/settings.dart';
import 'game.dart';
import 'game_solo.dart';
import 'utils/popup_empty.dart';
import 'utils/popup_empty_favorite.dart';
import 'paywall.dart';
import 'add_question.dart';
import 'main.dart' show isPremiumNotifier;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'utils/cat_gradients.dart';

// ---------- Lock badge sizing ----------
const double kLockCircleSizePhone  = 50;  // diameter on phones hell
const double kLockCircleSizeTablet = 110; // diameter on tablets
const double kLockIconSizePhone    = 26;  // lock glyph size on phones
const double kLockIconSizeTablet   = 48;  // lock glyph size on tablets

// ---------- Settings banner tuning (phones only) ----------
// ➜ Ces constantes n'affectent QUE l'iPhone (< 768 px).
//    L’iPad garde les valeurs d’origine à l’identique.
const double kSettingsBannerPhoneWidthFactor   = 0.92; // part de la largeur d'écran (iPhone)
const double kSettingsBannerPhoneMaxWidth      = 520;  // largeur max (iPhone)
const double kSettingsBannerPhoneTitleScale    = 0.28; // facteur *hauteur* pour la taille du titre (iPhone)
const double kSettingsBannerTabletTitleScale   = 0.28; // valeur d'origine, conservée sur iPad
const double kSettingsBannerPhoneImageFraction = 1.0;  // fraction de la zone droite occupée par l'illustration (iPhone)

// ---------- PlayWithoutLimits title scale ----------
const double kPlayWithoutLimitsTabletTitleScale = 0.28; // valeur d'origine (iPad)
const double kPlayWithoutLimitsPhoneTitleScale  = 0.24; // légèrement plus petit (iPhone)

// ---------- Category title tuning (phones only) ----------
const double kCategoryTitlePhoneScale = 0.15;   // plus petit sur iPhone (était ~0.18)
const double kCategoryTitleTabletScale = 0.18;  // valeur d'origine (iPad)
const double kCategoryTitlePhoneTop = 4.0;      // remonte le titre dans la tuile (iPhone)
const double kCategoryTitleTabletTop = 12.0;    // valeur d'origine (iPad)

//  ➜ Carte Settings + panneau modale
class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});
  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen>
    with TickerProviderStateMixin {
  // Bannières, FAB, etc.
  static const double _bannerHeightRatio = 0.6;

  /// Indique si l’utilisateur est premium (modifiable via le toggle en haut de l’écran)
  bool _isPremiumUser = false;
  /// Affiche / masque le petit toggle Premium en haut (pratique pour debug)
  bool _showPremiumToggle = false; // passer à false avant release

  late List<_CategoryData> _categories;
  bool _categoriesBuilt = false; // évite double build
  bool _imagesPrecached = false;
  Timer? _temporaryPremiumTimer;

  // --- reacts to any change of the global premium flag ---------------
  void _onPremiumChanged() {
    if (mounted) {
      setState(() => _isPremiumUser = isPremiumNotifier.value);
    }
  }

  @override
  void initState() {
    // _categories will be built in didChangeDependencies with localization
    // Sync initial premium state and listen for further changes
    _isPremiumUser = isPremiumNotifier.value;
    isPremiumNotifier.addListener(_onPremiumChanged);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_categoriesBuilt) {
      final t = AppLocalizations.of(context)!;
      _categories = [
        _CategoryData(
          id: 'discover',
          title: t.catDiscover,
          subtitle: t.catDiscoverSub,
          image: 'assets/illustrations/discover.png',
          gradient: const RadialGradient(
            colors: [Color.fromARGB(255, 153, 50, 255), Color.fromARGB(255, 0, 191, 255)],
            center: Alignment.center,
            radius: 1.15,
          ),
        ),
        _CategoryData(
          id: 'lifestyle',
          title: t.catLifestyle,
          subtitle: t.catLifestyleSub,
          image: 'assets/illustrations/lifestyle.png',
          gradient: catGradients['lifestyle']!,
        ),
        _CategoryData(
          id: 'couple',
          title: t.catCouple,
          subtitle: t.catCoupleSub,
          image: 'assets/illustrations/couple.png',
          gradient: catGradients['couple']!,
        ),
        _CategoryData(
          id: 'fun',
          title: t.catFun,
          subtitle: t.catFunSub,
          image: 'assets/illustrations/party.png',
          gradient: catGradients['fun']!,
        ),
        // Place hardcore_chaos before hot
        _CategoryData(
          id: 'hardcore_chaos',
          title: t.catHardcore,
          subtitle: t.catHardcoreSub,
          image: 'assets/illustrations/hardcore.png',
          // Pour la tuile combinée, on prend le dégradé "chaos"
          gradient: catGradients['chaos']!,
        ),
        _CategoryData(
          id: 'hot',
          title: t.catHot,
          subtitle: t.catHotSub,
          image: 'assets/illustrations/hot.png',
          gradient: catGradients['hot']!,
        ),
        _CategoryData(
          id: 'mix',
          title: t.catMix,
          subtitle: t.catMixSub,
          image: 'assets/illustrations/mix.png',
          // Pas de "mix" dans game.dart : on garde un look cohérent en radial
          gradient: const RadialGradient(
            colors: [Color.fromARGB(255, 0, 162, 255), Color.fromARGB(255, 183, 0, 255)],
            center: Alignment.center,
            radius: 1.15,
          ),
        ),
        _CategoryData(
          id: 'glitch',
          title: t.catGlitch,
          subtitle: t.catGlitchSub,
          image: 'assets/illustrations/glitch.png',
          gradient: catGradients['glitch']!,
        ),
        _CategoryData(
          id: 'add',
          title: t.catAdd,
          subtitle: t.catAddSub,
          image: 'assets/illustrations/add.png',
          gradient: const RadialGradient(
            colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
            center: Alignment.center,
            radius: 1.15,
          ),
        ),
        _CategoryData(
          id: 'mycard',
          title: t.catMyCards,
          subtitle: t.catMyCards,
          image: 'assets/illustrations/mycards.png',
          gradient: const RadialGradient(
            colors: [Color.fromARGB(255, 0, 81, 231), Color.fromARGB(255, 0, 0, 0)],
            center: Alignment.center,
            radius: 1.15,
          ),
        ),
      ];
      _categoriesBuilt = true;
    }
    if (!_imagesPrecached) {
      for (final cat in _categories) {
        precacheImage(AssetImage(cat.image), context);
      }
      precacheImage(const AssetImage('assets/illustrations/playwithoutlimit.png'), context);
      precacheImage(const AssetImage('assets/illustrations/bgNoLimit.png'), context);
      precacheImage(const AssetImage('assets/icons/lock.png'), context);
      _imagesPrecached = true;
    }
  }

  // -------------------------------------------------------------------------
  // Easter‑egg: 15 s press on banner → premium for 20 s
  void _activateEasterEgg() {
    // Passe en Premium 20 s seulement si l’utilisateur est actuellement Free
    if (isPremiumNotifier.value) return; // déjà premium

    isPremiumNotifier.value = true; // active premium globalement

    _temporaryPremiumTimer?.cancel();
    _temporaryPremiumTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) {
        isPremiumNotifier.value = false; // revient à Free
      }
    });
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------
  void _openSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _GlassModal(child: SettingsPanel()),
    );
  }

  @override
  void dispose() {
    isPremiumNotifier.removeListener(_onPremiumChanged);
    _temporaryPremiumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 768;
    const spacing = 10.0;
    final horizontalPadding = isWide ? 24.0 : 12.0;
    final gridWidth = isWide ? size.width * .8 : size.width;
    final cardWidth = (gridWidth - 48 - 20) / 2;
    final bannerHeight = cardWidth * _bannerHeightRatio;

    // ➜ Largeur du bandeau Settings : iPad conserve (gridWidth - 300),
    //    iPhone utilise un facteur + un plafond max.
    final settingsBannerWidth = isWide
        ? (gridWidth - 300)
        : math.min(size.width * kSettingsBannerPhoneWidthFactor, kSettingsBannerPhoneMaxWidth);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(color: const Color.fromARGB(255, 0, 0, 0)),
          // Fixed grain overlay

          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16),
              ),

              // --- Toggle Premium / Free ----------------------------------
              if (_showPremiumToggle)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _isPremiumUser ? 'Premium' : 'Free',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _isPremiumUser,
                          onChanged: (v) => isPremiumNotifier.value = v, // propagate change globally
                          activeColor: Colors.amber,
                        ),
                      ],
                    ),
                  ),
                ),

              if (!_isPremiumUser) ...[
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: gridWidth - 48,
                      height: bannerHeight,
                      child: _PlayWithoutLimitsCard(onEasterEgg: _activateEasterEgg),
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(top: 10)),
              ],

              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: gridWidth,
                    child: ReorderableGridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 0,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: _categories.length,
                      onReorder: _onReorder,
                      dragWidgetBuilderV2: DragWidgetBuilderV2(
                        isScreenshotDragWidget: false,
                        builder: (_, child, __) => Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          clipBehavior: Clip.antiAlias,
                          elevation: 6,
                          child: child,
                        ),
                      ),
                      itemBuilder: (_, index) {
                        final cat = _categories[index];

                        // ----- Settings card (flip) -----
                        if (cat.id == 'settings') {
                          // SettingsCard attend un LinearGradient. Si la donnée est un
                          // RadialGradient (comme les autres tuiles), on fournit un
                          // fallback linéaire cohérent.
                          final LinearGradient settingsLinear =
                              (cat.gradient is LinearGradient)
                                  ? (cat.gradient as LinearGradient)
                                  : const LinearGradient(
                                      colors: [Color(0xFFFFBC01), Color(0xFFF0680E)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    );

                          return SettingsCard(
                            key: ValueKey(cat.id),
                            title: cat.title,
                            image: cat.image,
                            gradient: settingsLinear,
                          );
                        }

                        // ----- Verrou premium -----
                        final bool locked = !_isPremiumUser &&
                            cat.id != 'discover' &&
                            cat.id != 'add' &&
                            cat.id != 'settings_card';

                        return _CategoryCard(
                          key: ValueKey(cat.id),
                          data: cat,
                          locked: locked,
                          onTap: () {
                            if (locked) {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const PaywallPage(),
                              );
                            } else {
                              _launchGame(cat);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),

              // --- Settings banner spacing (same as top banner bottom margin)
              const SliverPadding(padding: EdgeInsets.only(top: 10)),

              // --- Settings banner at the end -----------------------------
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: settingsBannerWidth, // ← iPhone ajustable ; iPad inchangé
                    height: bannerHeight,
                    child: _SettingsBanner(onOpen: _openSettingsModal),
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),

        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Reste pour compat : ex. si besoin d'un gradient simple ailleurs
  static LinearGradient _buildGradient(Color start, Color end) => LinearGradient(
        colors: [start, end],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
    });
  }

  // Convertit n'importe quel Gradient en LinearGradient pour les écrans
  // qui exigent spécifiquement un LinearGradient (ex: SoloGameScreen).
  LinearGradient _asLinearGradient(Gradient g) {
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
    // Fallback très conservateur
    return const LinearGradient(
      colors: [Colors.black, Colors.black],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Future<void> _launchGame(_CategoryData cat) async {
    if (cat.id == 'settings_card') {
      _openSettingsModal();
      return;
    }
    if (cat.id == 'add') {
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, anim, __) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: const AddQuestionPage(),
        ),
      ));
      return;
    }

    if (cat.id == 'mycard') {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getStringList('custom_questions') ?? []).isEmpty) {
        showDialog(context: context, builder: (_) => const PopupEmpty());
        return;
      }
    }

    if (cat.id == 'favorites') {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getStringList('favorite_questions') ?? []).isEmpty) {
        showDialog(context: context, builder: (_) => const PopupEmptyFavorite());
        return;
      }
    }

    final solo = Settings.get().soloOn;

    // Cas spécial pour la catégorie combinée hardcore+chaos
    if (cat.id == 'hardcore_chaos') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => solo
              ? SoloGameScreen(
                  categoryId: 'hardcore,chaos',
                  backgroundGradient: _asLinearGradient(cat.gradient),
                  useLocalQuestions: false,
                )
              : HomeScreen(
                  categoryId: 'hardcore,chaos',
                  backgroundGradient: cat.gradient,
                  useLocalQuestions: false,
                ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => solo
            ? SoloGameScreen(
                categoryId: cat.id,
                backgroundGradient: _asLinearGradient(cat.gradient),
                useLocalQuestions: cat.id == 'mycard',
              )
            : HomeScreen(
                categoryId: cat.id,
                backgroundGradient: cat.gradient,
                useLocalQuestions: cat.id == 'mycard',
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  PLAY WITHOUT LIMITS CARD  (modifié pour l'easter egg)
// ---------------------------------------------------------------------------
class _PlayWithoutLimitsCard extends StatefulWidget {
  final VoidCallback onEasterEgg;
  const _PlayWithoutLimitsCard({Key? key, required this.onEasterEgg}) : super(key: key);

  @override
  State<_PlayWithoutLimitsCard> createState() => _PlayWithoutLimitsCardState();
}

class _PlayWithoutLimitsCardState extends State<_PlayWithoutLimitsCard> {
  Timer? _holdTimer;

  void _startHold() {
    _holdTimer = Timer(const Duration(seconds: 15), () {
      widget.onEasterEgg();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _cancelHold(),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PaywallPage(),
      ),
      child: _buildCardContent(),
    );
  }

  /// Extracted previous UI code so we can reuse it.
  Widget _buildCardContent() {
    final l10n = AppLocalizations.of(context)!;
    final String playWithoutLimitsTitle = (
      '${l10n.playWord}\n${l10n.withoutWord}\n${l10n.limitsWord}'
    ).toUpperCase();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: const [Color(0xFFFFBC01), Color(0xFFF0680E)],
            center: const Alignment(-0.2, -0.2),
            radius: 1.1,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        // (padding removed here)
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background illustration over the gradient (like category cards)
            Positioned.fill(
              child: Image.asset(
                'assets/illustrations/bgNoLimit.png',
                fit: BoxFit.cover,
              ),
            ),
            // Foreground content (title + character) avec padding seulement sur le contenu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: LayoutBuilder(
                      builder: (_, c) {
                        final bool isTablet = MediaQuery.of(context).size.width >= 768;
                        final double titleScale = isTablet
                            ? kPlayWithoutLimitsTabletTitleScale
                            : kPlayWithoutLimitsPhoneTitleScale;
                        final double maxF = c.maxHeight * titleScale;
                        return Center(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outline text (stroke)
                                Text(
                                  playWithoutLimitsTitle,
                                  style: TextStyle(
                                    fontFamily: 'FeastOfFlesh',
                                    fontWeight: FontWeight.bold,
                                    fontSize: maxF,
                                    height: 1,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 12
                                      ..color = Colors.black,
                                  ),
                                ),
                                // Fill text (white) with drop shadow
                                Text(
                                  playWithoutLimitsTitle,
                                  style: TextStyle(
                                    fontFamily: 'FeastOfFlesh',
                                    fontWeight: FontWeight.bold,
                                    fontSize: maxF,
                                    height: 1,
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(offset: Offset(0, 2), blurRadius: 8, color: Colors.black45),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, right: 25),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.centerRight,
                        child: Image.asset('assets/illustrations/playwithoutlimite.png'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  SETTINGS BANNER (mirrors PlayWithoutLimitsCard visual)
// ---------------------------------------------------------------------------
class _SettingsBanner extends StatelessWidget {
  final VoidCallback onOpen;
  const _SettingsBanner({Key? key, required this.onOpen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final String title = t.settingsTitle.toUpperCase();

    // ➜ iPad : valeurs d'origine ; iPhone : valeurs ajustables via constantes.
    final bool isTablet = MediaQuery.of(context).size.width >= 768;
    final double _titleScale = isTablet
        ? kSettingsBannerTabletTitleScale
        : kSettingsBannerPhoneTitleScale;
    final double _imageFraction = isTablet ? 1.0 : kSettingsBannerPhoneImageFraction;

    return GestureDetector(
      onTap: onOpen,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: const [Color(0xFFFFBC01), Color(0xFFF0680E)],
              center: const Alignment(-0.2, -0.2),
              radius: 1.1,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background illustration (same as first banner)
              Positioned.fill(
                child: Image.asset(
                  'assets/illustrations/bgNoLimitSettings.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Foreground content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final maxF = c.maxHeight * _titleScale; // ← iPhone ajustable
                          return Center(
                            child: FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontFamily: 'FeastOfFlesh',
                                      fontWeight: FontWeight.bold,
                                      fontSize: maxF,
                                      height: 1,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 12
                                        ..color = Colors.black,
                                    ),
                                  ),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontFamily: 'FeastOfFlesh',
                                      fontWeight: FontWeight.bold,
                                      fontSize: maxF,
                                      height: 1,
                                      color: Colors.white,
                                      shadows: const [
                                        Shadow(offset: Offset(0, 2), blurRadius: 8, color: Colors.black45),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 25),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FractionallySizedBox(
                            widthFactor: _imageFraction, // ← iPhone ajustable ; iPad=1.0
                            child: FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.centerRight,
                              child: Image.asset('assets/illustrations/settings.png'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  DATA MODEL + CATEGORY CARD
// ---------------------------------------------------------------------------
class _CategoryData {
  final String id;
  final String title;
  final String subtitle;
  final String image;
  final Gradient gradient; // ← Gradient (Radial) pour correspondre exactement à game.dart
  const _CategoryData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.gradient,
  });
}

class _CategoryCard extends StatelessWidget {
  final _CategoryData data;
  final VoidCallback onTap;
  final bool locked;

  const _CategoryCard({
    required Key key,
    required this.data,
    required this.onTap,
    this.locked = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            // Utilise directement le Gradient fourni (mêmes paramètres que game.dart)
            gradient: data.gradient,
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
              builder: (_, c) {
                final w = c.maxWidth;
                final bool isTablet = MediaQuery.of(context).size.width >= 768;
                final double titleScale = isTablet ? kCategoryTitleTabletScale : kCategoryTitlePhoneScale;
                final double fontSize = math.min(w * titleScale, 52);
                final double titleTop = isTablet ? kCategoryTitleTabletTop : kCategoryTitlePhoneTop;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(data.image, fit: BoxFit.cover),
                    Positioned(
                      top: titleTop,
                      left: 12,
                      right: 12,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outline text (stroke)
                            Text(
                              data.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'FeastOfFlesh',
                                fontWeight: FontWeight.bold,
                                fontSize: fontSize,
                                foreground: Paint()
                                  ..style = PaintingStyle.stroke
                                  ..strokeWidth = 12
                                  ..color = Colors.black,
                              ),
                            ),
                            // Fill text (white) with drop shadow
                            Text(
                              data.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'FeastOfFlesh',
                                fontWeight: FontWeight.bold,
                                fontSize: fontSize,
                                color: Colors.white,
                                shadows: const [
                                  Shadow(offset: Offset(0, 4), blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---------- Glass lock ----------
                    if (locked)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Builder(
                          builder: (context) {
                            final bool tablet = MediaQuery.of(context).size.width >= 768;
                            final double circleSize =
                                tablet ? kLockCircleSizeTablet : kLockCircleSizePhone;
                            final double iconSize =
                                tablet ? kLockIconSizeTablet : kLockIconSizePhone;
                            final double padding = (circleSize - iconSize) / 2;

                            return ClipOval(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                                child: Container(
                                  width: circleSize,
                                  height: circleSize,
                                  padding: EdgeInsets.all(padding),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.25),
                                    border: Border.all(
                                      color: Colors.black.withOpacity(0.5),
                                      width: 2,
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/icons/lock.png',
                                    width: iconSize,
                                    height: iconSize,
                                    color: Colors.black,
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  GLASS FAB & GLASS MODAL (inchangé)
// ---------------------------------------------------------------------------

class _GlassModal extends StatelessWidget {
  final Widget child;
  const _GlassModal({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}