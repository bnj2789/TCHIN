import 'package:flutter/material.dart';
import 'paywall.dart';
import 'utils/particule_bg_home.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PrePaywallPage extends StatefulWidget {
  const PrePaywallPage({Key? key}) : super(key: key);

  @override
  State<PrePaywallPage> createState() => _PrePaywallPageState();
}

class _PrePaywallPageState extends State<PrePaywallPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Couleurs par slide
  final List<Color> _accentColors = const [
    Color.fromARGB(255, 36, 131, 255), // Slide 0
    Color.fromARGB(255, 0, 255, 26), // Slide 1
    Color.fromARGB(255, 255, 20, 181), // Slide 2
    Color(0xFFE38F11), // Slide 3
  ];

  /// 4 vraies slides + 1 slide factice (paywall)
  int get _pageCount => 5;

  void _onNextPressed() {
    if (_currentIndex < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _openPaywall();
    }
  }

  void _openPaywall() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PaywallPage()),
    );
  }

  late final List<_PageData> _pages = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = AppLocalizations.of(context)!;
    _pages.clear();
    _pages.addAll([
      _PageData(
        illustration: 'assets/illustrations/prepaywall1.png',
        title: t.prepay1Title,
        subtitle: t.prepay1Sub,
        accent: _accentColors[0],
        illustrationHeight: 250,
      ),
      _PageData(
        illustration: 'assets/illustrations/prepaywall2.png',
        title: t.prepay2Title,
        subtitle: t.prepay2Sub,
        accent: _accentColors[1],
        illustrationHeight: 250,
      ),
      _PageData(
        illustration: 'assets/illustrations/prepaywall3.png',
        title: t.prepay3Title,
        subtitle: t.prepay3Sub,
        accent: _accentColors[2],
        illustrationHeight: 250,
      ),
      _PageData(
        illustration: 'assets/illustrations/rate.json',
        title: t.prepay4Title,
        subtitle: t.prepay4Sub,
        accent: _accentColors[3],
        illustrationHeight: 250,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final Color currentAccent =
        _currentIndex < _accentColors.length ? _accentColors[_currentIndex] : _accentColors.last;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Stack(
          children: [
            // A) fond noir
            Positioned.fill(child: Container(color: Colors.black)),

            // B) lueur
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        currentAccent.withOpacity(0.4),
                        Colors.transparent,
                      ],
                      radius: 0.8,
                      center: const Alignment(0, -0.25),
                    ),
                  ),
                ),
              ),
            ),

            // C) particules
            Positioned.fill(
              child: IgnorePointer(
                child: ParticleBackgroundHome(),
              ),
            ),

            // D) PageView
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, i) {
                  if (i < _pages.length) {
                    return _Slide(
                      data: _pages[i],
                      onNext: _onNextPressed,
                    );
                  } else {
                    // Slide factice → ouverture paywall
                    WidgetsBinding.instance.addPostFrameCallback((_) => _openPaywall());
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),

            // E) bullets
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount - 1, (i) {
                  final bool active = i == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 14 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? _accentColors[i] : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Data model
// ---------------------------------------------------------------------------
class _PageData {
  final String illustration;
  final String title;
  final String subtitle;
  final double? illustrationHeight;
  final Color accent;

  const _PageData({
    required this.illustration,
    required this.title,
    required this.subtitle,
    this.illustrationHeight,
    required this.accent,
  });
}

// ---------------------------------------------------------------------------
//  Slide widget
// ---------------------------------------------------------------------------
class _Slide extends StatelessWidget {
  final _PageData data;
  final VoidCallback onNext;

  const _Slide({
    required this.data,
    required this.onNext,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final contentMaxWidth = isTablet ? 500.0 : double.infinity;

    return Container(
      color: Colors.transparent,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // illustration
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    height: data.illustrationHeight ?? 180,
                    child: Opacity(
                      opacity: 0.8,
                      child: data.illustration.endsWith('.json')
                          ? Lottie.asset(
                              data.illustration,
                              repeat: true,
                              fit: BoxFit.contain,
                            )
                          : Image.asset(
                              data.illustration,
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
                const Spacer(),
                // title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // séparateur
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  child: Divider(
                    color: data.accent,
                    thickness: 1,
                    indent: 60,
                    endIndent: 60,
                  ),
                ),
                // subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    data.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      color: Color.fromARGB(214, 255, 255, 255),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
                // CTA
                SizedBox(
                  width: 260,
                  height: 70,
                  child: ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      side: const BorderSide(color: Colors.white, width: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      t.prepayContinue,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}