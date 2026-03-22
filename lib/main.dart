import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: ClarionChainApp()));
}

class ClarionChainApp extends StatelessWidget {
  const ClarionChainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClarionChain',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}
