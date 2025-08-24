import 'package:flutter/material.dart';
import 'category.dart';
import 'paywall.dart';
import 'utils/settings.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:io'; // Platform check for RevenueCat keys
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' show debugPrint;

final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
bool isPremiumUser = false;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- RevenueCat initialisation (multi‑platform) ------------------------
  const String iosRevenuecatKey     = 'appl_LPjVEUouBOisbfyswabhmaIDlzZ';   // iOS / App Store
  const String androidRevenuecatKey = 'xxxx';   // Android / Play Store

  final String revenuecatApiKey =
      Platform.isIOS ? iosRevenuecatKey : androidRevenuecatKey;

  await Purchases.configure(PurchasesConfiguration(revenuecatApiKey));
  debugPrint('[RC] Purchases configured with key: $revenuecatApiKey');

  // Vérifie si l’utilisateur dispose déjà de l’entitlement “Premium”
  try {
    final customerInfo = await Purchases.getCustomerInfo();
    isPremiumUser = customerInfo.entitlements.active['Premium'] != null;
    isPremiumNotifier.value = isPremiumUser; // propagate to listeners
    debugPrint('[RC] Initial premium status: $isPremiumUser');
  } catch (e) {
    debugPrint('[RC] Error fetching initial customer info: $e');
    // On garde la valeur par défaut en cas d’erreur réseau
  }

  await Settings.get().loadFromPrefs(); // restore Sound, Solo, sliders…
  runApp(const FaceToFaceApp());
}

class FaceToFaceApp extends StatefulWidget {
  const FaceToFaceApp({super.key});

  @override
  State<FaceToFaceApp> createState() => _FaceToFaceAppState();
}

class _FaceToFaceAppState extends State<FaceToFaceApp> {
  late bool _premium;

  @override
  void initState() {
    super.initState();
    _premium = isPremiumUser;

    // Listen for any future changes to the customer’s entitlements
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      final bool hasPremium = customerInfo.entitlements.active['Premium'] != null;
      debugPrint('[RC] CustomerInfo update received. Premium: $hasPremium');
      if (hasPremium != _premium) {
        setState(() {
          _premium = hasPremium;
          isPremiumUser = hasPremium; // keep the global in sync
          isPremiumNotifier.value = hasPremium; // notify global listeners
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCHIN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
      ),
      // --- Localisation -----------------------------------------------
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return const Locale('en');
        for (final s in supported) {
          if (s.languageCode == locale.languageCode) return s;
        }
        return const Locale('en');
      },
      // ---------------------------------------------------------------
      home: _premium
          ? const CategorySelectionScreen()
          : const PaywallPage(),
    );
  }
}