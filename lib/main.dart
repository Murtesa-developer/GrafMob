import 'package:flutter/material.dart';

import 'core/push_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_controller.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GrafModApp());
}

class GrafModApp extends StatefulWidget {
  const GrafModApp({super.key});

  @override
  State<GrafModApp> createState() => _GrafModAppState();
}

class _GrafModAppState extends State<GrafModApp> {
  final _auth = AuthController();
  final _push = PushService();

  @override
  void initState() {
    super.initState();
    _push.init();
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    _push.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GrafMod',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
          switch (_auth.status) {
            case AuthStatus.unknown:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            case AuthStatus.loggedOut:
              return LoginScreen(auth: _auth);
            case AuthStatus.loggedIn:
              return HomeScreen(auth: _auth, push: _push);
          }
        },
      ),
    );
  }
}
