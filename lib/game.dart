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

/// Feature flag: show/hide the Favorite button on the question card.
const bool _showFavoriteButton = false;

/// Modèle interne générique (id + texte)
class _Q {
  _Q(this.id, this.text);
  final String id;
  final String text;
}

/// Modèle interne pour MIX (id + texte + id catégorie)
class _MixQ {
  _MixQ(this.id, this.text, this.catId);
  final String id;
  final String text;
  final String catId;
}

/// ------------------------------------------------------------
///  ÉCRAN DE JEU  (HomeScreen)
/// ------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.categoryId,
    this.backgroundGradient,
    this.useLocalQuestions = false,
  });

  final String? categoryId;                // id catégorie
  final Gradient? backgroundGradient;      // gradient reçu
  final bool useLocalQuestions;            // My Cards

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum Direction { down, up }

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ─────────── paramètres/utilisateur ───────────
  late final String _langCode;            // ex: 'en', 'fr', 'es'
  late final bool _soundOnSetting;
  late final bool _soloMode;
  late final int  _initialLives;
  late final int  _slideDurationMs;

  // ─────────── données/questions ───────────
  static const double _cardMinHeight = 100.0;
  final List<_Q> _questions = [];          // catégories simples
  final List<_MixQ> _mixQuestions = [];    // catégorie MIX
  late String _question;
  late String _currentQuestionId;
  String? _lastMixCat;                     // évite doublon cat

  // [FAVORITES]
  final Set<String> _favorites = {};
  bool get _isCurrentFavorite =>
      _currentQuestionId.isNotEmpty && _favorites.contains(_currentQuestionId);

  // gradient courant (animé)
  late Gradient _currentBg;

  // ─────────── animations principales ───────────
  late final AnimationController _slideCtrl;
  late AlignmentTween _slideTween;
  late Animation<Alignment> _slideAnim;

  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  late final AnimationController _topPumpCtrl;
  late final Animation<double> _topPumpAnim;
  late final AnimationController _bottomPumpCtrl;
  late final Animation<double> _bottomPumpAnim;

  // ----- Lottie “life‑out” : un contrôleur par coeur -----
  late final List<AnimationController> _lifeCtrlsTop;
  late final List<AnimationController> _lifeCtrlsBottom;

  // ----- Pop d’apparition des icônes (favori + pause/play) -----
  late final AnimationController _iconsPopCtrl;
  late final Animation<double> _iconsPopAnim;

  TweenSequence<double> get _pumpSequence => TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.5), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.5, end: 1), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: .8),
        TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: .8),
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.2), weight: .6),
        TweenSequenceItem(tween: Tween(begin: 1.2, end: 1), weight: .6),
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.1), weight: .4),
        TweenSequenceItem(tween: Tween(begin: 1.1, end: 1), weight: .4),
        TweenSequenceItem(tween: Tween(begin: 1, end: 1.05), weight: .2),
        TweenSequenceItem(tween: Tween(begin: 1.05, end: 1), weight: .2),
        TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: .3),
      ]);

  // ─────────── état logique ───────────
  Direction _direction = Direction.down;
  double _flipTurns = 0.0;                // 0 → 0.5 → 1 …
  bool _countdownDone = false;
  bool _isPaused = false;
  bool _visible = true;
  bool _slideEnding = false;
  bool _bonusEnabled = true;
  bool _bonusInterruption = false;
  int _dirChanges = 0; // show bonus buttons after 2 direction changes
  static const int _bonusAppearAfterTurns = 100; // configurable threshold

  // ----- vies -----
  late int _livesTop;
  late int _livesBottom;

  // ----- bonus scale -----
  double _topChronoScale = 1;
  double _bottomChronoScale = 1;
  double _topReverseScale = 1;
  double _bottomReverseScale = 1;

  // ----- typing -----
  bool _isTyping = false;
  String _displayedText = '';
  static const int _typingCharDelayMs = 50; // vitesse du typewriter
  bool _sideIconsVisible = false;

  final GlobalKey _cardKey = GlobalKey();
  final AudioPlayer _audioPlayer = AudioPlayer();   // sons généraux
  final AudioPlayer _boomPlayer  = AudioPlayer();   // boom indépendant
  Timer? _slideEndingTimer;

  // ------------------------------------------------------------
  //              SEEN QUESTIONS (anti‑répétition)
  // ------------------------------------------------------------
  String get _seenPrefKey =>
      'seen_${widget.categoryId ?? (widget.useLocalQuestions ? 'local' : 'default')}';

  Future<List<String>> _getSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_seenPrefKey) ?? <String>[];
  }

  Future<void> _addSeenId(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_seenPrefKey) ?? <String>[];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList(_seenPrefKey, list);
    }
  }

  Future<void> _resetSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenPrefKey);
  }

  // ------------------------------------------------------------
  // ---------------- life‑cycle ---------------
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _langCode = PlatformDispatcher.instance.locale.languageCode;
    final sett = Settings.get();
    _soundOnSetting = sett.soundOn;
    _soloMode       = sett.soloOn;
    _initialLives   = sett.selectedLives;              // 1, 3, 5
    _slideDurationMs = (sett.selectedTime * 1000).round(); // 3300, 6900, 9600

    // gradient de départ
    _currentBg = widget.backgroundGradient ??
        catGradients[widget.categoryId ?? ''] ??
        const RadialGradient(
          colors: [Color(0xFF06ACFF), Color(0xFF02FFFB)],
          center: Alignment.center,
          radius: 1.15,
        );

    _currentQuestionId = '';
    _initQuestions();
    _livesTop = _initialLives;
    _livesBottom = _initialLives;
    _initAnimations();
    _loadFavorites();
    Settings.get().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    Settings.get().removeListener(_onSettingsChanged);
    _slideEndingTimer?.cancel();
    _slideCtrl.dispose();
    _scaleCtrl.dispose();
    _shakeCtrl.dispose();
    _topPumpCtrl.dispose();
    _bottomPumpCtrl.dispose();
    for (final c in _lifeCtrlsTop) c.dispose();
    for (final c in _lifeCtrlsBottom) c.dispose();
    _iconsPopCtrl.dispose();
    _audioPlayer.dispose();
    _boomPlayer.dispose();          // ← libération du lecteur boom
    super.dispose();
  }

  // ------------------------------------------------------------
  //                     INITIALISATIONS
  // ------------------------------------------------------------
  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

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
      _questions.addAll([
        _Q('default_0', 'Un aliment qu’on mange avec les doigts'),
        _Q('default_1', 'Un objet dans une trousse'),
        _Q('default_2', 'Une série que tout le monde connaît'),
      ]);
      final _Q first = (_questions..shuffle()).first;
      _question = first.text;
      _currentQuestionId = first.id;
      _addSeenId(first.id); // ---- mémorise
    }
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('favorite_questions') ?? <String>[];
    setState(() => _favorites.addAll(favs));
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_questions', _favorites.toList());
  }

  void _toggleFavorite() {
    if (_currentQuestionId.isEmpty) return;
    setState(() {
      if (_isCurrentFavorite) {
        _favorites.remove(_currentQuestionId);
      } else {
        _favorites.add(_currentQuestionId);
      }
    });
    _saveFavorites();
  }

  void _initAnimations() {
    _slideCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _slideDurationMs),
    );
    _slideTween = AlignmentTween(begin: Alignment.center, end: Alignment.center);
    _slideAnim = _slideTween.animate(_slideCtrl);

    _scaleCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);

    _shakeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(_shakeCtrl);

    _topPumpCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _bottomPumpCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _topPumpAnim = _pumpSequence.animate(_topPumpCtrl);
    _bottomPumpAnim = _pumpSequence.animate(_bottomPumpCtrl);

    // ----- Lottie life‑out : contrôleurs par joueur selon le nombre de vies -----
    _lifeCtrlsTop = List.generate(_initialLives, (_) => AnimationController(vsync: this));
    _lifeCtrlsBottom = List.generate(_initialLives, (_) => AnimationController(vsync: this));

    // ---- BOOM à 80 % de chaque anim lifeOut ----
    for (final c in _lifeCtrlsTop)    _attachBoomSound(c);
    for (final c in _lifeCtrlsBottom) _attachBoomSound(c);

    // ---- Pop apparition icônes (favori + pause/play)
    _iconsPopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _iconsPopAnim = CurvedAnimation(parent: _iconsPopCtrl, curve: Curves.elasticOut);

    _slideCtrl.addStatusListener(_onSlideCompleted);
  }

  // ------------------------------------------------------------
  //        BOOM sound à 80 % de l’animation lifeOut
  // ------------------------------------------------------------
  void _attachBoomSound(AnimationController ctrl) {
    bool played = false;
    ctrl.addListener(() {
      // déclenche une seule fois par cycle
      if (!played && ctrl.value >= 0.80) {
        played = true;
        if (_soundOnSetting) {
          // Derive sound from selected life JSON: e.g. assets/illustrations/fire.json -> sound/fire.mp3
          final String jsonPath = Settings.get().selectedLifeJson;
          final String fileName = jsonPath.split('/').last;          // e.g. fire.json
          final String baseName = fileName.replaceAll('.json', '');  // fire
          final String soundPath = 'sound/$baseName.mp3';            // AssetSource expects path without 'assets/'
          _boomPlayer.play(AssetSource(soundPath));
        }
      }
      // ré‑arme quand on remet l’anim à zéro
      if (ctrl.value == 0.0) {
        played = false;
      }
    });
  }

  /// Calcule l’échelle du cœur en fonction de la progression de l’anim lifeOut
  double _lifeScale(double progress) {
    if (progress < 0.80) return 1.0;
    if (progress <= 0.85) {
      final t = (progress - 0.80) / 0.05; // 0 → 1
      return 1.0 + t * 2.0;               // 1 → 3
    }
    return 3.0;
  }

  // ------------------------------------------------------------
  //                       GAME FLOW
  // ------------------------------------------------------------
  void _launchCountdownThenStart() {
    final firstDir = Random().nextBool() ? Direction.down : Direction.up;
    _flipTurns = firstDir == Direction.up ? 0.5 : 0.0;

    setState(() {
      _countdownDone = true;

      // Désactive et masque les bonus au départ
      _bonusEnabled = false;
      _dirChanges = 0;
      _topChronoScale = _bottomChronoScale =
          _topReverseScale = _bottomReverseScale = 0;

      // Typing: on prépare l'état
      _isTyping = true;
      _displayedText = '';
      _sideIconsVisible = false;
      _iconsPopCtrl.value = 0;
    });

    _scaleCtrl.forward(from: 0);

    // Lance le typing puis, à la fin, icônes en pop + slide
    _startTyping(_question, onDone: () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _sideIconsVisible = true;
      });
      _iconsPopCtrl.forward(from: 0);
      _startSlide(to: firstDir);
    });
  }

  /// Effet machine à écrire (lettre par lettre)
  void _startTyping(String fullText, {required VoidCallback onDone}) async {
    final List<String> chars =
        fullText.runes.map((c) => String.fromCharCode(c)).toList();
    for (final ch in chars) {
      await Future.delayed(const Duration(milliseconds: _typingCharDelayMs));
      if (!mounted) return;
      setState(() {
        _displayedText += ch;
      });
    }
    onDone();
  }

  // ------------------------------------------------------------
  //                 MIX : prochaine question
  // ------------------------------------------------------------
  Future<void> _pickNextMixQuestion() async {
    if (_mixQuestions.isEmpty) return;

    // ---- filtre déjà vues ----
    final seen = await _getSeenIds();
    List<_MixQ> remaining =
        _mixQuestions.where((q) => !seen.contains(q.id)).toList();

    if (remaining.isEmpty) {
      // Toutes les questions ont été vues → on réinitialise.
      await _resetSeenIds();
      remaining = List<_MixQ>.from(_mixQuestions);
    }

    // ---- évite deux questions consécutives de la même catégorie ----
    List<_MixQ> pool = remaining.where((q) => q.catId != _lastMixCat).toList();

    if (pool.isEmpty && remaining.length > 1) {
      // Il ne reste que des questions de la même catégorie que la précédente,
      // mais d'autres catégories existent déjà vues : on autorise un retour
      // exceptionnel sur des questions déjà vues pour casser la répétition.
      pool = _mixQuestions.where((q) => q.catId != _lastMixCat).toList();
    }

    final _MixQ next = (pool..shuffle()).first;
    _lastMixCat = next.catId;

    setState(() {
      _question = next.text;
      _currentQuestionId = next.id;
      _currentBg = catGradients[next.catId]!;
    });

    await _addSeenId(next.id);
  }

  // ------------------------------------------------------------
  //                       SLIDE / LOSER / RESET
  // ------------------------------------------------------------
  void _startSlide({required Direction to}) {
    if (_isPaused) return;

    _slideEndingTimer?.cancel();
    _slideEnding = false;

    _direction = to;
    final endAlignment =
        to == Direction.down ? Alignment.bottomCenter : Alignment.topCenter;
    _slideTween = AlignmentTween(begin: _slideAnim.value, end: endAlignment);
    _slideAnim = _slideTween.animate(_slideCtrl);

    _slideCtrl
      ..reset()
      ..forward();

    _slideEndingTimer = Timer(
      _slideCtrl.duration! - const Duration(milliseconds: 200),
      () => mounted ? setState(() => _slideEnding = true) : null,
    );
  }

  void _onSlideCompleted(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_bonusInterruption) {
      _bonusInterruption = false;
      return;
    }

    // ---- annonce loser ----
    _slideEnding = false;
    setState(() {
      _bonusEnabled = false;
      _topChronoScale = _bottomChronoScale =
          _topReverseScale = _bottomReverseScale = 0;
      _question = '👇🏻 Loser ! 👇🏻';
      _currentQuestionId = ''; // pas de favoris sur le loser
    });

    // ---- retire une vie ----
    setState(() {
      if (_direction == Direction.down) {
        if (_livesBottom > 0) _livesBottom--;
      } else {
        if (_livesTop > 0) _livesTop--;
      }
    });
    // ---- feedback loser (sound + haptic) ----
    if (_soundOnSetting) {
      _audioPlayer.play(AssetSource('sound/haha.mp3'));
    }
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);

    // ---- Lottie life‑out : joue l’anim du coeur concerné ----
    if (_direction == Direction.down) {
      if (_livesBottom < _initialLives) {
        final int idx = _initialLives - 1 - _livesBottom; // 0..initialLives-1
        _lifeCtrlsBottom[idx]
          ..reset()
          ..forward();
      }
    } else {
      if (_livesTop < _initialLives) {
        final int idx = _livesTop; // after decrement
        _lifeCtrlsTop[idx]
          ..reset()
          ..forward();
      }
    }

    // ---- Game Over ? ----
    if (_livesTop == 0 || _livesBottom == 0) {
      _showGameOverPopup();
      return;
    }

    // ---- prochaine question ----
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _visible = false;
        _countdownDone = false;
      });
      Future.delayed(const Duration(milliseconds: 1500), _prepareNextQuestion);
    });
  }

  // ------------------------------------------------------------
  //                    GAME OVER  /  RESTART
  // ------------------------------------------------------------
  Future<void> _showGameOverPopup() async {
    // On retourne la pop‑up de 90° quand c’est le joueur d’en haut qui perd.
    final bool needFlip = _direction != Direction.up; // invert logic

    final result = await showDialog<String>(
      barrierDismissible: false,
      context: context,
      builder: (_) => PopupGameOver(flipped: needFlip),
    );

    if (!mounted) return;

    if (result == 'restart') {
      _restartGame();
    } else if (result == 'switch') {
      Navigator.of(context).pop();
    }
  }

  void _restartGame() {
    _slideEndingTimer?.cancel();
    _slideCtrl.reset();
    _scaleCtrl.reset();
    _shakeCtrl.reset();
    _topPumpCtrl.reset();
    _bottomPumpCtrl.reset();
    for (final c in _lifeCtrlsTop) c.reset();
    for (final c in _lifeCtrlsBottom) c.reset();

    setState(() {
      _livesTop = _initialLives;
      _livesBottom = _initialLives;
      _flipTurns = 0;
      _direction = Direction.down;
      _isPaused = false;
      _visible = true;
      _bonusEnabled = true;
      _countdownDone = false;
      _lastMixCat = null;
      _currentQuestionId = '';
      _currentBg = widget.backgroundGradient ??
          catGradients[widget.categoryId ?? ''] ??
          const RadialGradient(
            colors: [Color(0xFF06ACFF), Color(0xFF02FFFB)],
            center: Alignment.center,
            radius: 1.15,
          );
    });

    _prepareNextQuestion();
  }

  // ------------------------------------------------------------
  //                PRÉPARER PROCHAINE QUESTION
  // ------------------------------------------------------------
  Future<void> _prepareNextQuestion() async {
    if (widget.categoryId == 'mix' ||
        widget.categoryId == 'favorites' ||
        widget.categoryId == 'discover') {
      await _pickNextMixQuestion();
    } else {
      // ------------ catégories simples ------------
      final seen = await _getSeenIds();
      List<_Q> pool = _questions.where((q) => !seen.contains(q.id)).toList();
      if (pool.isEmpty) {
        await _resetSeenIds();
        pool = List<_Q>.from(_questions);
      }
      final _Q next = (pool..shuffle()).first;
      setState(() {
        _question = next.text;
        _currentQuestionId = next.id;
        final String srcCat = next.id.split('_').first; // ex: hardcore / chaos
        if (catGradients.containsKey(srcCat)) {
          _currentBg = catGradients[srcCat]!;
        }
      });
      await _addSeenId(next.id);
    }

    setState(() {
      _visible = true;
      _flipTurns = 0;
      _slideTween = AlignmentTween(begin: Alignment.center, end: Alignment.center);
      _slideAnim = _slideTween.animate(_slideCtrl);
    });

    // Prépare l'état de typing pour le prochain countdown
    _displayedText = '';
    _isTyping = false;
    _sideIconsVisible = false;
    _iconsPopCtrl.value = 0;

    _resetButtons();
  }

  // ------------------------------------------------------------
  //                 CHARGER LES QUESTIONS (MIX)
  // ------------------------------------------------------------
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
            final String id = '${cat}_${entry.key}';
            tmp.add(_MixQ(id, q.trim(), cat));
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
      await _pickNextMixQuestion();
    }
  }

  // ------------------------------------------------------------
  //                 CHARGER LES FAVORIS
  // ------------------------------------------------------------
  Future<void> _loadQuestionsFromFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favIdsRaw =
        prefs.getStringList('favorite_questions') ?? [];

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
          debugPrint('⚠️ Favoris : impossible de charger $cat.json');
          continue;
        }
      }

      final Map<String, dynamic>? jsonMap = jsonCache[cat];
      final Map<String, dynamic>? item = jsonMap?[key];
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
    await _pickNextMixQuestion();
  }

  // ------------------------------------------------------------
  //             CHARGER LES QUESTIONS « DISCOVER »
  // ------------------------------------------------------------
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
        debugPrint('⚠️ Discover : aucune question valide');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
        return;
      }

      tmp.shuffle();
      _mixQuestions
        ..clear()
        ..addAll(tmp);
      await _pickNextMixQuestion();
    } catch (e) {
      debugPrint('⚠️ Impossible de charger discover.json : $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  /// Affiche la popup "Pas de favoris" puis revient à l'écran précédent
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

  // ------------------------------------------------------------
  //   CHARGEMENT QUESTIONS PREFS / ASSET (logique d'origine)
  // ------------------------------------------------------------
  Future<void> _loadQuestionsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_questions') ?? [];
    if (saved.isNotEmpty) {
      _questions
        ..clear()
        ..addAll(saved.map((t) => _Q(t, t)));
      final _Q first = (_questions..shuffle()).first;
      setState(() {
        _question = first.text;
        _currentQuestionId = first.id;
      });
      await _addSeenId(first.id);
    }
  }

  Future<void> _loadQuestionsFromAsset(String categoryId) async {
    // Certaines catégories peuvent agréger plusieurs fichiers JSON.
    // Nouveau comportement : on ne charge que la bdd correspondant à l'ID fourni,
    // sauf si l'ID contient explicitement des virgules.
    List<String> sourceCats;
    if (categoryId.contains(',')) {
      sourceCats = categoryId
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet() // évite doublons
          .toList();
    } else {
      // Cas standard : on ne charge que la catégorie demandée (ex: 'hardcore')
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

          // Permet de tagger chaque question avec sa vraie catégorie source si fournie
          // (ex: dans hardcore.json fusionné, certaines entrées ont {"category":"chaos"})
          final String srcCat = (item['category'] is String && (item['category'] as String).trim().isNotEmpty)
              ? (item['category'] as String).trim()
              : cat; // fallback: le fichier chargé

          // ID basé sur la source réelle pour que le BG suive (hardcore/chaos)
          loaded.add(_Q('${srcCat}_${entry.key}', q.trim()));
        }
      } catch (e) {
        debugPrint('⚠️ Impossible de charger $cat.json : $e');
        // On continue pour les autres sources si l'une est manquante/incorrecte
      }
    }

    // Optionnel: log de contrôle de la répartition par catégorie source
    final Map<String, int> bySrc = {};
    for (final q in loaded) {
      final src = q.id.split('_').first;
      bySrc[src] = (bySrc[src] ?? 0) + 1;
    }
    debugPrint('📦 Chargé ${loaded.length} questions depuis: ' + bySrc.entries.map((e) => '${e.key}=${e.value}').join(', '));

    if (loaded.isNotEmpty) {
      _questions
        ..clear()
        ..addAll(loaded);
      final _Q first = (_questions..shuffle()).first;
      setState(() {
        _question = first.text;
        _currentQuestionId = first.id;
        final String srcCat = first.id.split('_').first; // hardcore / chaos
        if (catGradients.containsKey(srcCat)) {
          _currentBg = catGradients[srcCat]!;
        }
      });
      await _addSeenId(first.id);
    }
  }

  bool _isPlayerOnTurn(bool isTop) =>
      (_direction == Direction.down && !isTop) ||
      (_direction == Direction.up && isTop);

  // ------------------------------------------------------------
  //                              UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;

    final isTablet = screenW >= 768;
    final fontSize = isTablet ? 36.0 : 22.0;
    final buttonSize = isTablet ? 50.0 : 30.0;
    final buttonOuterSize = isTablet ? 95.0 : 60.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(gradient: _currentBg),
      child: Stack(
        children: [
          const Positioned.fill(child: ParticleBackground()),

          if (_countdownDone) _buildQuestionCard(screenH, fontSize),
          if (!_countdownDone) _buildCountdown(),

          if (_countdownDone) ..._buildPlayerButtons(buttonSize, buttonOuterSize),

          _buildLivesTop(),
          _buildLivesBottom(),

          _buildClose(buttonSize, buttonOuterSize),
        ],
      ),
    );
  }

  // ------------------- Sub‑widgets -------------------
  Widget _buildQuestionCard(double screenH, double fontSize) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => _handleTap(d, screenH),
        child: AnimatedBuilder(
          animation: _slideCtrl,
          builder: (_, __) => Align(
            alignment: _slideAnim.value,
            child: AnimatedRotation(
              turns: _flipTurns % 4, // garde la valeur dans [0,4[
              duration: const Duration(milliseconds: 300),
              child: FadeTransition(
                opacity: _scaleAnim,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 500),
                  child: _QuestionCard(
                    key: _cardKey,
                    text: _isTyping ? _displayedText : _question,
                    shakeAnim: _shakeAnim,
                    fontSize: fontSize,
                    isFavorite: _isCurrentFavorite,
                    onFavoriteTap: _toggleFavorite,
                    // ---- taille de l’icône favorite dépendant du device
                    favSize: MediaQuery.of(context).size.width >= 768 ? 38.0 : 28.0,
                    // ---- icône à droite : pause par défaut, play quand _isPaused
                    rightIconAsset: _isPaused
                        ? 'assets/icons/play.png'
                        : 'assets/icons/pause.png',
                    rightIconSize:
                        MediaQuery.of(context).size.width >= 768 ? 38.0 : 28.0,
                    // ---- apparition pop des icônes après typing
                    showSideIcons: _sideIconsVisible,
                    sideIconsPopAnim: _iconsPopAnim,
                  ),
                ),
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
          onLoaded: (c) => Future.delayed(c.duration, _launchCountdownThenStart),
        ),
      );

  // ---------- boutons joueurs ----------
  List<Widget> _buildPlayerButtons(double buttonSize, double outer) => [
        // haut
        Positioned(
          top: 50,
          left: 30,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _topPumpCtrl,
                  builder: (_, child) =>
                      Transform.scale(scale: _topPumpAnim.value, child: child),
                  child: AnimatedScale(
                    scale: _topChronoScale,
                    duration: const Duration(milliseconds: 200),
                    child: _glassButton(
                      onTap: () => _onChronoPressed(true),
                      enabled: _bonusEnabled && _isPlayerOnTurn(true),
                      size: outer,
                      child: SizedBox(
                        width: buttonSize,
                        child: FittedBox(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(pi)..rotateX(pi),
                            child: Image.asset('assets/icons/chrono.png'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                AnimatedScale(
                  scale: _topReverseScale,
                  duration: const Duration(milliseconds: 200),
                  child: _glassButton(
                    onTap: () => _onReversePressed(true),
                    enabled: _bonusEnabled && _isPlayerOnTurn(true),
                    size: outer,
                    child: SizedBox(
                      width: buttonSize,
                      child: FittedBox(
                        child: Image.asset('assets/icons/reverse.png'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // bas
        Positioned(
          bottom: 50,
          right: 30,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _bottomPumpCtrl,
                  builder: (_, child) => Transform.scale(
                      scale: _bottomPumpAnim.value, child: child),
                  child: AnimatedScale(
                    scale: _bottomChronoScale,
                    duration: const Duration(milliseconds: 200),
                    child: _glassButton(
                      onTap: () => _onChronoPressed(false),
                      enabled: _bonusEnabled && _isPlayerOnTurn(false),
                      size: outer,
                      child: SizedBox(
                        width: buttonSize,
                        child: FittedBox(
                          child: Image.asset('assets/icons/chrono.png'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                AnimatedScale(
                  scale: _bottomReverseScale,
                  duration: const Duration(milliseconds: 200),
                  child: _glassButton(
                    onTap: () => _onReversePressed(false),
                    enabled: _bonusEnabled && _isPlayerOnTurn(false),
                    size: outer,
                    child: SizedBox(
                      width: buttonSize,
                      child: FittedBox(
                        child: Image.asset('assets/icons/reverse.png'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];

  // ---------- vies ----------
  Widget _buildLivesTop() {
    final w = MediaQuery.of(context).size.width;
    final bool tablet = w >= 768;

    // On smartphone, use smaller hearts when 5 lives to avoid overlap
    final double heartSize = tablet
        ? 100
        : (_initialLives == 5 ? 60 : 60);
    final double sideOffset = tablet ? 0 : 20;

    return Positioned(
      top: 50,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment:
            tablet ? MainAxisAlignment.center : MainAxisAlignment.center,
        children: List.generate(
          _initialLives,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: AnimatedBuilder(
              animation: _lifeCtrlsTop[i],
              builder: (_, child) => Transform.scale(
                scale: _lifeScale(_lifeCtrlsTop[i].value),
                child: child,
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(pi)..rotateX(pi),
                child: SizedBox(
                  width: heartSize,
                  height: heartSize,
                  child: Lottie.asset(
                    Settings.get().selectedLifeJson,
                    controller: _lifeCtrlsTop[i],
                    repeat: false,
                    onLoaded: (comp) =>
                        _lifeCtrlsTop[i].duration = comp.duration,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLivesBottom() {
    final w = MediaQuery.of(context).size.width;
    final bool tablet = w >= 768;

    final double heartSize = tablet
        ? 100
        : (_initialLives == 5 ? 60 : 60);
    final double sideOffset = tablet ? 0 : 20;

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment:
            tablet ? MainAxisAlignment.center : MainAxisAlignment.center,
        children: List.generate(
          _initialLives,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: AnimatedBuilder(
              animation: _lifeCtrlsBottom[i],
              builder: (_, child) => Transform.scale(
                scale: _lifeScale(_lifeCtrlsBottom[i].value),
                child: child,
              ),
              child: SizedBox(
                width: heartSize,
                height: heartSize,
                child: Lottie.asset(
                  Settings.get().selectedLifeJson,
                  controller: _lifeCtrlsBottom[i],
                  repeat: false,
                  onLoaded: (comp) =>
                      _lifeCtrlsBottom[i].duration = comp.duration,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- close ----------
  Widget _buildClose(double iconSize, double outer) => Positioned(
        top: 30,
        right: 20,
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: outer,
            height: outer,
            child: Center(
              child: Icon(Icons.close, color: Colors.white, size: iconSize),
            ),
          ),
        ),
      );

  // ------------------------------------------------------------
  //                    INTERACTIONS & BONUS
  // ------------------------------------------------------------
  void _handleTap(TapDownDetails d, double screenH) {
    // Pendant le typing : on ignore tous les taps (pas pause, pas flip)
    if (_isTyping) {
      return;
    }

    final insideCard = _isTapInsideCard(d.globalPosition);

    // pause / reprise
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

    // changement de direction
    if (!_isPaused && !_slideEnding) {
      final cardH = _cardKey.currentContext?.size?.height ?? _cardMinHeight;
      final centerY = ((_slideAnim.value.y + 1) / 2) * screenH;
      final top = centerY - cardH / 2;
      final bottom = centerY + cardH / 2;
      const tol = 30.0;

      if (_direction == Direction.down && d.globalPosition.dy > bottom - tol) {
        _flipCard();
        _startSlide(to: Direction.up);
      } else if (_direction == Direction.up && d.globalPosition.dy < top + tol) {
        _flipCard();
        _startSlide(to: Direction.down);
      }
    }
  }

  bool _isTapInsideCard(Offset globalPos) {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect =
        MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    return rect.contains(globalPos);
  }

  void _flipCard() {
    if (_soundOnSetting) {
      _audioPlayer.play(AssetSource('sound/switch.mp3'));
    }

    setState(() {
      _flipTurns = (_flipTurns + 0.5) % 4;
      _dirChanges += 1;

      // Apparition des bonus après X changements de direction
      if (!_bonusEnabled && _dirChanges >= _bonusAppearAfterTurns) {
        _bonusEnabled = true;

        // animation d’apparition : scales 0 → 1 puis pop‑in via _scaleCtrl
        _topChronoScale = _bottomChronoScale =
            _topReverseScale = _bottomReverseScale = 1;

        _scaleCtrl.forward(from: 0);
      }
    });
  }

  Future<void> _onReversePressed(bool isTop) async {
    if (_isPaused || !_bonusEnabled || _slideEnding) return;
    _bonusInterruption = true;

    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();

    if (isTop) {
      setState(() => _topReverseScale = 0.7);
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => _topReverseScale = 1);
      await Future.delayed(const Duration(milliseconds: 100));
    } else {
      setState(() => _bottomReverseScale = 0.7);
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => _bottomReverseScale = 1);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _flipCard();
    _startSlide(
        to: _direction == Direction.down ? Direction.up : Direction.down);
    _bonusInterruption = false;
    setState(() => isTop ? _topReverseScale = 0 : _bottomReverseScale = 0);
  }

  Future<void> _onChronoPressed(bool isTop) async {
    if (_isPaused || !_bonusEnabled || !_isPlayerOnTurn(isTop) || _slideEnding) return;
    _bonusInterruption = true;

    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();

    _isPaused = true;
    _slideCtrl.stop();
    _slideEndingTimer?.cancel();

    if (isTop) {
      setState(() => _topChronoScale = 0.7);
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => _topChronoScale = 1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _topPumpCtrl.forward(from: 0);
    } else {
      setState(() => _bottomChronoScale = 0.7);
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => _bottomChronoScale = 1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _bottomPumpCtrl.forward(from: 0);
    }

    setState(() => isTop ? _topChronoScale = 0 : _bottomChronoScale = 0);

    _isPaused = false;
    _bonusInterruption = false;
    _slideCtrl.forward();
  }

  void _resetButtons() {
    _dirChanges = 0;
    _bonusEnabled = false;          // désactivé + caché
    setState(() {
      // Bonus invisibles jusqu’à la 2ᵉ rotation (scale 0)
      _topChronoScale = _bottomChronoScale =
          _topReverseScale = _bottomReverseScale = 0;
    });
    _scaleCtrl.reset();
    _topPumpCtrl.reset();
    _bottomPumpCtrl.reset();
    _slideEnding = false;
    _bonusInterruption = false;
  }

  /// Récupère le texte localisé (extrait du map JSON `text`)
  String? _localizedText(Map<String, dynamic>? textMap) {
    if (textMap == null) return null;
    return textMap[_langCode] ??
        textMap['en'] ??
        (textMap.isNotEmpty ? textMap.values.first as String? : null);
  }
}

// ------------------------------------------------------------
//                       QuestionCard
// ------------------------------------------------------------
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.text,
    required this.shakeAnim,
    required this.fontSize,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.favSize,
    required this.rightIconAsset,
    required this.rightIconSize,
    required this.showSideIcons,
    required this.sideIconsPopAnim,
  });

  final String text;
  final Animation<double> shakeAnim;
  final double fontSize;

  // [FAVORITES]
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final double favSize;

  // [RIGHT ICON: pause/play]
  final String rightIconAsset;
  final double rightIconSize;

  // [Side icons visibility + pop]
  final bool showSideIcons;
  final Animation<double> sideIconsPopAnim;

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
                  const BoxConstraints(minHeight: _HomeScreenState._cardMinHeight),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: text == '👇🏻 Loser ! 👇🏻'
                        ? Offset(sin(shakeAnim.value * pi * 5) * 4, 0)
                        : Offset.zero,
                    child: child,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showFavoriteButton && text != '👇🏻 Loser ! 👇🏻' && showSideIcons) ...[
                        ScaleTransition(
                          scale: sideIconsPopAnim,
                          child: _FavoriteIcon(
                            isFavorite: isFavorite,
                            onFavoriteTap: onFavoriteTap,
                            size: favSize,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (text != '👇🏻 Loser ! 👇🏻' && showSideIcons) ...[
                        const SizedBox(width: 12),
                        ScaleTransition(
                          scale: sideIconsPopAnim,
                          child: _PausePlayIcon(
                            isPaused: rightIconAsset.contains('play.png'),
                            size: rightIconSize,
                          ),
                        ),
                      ],
                    ],
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

// ------------------------------------------------------------
//                        Glass button
// ------------------------------------------------------------
Widget _glassButton({
  required Widget child,
  required VoidCallback onTap,
  double size = 90,
  bool enabled = true,
}) {
  return GestureDetector(
    onTap: enabled ? onTap : null,
    child: ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
          ),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

/// ------------------------------------------------------------
///               Icône animée de Favoris
/// ------------------------------------------------------------
class _FavoriteIcon extends StatefulWidget {
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final double size;

  const _FavoriteIcon({
    Key? key,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.size,
  }) : super(key: key);

  @override
  State<_FavoriteIcon> createState() => _FavoriteIconState();
}

class _FavoriteIconState extends State<_FavoriteIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _playPop() async {
    await _ctrl.forward(from: 0.0);
    await _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.isFavorite
        ? "assets/icons/favorite.png"
        : "assets/icons/unfavorite.png";

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        widget.onFavoriteTap();
        await _playPop();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Image.asset(
          asset,
          width: widget.size,
          height: widget.size,
        ),
      ),
    );
  }
}
/// ------------------------------------------------------------
///               Icône animée Pause/Play (droite)
/// ------------------------------------------------------------
class _PausePlayIcon extends StatefulWidget {
  final bool isPaused;
  final double size;

  const _PausePlayIcon({
    Key? key,
    required this.isPaused,
    required this.size,
  }) : super(key: key);

  @override
  State<_PausePlayIcon> createState() => _PausePlayIconState();
}

class _PausePlayIconState extends State<_PausePlayIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _PausePlayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      _ctrl.forward(from: 0.0).then((_) => _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.isPaused
        ? "assets/icons/play.png"
        : "assets/icons/pause.png";
    return ScaleTransition(
      scale: _scaleAnim,
      child: Image.asset(
        asset,
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}