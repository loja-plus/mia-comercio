import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'client_config.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/notifications.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Modo offline: todos os dados ficam guardados no aparelho, sem limite de tamanho,
  // e as alterações feitas sem internet são enviadas quando a rede voltar.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await initializeDateFormatting('pt_PT');
  await initializeDateFormatting('en_GB');
  await Notifier.I.init();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const MiaApp()));
}

class MiaApp extends StatelessWidget {
  const MiaApp({super.key});

  static const green = Color(0xFF0E7A57);
  static const ink = Color(0xFF123A30);
  static const gold = Color(0xFFB7790A);

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: green, brightness: b, secondary: gold);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF3F5F2) : const Color(0xFF0F1614),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: ClientConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: Locale(app.lang),
      supportedLocales: const [Locale('pt'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: app.user == null ? const LoginScreen() : const HomeShell(),
    );
  }
}
