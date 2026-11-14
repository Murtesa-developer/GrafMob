import 'package:flutter/material.dart';

import 'core/alarm_state.dart';
import 'core/alert_watcher.dart';
import 'core/background_watch.dart';
import 'screens/alarm_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_controller.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundWatch.configure();
  runApp(const GrafModApp());
}

class GrafModApp extends StatefulWidget {
  const GrafModApp({super.key});

  @override
  State<GrafModApp> createState() => _GrafModAppState();
}

class _GrafModAppState extends State<GrafModApp> {
  final _auth = AuthController();
  final _watcher = AlertWatcher();

  @override
  void initState() {
    super.initState();
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    _watcher.dispose();
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
      // The alarm page sits above everything, whatever screen is open, and
      // updates live as critical alerts come and go.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          if (child != null) child,
          ListenableBuilder(
            listenable: Listenable.merge([_watcher.alarm, _watcher.pageOpen]),
            builder: (context, _) {
              final snap = _watcher.alarm.value;
              if (!_watcher.pageOpen.value || snap.items.isEmpty) {
                return const SizedBox.shrink();
              }
              return AlarmScreen(
                snapshot: snap,
                onAcknowledge: _watcher.acknowledgeAlarm,
                onSnooze: _watcher.snoozeAlarm,
                onDismiss: _watcher.dismissAlarm,
                onOpenApp: _watcher.openAppFromAlarm,
              );
            },
          ),
        ],
      ),
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
              return HomeScreen(auth: _auth, watcher: _watcher);
          }
        },
      ),
    );
  }
}
