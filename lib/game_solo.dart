import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/particule_bg.dart';
import 'utils/popup_game_over.dart';
import 'utils/popup_empty_favorite.dart';
import 'utils/settings.dart';
import 'utils/cat_gradients.dart';

/// ------------------------------------------------------------
///  Helper : convertir n'importe quel Gradient en LinearGradient
///  (SoloGameScreen utilise un LinearGradient pour l'arrière-plan)
/// ------------------------------------------------------------
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
  // Fallback sécurisé
  return const LinearGradient(
    colors: [Color(0xFF06ACFF), Color(0xFF02FFFB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// ------------------------------------------------------------
///  Modèles internes
/// ------------------------------------------------------------
class _Q {
  _Q(this.id, this.text);
  final String id;
  final String text;
}

class _MixQ {
  _MixQ(this.id, this.text, this.catId);
  final String id;
  final String text;
  final String catId;
}

/// ------------------------------------------------------------
///                SOLO  GAME  SCREEN
/// ------------------------------------------------------------
class SoloGameScreen extends StatefulWidget {
  const SoloGameScreen({
    Key? key,
    this.categoryId,
    this.backgroundGradient,
    this.useLocalQuestions = false,
  }) : super(key: key);

  final String? categoryId;                 // id catégorie
  final LinearGradient? backgroundGradient; // gradient reçu
  final bool useLocalQuestions;             // My Cards

  @override
  State<SoloGameScreen> createState() => _SoloGameScreenState();
}

class _SoloGameScreenState extends State<SoloGameScreen>
    with TickerProviderStateMixin {
  /* -------------------- Settings -------------------- */
  late final bool _soundOn = Settings.get().soundOn;
  late final int _initialLives = Settings.get().selectedLives;          // 1‑3‑5
  late final int _slideDuration = (Settings.get().selectedTime * 1000).round();

  /* -------------------- Data -------------------- */
  static const double _cardMinHeight = 100;
  final List<_Q> _questions = [];           // catégories simples
  final List<_MixQ> _mixQuestions = [];     // catégorie MIX / Fav / Discover
  String? _lastMixCat;
  late String _question;
  late String _currentQuestionId;
  // Langue du téléphone (ex. 'fr', 'en', 'es')
  late final String _langCode;

  /* -------------------- Animations -------------------- */
  late final AnimationController _slideCtrl;
  late AlignmentTween _slideTween;
  late Animation<Alignment> _slideAnim;

  // Lottie life‑out
  late final List<AnimationController> _lifeCtrls;

  /* -------------------- State -------------------- */
  bool _countdownDone = false;
  bool _visible = true;
  bool _slideEnding = false;
  bool _isPaused = false;
  late int _lives;

  // gradient courant
  late LinearGradient _currentBg;

  final GlobalKey _cardKey = GlobalKey();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _boomPlayer  = AudioPlayer();   // lecteur dédié pour boom.mp3
  Timer? _slideEndingTimer;

  /* -------------------- Init -------------------- */
  @override
  void initState() {
    super.initState();
    _langCode = PlatformDispatcher.instance.locale.languageCode;

    // gradient de départ
    final Gradient? g = catGradients[widget.categoryId ?? ''];
    _currentBg = widget.backgroundGradient ??
        (g != null
            ? _asLinearGradient(g)
            : const LinearGradient(
                colors: [Color(0xFF06ACFF), Color(0xFF02FFFB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ));

    _currentQuestionId = '';
    _lives = _initialLives;
    _initQuestions();
    _initAnimations();
  }

  @override
  void dispose() {
    _slideEndingTimer?.cancel();
    _slideCtrl.dispose();
    for (final c in _lifeCtrls) c.dispose();
    _audioPlayer.dispose();
    _boomPlayer.dispose();
    super.dispose();
  }

  /* -------------------- Questions -------------------- */
  void _initQuestions() {
    if (widget.useLocalQuestions) {
      _loadQuestionsFromPrefs();
    } else if (widget.categoryId == 'mix') {
      _loadQuestionsFromMix();
    } else if (widget.categoryId == 'favorites') {
      _loadQuestionsFromFavorites();
    } else if (widget.categoryId == 'discover') {
      _loadQuestionsFromDiscover();
    } else if (widget.categoryId != null) {
      _loadQuestionsFromAsset(widget.categoryId!);
    } else {
      _questions.add(_Q('default', 'Une anecdote gênante'));
      _question = _questions.first.text;
      _currentQuestionId = _questions.first.id;
    }
  }

  /// Joue boom.mp3 une seule fois quand l’anim lifeOut atteint 80 %
  void _attachBoomSound(AnimationController ctrl) {
    bool played = false;
    ctrl.addListener(() {
      final p = ctrl.value;
      if (!played && p >= 0.80) {
        played = true;
        if (_soundOn) {
          // Son dérivé du JSON de vie sélectionné
          final String jsonPath = Settings.get().selectedLifeJson;   // ex: assets/illustrations/fire.json
          final String fileName = jsonPath.split('/').last;          // fire.json
          final String baseName = fileName.replaceAll('.json', '');  // fire
          final String soundPath = 'sound/$baseName.mp3';            // sound/fire.mp3
          _boomPlayer.play(AssetSource(soundPath));
        }
      }
      if (p == 0.0) played = false; // ré‑arme
    });
  }

  /// Calcule l’échelle du cœur : 1× jusqu’à 80 %, 1 → 3 entre 80‑85 %, puis 3×
  double _lifeScale(double progress) {
    if (progress < 0.80) return 1.0;
    if (progress <= 0.85) {
      final t = (progress - 0.80) / 0.05; // 0‑1
      return 1.0 + t * 2.0;               // 1‑3
    }
    return 3.0;
  }

  /* -------------------- Animations -------------------- */
  void _initAnimations() {
    _slideCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _slideDuration),
    );
    _slideTween = AlignmentTween(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    _slideAnim = _slideTween.animate(_slideCtrl)
      ..addStatusListener(_onSlideStatus);

    _lifeCtrls =
        List.generate(_initialLives, (_) => AnimationController(vsync: this));
    for (final c in _lifeCtrls) _attachBoomSound(c);
  }

  /* -------------------- Slide flow -------------------- */
  void _startSlide() {
    _slideEnding = false;
    _slideTween = AlignmentTween(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    _slideAnim = _slideTween.animate(_slideCtrl);
    _slideCtrl
      ..reset()
      ..forward();

    _slideEndingTimer = Timer(
      _slideCtrl.duration! - const Duration(milliseconds: 200),
      () => mounted ? setState(() => _slideEnding = true) : null,
    );
  }

  void _resetSlide() {
    _slideCtrl.reset();
    _slideEndingTimer?.cancel();
    _startSlide();
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    // ---- Loser ! -------------------------------------------------------
    setState(() {
      _slideEnding = false;
      _question = '👇🏻 Loser ! 👇🏻';
      _visible = true;
      _currentQuestionId = ''; // pas de favoris ici
    });

    if (_soundOn) {
      _audioPlayer.play(AssetSource('sound/haha.mp3'));
    }

    // ---- retire une vie -----------------------------------------------
    setState(() => _lives--);
    if (_lives < _initialLives) {
      final idx = _initialLives - 1 - _lives;
      _lifeCtrls[idx]
        ..reset()
        ..forward();
    }

    // ---- Game Over ? ---------------------------------------------------
    if (_lives == 0) {
      _showGameOver();
      return;
    }

    // ---- Prépare question suivante ------------------------------------
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _visible = false;
        _countdownDone = false;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        _prepareNextQuestion();
      });
    });
  }

  /* -------------------- Question pick -------------------- */
  void _prepareNextQuestion() {
    if (widget.categoryId == 'mix' ||
        widget.categoryId == 'favorites' ||
        widget.categoryId == 'discover') {
      _pickNextMixQuestion();
    } else {
      final _Q next = (_questions..shuffle()).first;
      _question = next.text;
      _currentQuestionId = next.id;

      // --- BG dynamique selon la source réelle (hardcore / chaos) ---
      final String srcCat = next.id.split('_').first;
      if (catGradients.containsKey(srcCat)) {
        _currentBg = _asLinearGradient(catGradients[srcCat]!);
      }
    }

    setState(() {
      _visible = true;
    });
  }

  void _pickNextMixQuestion() {
    if (_mixQuestions.isEmpty) return;

    final cats = _mixQuestions.where((q) => q.catId != _lastMixCat).toList();
    final _MixQ next =
        cats.isNotEmpty ? cats[Random().nextInt(cats.length)] : _mixQuestions.first;
    _lastMixCat = next.catId;

    setState(() {
      _question = next.text;
      _currentQuestionId = next.id;
      _currentBg = _asLinearGradient(catGradients[next.catId]!);
    });
  }

  /* -------------------- UI -------------------- */
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 768;
    final fontSize = isTablet ? 36.0 : 22.0;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(gradient: _currentBg),
        child: Stack(
          children: [
            const Positioned.fill(child: ParticleBackground()),
            if (_countdownDone) _buildQuestionCard(fontSize),
            if (!_countdownDone) _buildCountdown(),
            _buildLivesRow(),
            _buildClose(isTablet ? 50 : 30),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(double fontSize) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => _handleTap(d),
        child: AnimatedBuilder(
          animation: _slideCtrl,
          builder: (_, __) => Align(
            alignment: _slideAnim.value,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _visible ? 1 : 0,
              child: _QuestionCard(
                key: _cardKey,
                text: _question,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      );

  Widget _buildCountdown() => Center(
        child: Lottie.asset(
          'assets/countdown.json',
          width: 600,
          repeat: false,
          onLoaded: (c) => Future.delayed(c.duration, () {
            setState(() {
              _countdownDone = true;
              _startSlide();
            });
          }),
        ),
      );

  Widget _buildLivesRow() {
    final w = MediaQuery.of(context).size.width;
    final bool tablet = w >= 768;
    final double heartSize = tablet ? 100 : (_initialLives == 5 ? 60 : 60);

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          _initialLives,
          (i) => AnimatedBuilder(
            animation: _lifeCtrls[i],
            builder: (_, child) => Transform.scale(
              scale: _lifeScale(_lifeCtrls[i].value),
              child: child,
            ),
            child: SizedBox(
              width: heartSize,
              height: heartSize,
              child: Lottie.asset(
                // ← JSON de vie choisi dans Settings
                Settings.get().selectedLifeJson,
                controller: _lifeCtrls[i],
                repeat: false,
                onLoaded: (comp) => _lifeCtrls[i].duration = comp.duration,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClose(double iconSize) => Positioned(
        top: 50,
        right: 30,
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(Icons.close, color: Colors.white, size: iconSize),
        ),
      );

  /* -------------------- Tap logic -------------------- */
  void _handleTap(TapDownDetails d) {
    final insideCard = _isTapInsideCard(d.globalPosition);

    // ---------- Pause / reprise ----------
    if (insideCard) {
      HapticFeedback.lightImpact();
      setState(() => _isPaused = !_isPaused);

      if (_isPaused) {
        _slideCtrl.stop();
        _slideEndingTimer?.cancel();
        _slideEnding = false;
      } else {
        final remaining = _slideCtrl.duration! * (1 - _slideCtrl.value);
        final delay = remaining - const Duration(milliseconds: 200);
        if (delay > Duration.zero) {
          _slideEndingTimer =
              Timer(delay, () => mounted ? setState(() => _slideEnding = true) : null);
        } else {
          _slideEnding = true;
        }
        _slideCtrl.forward();
      }
      return;
    }

    // ---------- Reset (tap dessous) ----------
    if (_isPaused) return; // en pause : on ignore les taps sous la carte

    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final cardRect =
        MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

    if (d.globalPosition.dy > cardRect.bottom + 10) {
      HapticFeedback.lightImpact();
      _resetSlide();
    }
  }

  bool _isTapInsideCard(Offset globalPos) {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect =
        MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    return rect.contains(globalPos);
  }

  /* -------------------- Game over -------------------- */
  Future<void> _showGameOver() async {
    final result = await showDialog<String>(
      barrierDismissible: false,
      context: context,
      builder: (_) => const PopupGameOver(),
    );
    if (!mounted) return;
    if (result == 'restart') {
      setState(() {
        _lives = _initialLives;
        _prepareNextQuestion();
        _countdownDone = false;
        _visible = false;
      });
      Future.delayed(const Duration(milliseconds: 500), _resetSlide);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /* -------------------- Loading helpers -------------------- */
  Future<void> _loadQuestionsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_questions') ?? [];
    if (saved.isNotEmpty) {
      _questions
        ..clear()
        ..addAll(saved.map((t) => _Q(t, t)));
      _prepareNextQuestion();
    }
  }

  Future<void> _loadQuestionsFromAsset(String categoryId) async {
    // Supporte les IDs composites "a,b,c" et tague chaque entrée par sa vraie source.
    List<String> sourceCats;
    if (categoryId.contains(',')) {
      sourceCats = categoryId
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } else {
      sourceCats = [categoryId];
    }

    final List<_Q> loaded = [];

    for (final cat in sourceCats) {
      try {
        final raw = await rootBundle.loadString('assets/bdd/$cat.json');
        final Map<String, dynamic> jsonMap = json.decode(raw);

        for (final entry in jsonMap.entries) {
          final Map<String, dynamic> item = entry.value is Map<String, dynamic>
              ? (entry.value as Map<String, dynamic>)
              : <String, dynamic>{};

          final String? q = _localizedText(item['options']?[0]?['text']);
          if (q == null || q.trim().isEmpty) continue;

          // Si présent, on prend item['category'] (ex: 'chaos') comme vraie source.
          final String srcCat =
              (item['category'] is String && (item['category'] as String).trim().isNotEmpty)
                  ? (item['category'] as String).trim()
                  : cat;

          loaded.add(_Q('${srcCat}_${entry.key}', q.trim()));
        }
      } catch (e) {
        debugPrint('⚠️ Impossible de charger $cat.json : $e');
      }
    }

    if (loaded.isNotEmpty) {
      _questions
        ..clear()
        ..addAll(loaded);
      _prepareNextQuestion(); // BG mis à jour via srcCat dans _prepareNextQuestion
    }
  }

  /* -------------------- Mix / Favorites / Discover -------------------- */
  Future<void> _loadQuestionsFromMix() async {
    const cats = [
      'lifestyle',
      'couple',
      'chaos',
      'hot',
      'hardcore',
      'fun',
      'glitch',
    ];

    final List<_MixQ> tmp = [];
    for (final cat in cats) {
      try {
        final raw = await rootBundle.loadString('assets/bdd/$cat.json');
        final Map<String, dynamic> jsonMap = json.decode(raw);
        for (final entry in jsonMap.entries) {
          final String? q = _localizedText(entry.value['options']?[0]?['text']);
          if (q != null && q.trim().isNotEmpty) {
            tmp.add(_MixQ('${cat}_${entry.key}', q.trim(), cat));
          }
        }
      } catch (_) {
        debugPrint('⛔️ Mix : $cat.json manquant ou invalide');
      }
    }

    if (tmp.isNotEmpty) {
      tmp.shuffle();
      _mixQuestions
        ..clear()
        ..addAll(tmp);
      _pickNextMixQuestion();
    }
  }

  Future<void> _loadQuestionsFromFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favIdsRaw = prefs.getStringList('favorite_questions') ?? [];
    final favIds = favIdsRaw.where((id) => id.trim().isNotEmpty).toList();
    if (favIds.isEmpty) {
      _showEmptyFavoriteAndExit();
      return;
    }

    final Map<String, Map<String, dynamic>> jsonCache = {};
    final List<_MixQ> tmp = [];

    for (final id in favIds) {
      final int sep = id.indexOf('_');
      if (sep == -1) continue;

      final String cat = id.substring(0, sep);
      final String key = id.substring(sep + 1);

      if (!jsonCache.containsKey(cat)) {
        try {
          final raw = await rootBundle.loadString('assets/bdd/$cat.json');
          jsonCache[cat] = json.decode(raw);
        } catch (_) {
          continue;
        }
      }

      final Map<String, dynamic>? item = jsonCache[cat]?[key];
      final String? q = _localizedText(item?['options']?[0]?['text']);
      if (q != null && q.trim().isNotEmpty) {
        tmp.add(_MixQ(id, q.trim(), cat));
      }
    }

    if (tmp.isEmpty) {
      _showEmptyFavoriteAndExit();
      return;
    }

    tmp.shuffle();
    _mixQuestions
      ..clear()
      ..addAll(tmp);
    _pickNextMixQuestion();
  }

  Future<void> _loadQuestionsFromDiscover() async {
    try {
      final raw = await rootBundle.loadString('assets/bdd/discover.json');
      final Map<String, dynamic> jsonMap = json.decode(raw);

      final List<_MixQ> tmp = [];
      for (final entry in jsonMap.entries) {
        final Map<String, dynamic> item = entry.value;
        final String? q = _localizedText(item['options']?[0]?['text']);
        final String? catId = item['category'];
        if (q != null &&
            catId != null &&
            q.trim().isNotEmpty &&
            catGradients.containsKey(catId)) {
          tmp.add(_MixQ('discover_${entry.key}', q.trim(), catId));
        }
      }

      if (tmp.isEmpty) {
        _showEmptyFavoriteAndExit();
        return;
      }

      tmp.shuffle();
      _mixQuestions
        ..clear()
        ..addAll(tmp);
      _pickNextMixQuestion();
    } catch (_) {
      _showEmptyFavoriteAndExit();
    }
  }

  /// Retourne la chaîne localisée à partir de la map `text`.
  String? _localizedText(Map<String, dynamic>? textMap) {
    if (textMap == null) return null;
    return textMap[_langCode] ??
        textMap['en'] ??
        (textMap.isNotEmpty ? textMap.values.first as String? : null);
  }

  Future<void> _showEmptyFavoriteAndExit() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => const PopupEmptyFavorite(),
      );
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }
}

/* ------------------------------------------------------------
                        Question Card
------------------------------------------------------------ */
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    Key? key,
    required this.text,
    required this.fontSize,
  }) : super(key: key);

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 1,
      child: IntrinsicHeight(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              constraints:
                  const BoxConstraints(minHeight: _SoloGameScreenState._cardMinHeight),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.8)),
              ),
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}