// /lib/paywall.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'category.dart';
import 'utils/popup_info.dart';
import 'main.dart';            // <-- pour isPremiumUser
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Increase RevenueCat verbosity while debugging
void _enableRcLogs() {
  try {
    Purchases.setLogLevel(LogLevel.debug);
  } catch (_) {}
}

/// ---------------------------------------------------------------------------
///  PAYWALL “6.9 Secs” – version RevenueCat
/// ---------------------------------------------------------------------------
class PaywallPage extends StatefulWidget {
  final double topSpacing;
  final bool   fullWidth;
  final double rewardIconSize;
  final double rewardTextSize;
  final double rewardVerticalSpacing;
  final double bottomContentSpacing;
  final double planHeight;
  final int    iconDelayBetween;

  const PaywallPage({
    Key? key,
    this.topSpacing            = 50.0,
    this.fullWidth             = false,
    this.rewardIconSize        = 26.0,
    this.rewardTextSize        = 20.0,
    this.rewardVerticalSpacing = 5.0,
    this.bottomContentSpacing  = 10.0,
    this.planHeight            = 60.0,
    this.iconDelayBetween      = 400,
  }) : super(key: key);

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  //  RevenueCat – Packages & Prices (chargés dynamiquement)
  // ---------------------------------------------------------------------------
  String? _weeklyPrice;
  String? _monthlyPrice;
  String? _lifetimePrice;

  Package? _weeklyPkg;
  Package? _monthlyPkg;
  Package? _lifetimePkg;

  // ---------------------------------------------------------------------------
  //  Avantages affichés (localisés)
  // ---------------------------------------------------------------------------
  late List<String> _rewards;
  bool _rewardsBuilt = false;

  // ---------------------------------------------------------------------------
  //  Animations
  // ---------------------------------------------------------------------------
  List<AnimationController> _iconCtrls = [];
  List<Animation<double>>   _iconScales = [];
  late final AnimationController       _heartbeatCtrl;
  late final Animation<double>         _heartbeatAnim;

  // ---------------------------------------------------------------------------
  //  UI State
  // ---------------------------------------------------------------------------
  bool   _isLoading    = false;
  String _selectedPlan = "weekly"; // 'weekly' | 'monthly' | 'lifetime'

  // Indique si ce paywall est affiché dans une bottom‑sheet
  bool? _presentedAsSheet;
  bool _showLimitedLink = false;

  @override
  void initState() {
    super.initState();
    // Forcer portrait sur téléphone
    final shortest = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size.shortestSide;
    if (shortest < 600) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    // Animation pulsante sur CTA
    _heartbeatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _heartbeatAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _heartbeatCtrl, curve: Curves.easeInOut),
    );

    // Chargement des produits RevenueCat
    _enableRcLogs();
    _fetchProductPrices();

    // Affiche le lien "version limitée" après 1.5 s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showLimitedLink = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Mémorise UNE seule fois si l’écran est dans une bottom‑sheet
    _presentedAsSheet ??= (ModalRoute.of(context) is ModalBottomSheetRoute);

    if (!_rewardsBuilt) {
      final t = AppLocalizations.of(context)!;
      _rewards = [
        t.payRewardAdFree,
        t.payRewardContent,
        t.payRewardCards,
        t.premiumSub,
      ];
      _rewardsBuilt = true;
    }
    if (_iconCtrls.length != _rewards.length) {
      _iconCtrls  = List.generate(_rewards.length, (_) =>
          AnimationController(vsync: this, duration: const Duration(milliseconds: 300)));
      _iconScales = _iconCtrls
          .map((c) => CurvedAnimation(parent: c, curve: Curves.elasticOut))
          .toList();
      // démarre l'anim des icônes après la frame courante
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateCheckIcons());
    }
  }

  @override
  void dispose() {
    _heartbeatCtrl.dispose();
    for (var c in _iconCtrls) c.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Helpers – fermeture élégante après achat
  // ---------------------------------------------------------------------------
  void _dismissAfterPurchase() {
    if (_presentedAsSheet == true) {
      // 1) Popup "Premium unlocked"
      Navigator.of(context).pop();              // <- ferme le dialogue
      // 2) Bottom‑sheet (animation slide‑down)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();          // <- ferme la sheet
        }
      });
    } else {
      // Paywall plein‑écran (opened after pre‑paywall)
      _close();
    }
  }

  // ---------------------------------------------------------------------------
  //  RevenueCat – Récupération des offres
  // ---------------------------------------------------------------------------
  Future<void> _fetchProductPrices() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current   = offerings.current;
      if (current != null) {
        debugPrint('🔍 RevenueCat packages returned (${current.availablePackages.length}):');
        for (final p in current.availablePackages) {
          debugPrint(
              ' • rcId=${p.identifier} | storeId=${p.storeProduct.identifier} | price=${p.storeProduct.priceString}');
        }
      }
      if (current == null) {
        debugPrint("⚠️  Aucun offering « Premium » trouvé.");
        return;
      }

      for (final pkg in current.availablePackages) {
        final rcId    = pkg.identifier;              // ex: $rc_monthly
        final storeId = pkg.storeProduct.identifier; // ex: premium_month:premium-month

        // --- iOS aliases ---------------------------------------------------
        switch (rcId) {
          case r'$rc_weekly':
            _weeklyPkg   = pkg;
            _weeklyPrice = pkg.storeProduct.priceString;
            continue;
          case r'$rc_monthly':
            _monthlyPkg   = pkg;
            _monthlyPrice = pkg.storeProduct.priceString;
            continue;
          case r'$rc_lifetime':
            _lifetimePkg   = pkg;
            _lifetimePrice = pkg.storeProduct.priceString;
            continue;
        }

        // --- Android Play Store IDs ---------------------------------------
        switch (storeId) {
          case 'premium_week:premium-week':
          case '6.9_premium_week':
            _weeklyPkg   = pkg;
            _weeklyPrice = pkg.storeProduct.priceString;
            break;
          case 'premium_month:premium-month':
          case '6.9_premium_month':
            _monthlyPkg   = pkg;
            _monthlyPrice = pkg.storeProduct.priceString;
            break;
          case 'lifetime':
          case 'lifetime_6_9_secs':
            _lifetimePkg   = pkg;
            _lifetimePrice = pkg.storeProduct.priceString;
            break;
        }
      }
      debugPrint('✅ Mapping completed → weekly=$_weeklyPrice | monthly=$_monthlyPrice | lifetime=$_lifetimePrice');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("💥 _fetchProductPrices error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  //  RevenueCat – Achat
  // ---------------------------------------------------------------------------
  Future<void> _purchaseSelectedPlan() async {
    final t = AppLocalizations.of(context)!;          // localisation
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      Package? pkg;
      if (_selectedPlan == 'weekly')   pkg = _weeklyPkg;
      if (_selectedPlan == 'monthly')  pkg = _monthlyPkg;
      if (_selectedPlan == 'lifetime') pkg = _lifetimePkg;

      if (pkg == null) {
        PopupInfo.show(context,
          iconPath: 'assets/illustrations/yes.png',
          title: t.payErrProduct);
        return;
      }

      debugPrint('🛒 Attempting purchase → rcId=${pkg.identifier} | storeId=${pkg.storeProduct.identifier}');
      await Purchases.purchasePackage(pkg);
      await Purchases.syncPurchases();

      final info        = await Purchases.getCustomerInfo();
      final entitlement = info.entitlements.all["Premium"];
      final active      = entitlement?.isActive ?? false;

      if (active) {
        isPremiumUser = true;

        // Success popup
        PopupInfo.show(
          context,
          iconPath: 'assets/icons/party.png',
          title: t.paySuccess,
        );

        // Laisse le temps d’afficher le popup avant de fermer le paywall
        await Future.delayed(const Duration(seconds: 2));

        _dismissAfterPurchase();
      } else {
        PopupInfo.show(context,
          iconPath: 'assets/icons/error.png',
          title: t.payErrEntitlement);
      }
    } catch (e) {
      // Show a "cancelled" popup if the user closes the purchase sheet
      if (e is PlatformException &&
          PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
        PopupInfo.show(context,
          iconPath: 'assets/icons/sad.png',
          title: t.payErrCancelled);
        return;
      }
      debugPrint("💥 purchase error: $e");
      PopupInfo.show(context,
        iconPath: 'assets/icons/error.png',
        title: t.payErrFailed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  RevenueCat – Restore
  // ---------------------------------------------------------------------------
  Future<void> _restorePurchases() async {
    final t = AppLocalizations.of(context)!;          // localisation
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await Purchases.restorePurchases();
      await Purchases.syncPurchases();
      final info        = await Purchases.getCustomerInfo();
      final entitlement = info.entitlements.all["Premium"];
      if (entitlement?.isActive ?? false) {
        isPremiumUser = true;
        PopupInfo.show(context,
          iconPath: 'assets/icons/party.png',
          title: t.payRestoreSuccess);
        await Future.delayed(const Duration(seconds: 2));
        _close();
      } else {
        PopupInfo.show(context,
          iconPath: 'assets/icons/error.png',
          title: t.payRestoreNone);
      }
    } catch (e) {
      debugPrint("💥 restore error: $e");
      PopupInfo.show(context,
        iconPath: 'assets/icons/error.png',
        title: t.payRestoreFailed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  Anim icons
  // ---------------------------------------------------------------------------
  Future<void> _animateCheckIcons() async {
    for (final ctrl in _iconCtrls) {
      await Future.delayed(Duration(milliseconds: widget.iconDelayBetween));
      if (mounted) ctrl.forward();
    }
  }

  // ---------------------------------------------------------------------------
  //  Helpers UI ( _close() inchangé )
  // ---------------------------------------------------------------------------
  void _close() {
    final currentRoute = ModalRoute.of(context);
    if (currentRoute is ModalBottomSheetRoute) {
      Navigator.of(context).pop(); // close sheet → animates downwards
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CategorySelectionScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.inAppWebView)) {
      debugPrint("Could not launch $url");
    }
  }

  // ---------------------------------------------------------------------------
  //  BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isTablet       = MediaQuery.of(context).size.width >= 600;
    final t = AppLocalizations.of(context)!; // localisation
    final rewardSpacing  = widget.rewardVerticalSpacing;
    final bottomSpacing  = widget.bottomContentSpacing;
    final boxFit         = widget.fullWidth ? BoxFit.fitWidth : BoxFit.cover;
    final scrW           = MediaQuery.of(context).size.width;
    final double maxContentW = isTablet ? 600.0 : scrW;
    final planW          = math.min(scrW * .85, maxContentW);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentW),
                  child: Column(
                    children: [
                      SizedBox(height: widget.topSpacing),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/illustrations/premium.png',
                          fit: BoxFit.contain,
                          width: scrW * 0.85,
                        ),
                      ),
                      const SizedBox(height: 0), // spacing between image and text
                      Text(
                        t.payPremium,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 0),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Column(
                          children: [
                            for (int i = 0; i < _rewards.length; i++) ...[
                              _rewardRow(_rewards[i], i),
                              if (i < _rewards.length - 1)
                                SizedBox(height: rewardSpacing),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: bottomSpacing),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 50 : 0),
                        child: _planSelector(planW, widget.planHeight),
                      ),
                      const SizedBox(height: 20),
                      _subscribeButton(),
                      const SizedBox(height: 25),
                      SizedBox(
                        height: 24, // réserve l’espace pour éviter tout décalage
                        child: IgnorePointer(
                          ignoring: !_showLimitedLink,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _showLimitedLink ? 1 : 0,
                            child: GestureDetector(
                              onTap: _isLoading ? null : _close,
                              child: Text(
                                t.payContinueLimited,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  decoration: TextDecoration.none,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 35),

                      // --- Bottom links ---------------------------------------
                      Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _isLoading ? null : _restorePurchases,
                              child: Text(
                                t.payRestore,
                                style: TextStyle(
                                  color: _isLoading ? Colors.grey : Colors.white,
                                  decoration: TextDecoration.none,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () => _openUrl(
                                      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                                  child: Text(
                                    t.payTerms,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                GestureDetector(
                                  onTap: () =>
                                      _openUrl('https://rawitconsulting.com/privacy-policy/'),
                                  child: Text(
                                    t.payPrivacy,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // --- Close button -------------------------------------------
            Positioned(
              top: 45,
              left: 30,
              child: GestureDetector(
                onTap: _close,
                child: const Icon(Icons.close,
                    color: Color.fromARGB(177, 255, 255, 255), size: 40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Reward row
  // ---------------------------------------------------------------------------
  Widget _rewardRow(String txt, int i) => Row(
        children: [
          ScaleTransition(
            scale: _iconScales[i],
            child: Image.asset('assets/illustrations/checkblue.png',
                width: widget.rewardIconSize, height: widget.rewardIconSize),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(txt,
                style: TextStyle(
                    color: Colors.white, fontSize: widget.rewardTextSize)),
          ),
        ],
      );

  // ---------------------------------------------------------------------------
  //  Plan selector
  // ---------------------------------------------------------------------------
  Widget _planSelector(double w, double h) {
    final t = AppLocalizations.of(context)!;   // localisation
    return Column(
      children: [
        _planRow("weekly",  t.payPlanWeekly,  _weeklyPrice, w, h),
        const SizedBox(height: 10),
        _planRow("lifetime", t.payPlanLifetime, _lifetimePrice, w, h),
      ],
    );
  }

  Widget _planRow(String key, String title, String? price, double w, double h) {
    final isSel   = (_selectedPlan == key);
    final borderC = isSel ? const Color(0xFF009DFF) : const Color(0xFF454545);

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = key),
      child: SizedBox(
        width: w,
        child: Container(
          height: h,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: borderC, width: 2),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 20)),
              price == null
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      price,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Subscribe button
  // ---------------------------------------------------------------------------
  Widget _subscribeButton() {
    final t = AppLocalizations.of(context)!; // localisation
    final isMonthly  = _selectedPlan == 'monthly';
    final isLifetime = _selectedPlan == 'lifetime';

    String secondLine;

    if (isMonthly) {
      secondLine = t.payCTA; // "Try FREE & Subscribe"
    } else if (isLifetime) {
      secondLine = t.payUnlockLifetime;
    } else { // weekly
      secondLine = t.paySubscribeNow;
    }

    final content = _isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          )
        : Text(
            secondLine,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ScaleTransition(
        scale: _heartbeatAnim,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF44F5FB), Color(0xFF025BFE)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(50),
          ),
          child: TextButton(
            onPressed: _isLoading ? null : _purchaseSelectedPlan,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 55),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}