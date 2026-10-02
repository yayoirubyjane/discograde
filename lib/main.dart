import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/album_detail_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/forums_screen.dart';
import 'screens/thread_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/ai_discovery_screen.dart';
import 'screens/login_screen.dart';
import 'screens/two_step_sign_up_screen.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';

final _authRouterRefresh = ChangeNotifier();
StreamSubscription<User?>? _authStateSubscription;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiscoGradeApp());
}

class DiscoGradeApp extends StatefulWidget {
  const DiscoGradeApp({super.key});

  @override
  State<DiscoGradeApp> createState() => _DiscoGradeAppState();
}

class _DiscoGradeAppState extends State<DiscoGradeApp> {
  late Future<void> _startup;
  late final GoRouter _router = _createRouter();

  @override
  void initState() {
    super.initState();
    _startup = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAppCheck.instance.activate(
      providerWeb: kDebugMode
          ? WebDebugProvider()
          : ReCaptchaV3Provider(
              const String.fromEnvironment('RECAPTCHA_V3_SITE_KEY'),
            ),
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _authStateSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
      _,
    ) {
      _authRouterRefresh.notifyListeners();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _startup,
    builder: (context, snapshot) {
      final theme = _appTheme();
      if (snapshot.connectionState != ConnectionState.done) {
        return MaterialApp(
          title: 'Discograde',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: const _StartupLoadingScreen(),
        );
      }
      if (snapshot.hasError) {
        return MaterialApp(
          title: 'Discograde',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: _StartupErrorScreen(error: snapshot.error!),
        );
      }
      return MaterialApp.router(
        title: 'Discograde',
        debugShowCheckedModeBanner: false,
        theme: theme,
        routerConfig: _router,
      );
    },
  );
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFFF5F5F5),
    body: Center(child: CircularProgressIndicator(color: Color(0xFF0E8A8A))),
  );
}

ThemeData _appTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFF5F5F5),
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF0E8A8A),
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF3F3F3F),
  ),
  textTheme: GoogleFonts.interTextTheme().apply(
    bodyColor: const Color(0xFF3F3F3F),
    displayColor: const Color(0xFF3F3F3F),
  ),
  cardTheme: const CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: Color(0xFF0E8A8A),
    unselectedItemColor: Color(0xFF8A8A8A),
    elevation: 0,
    type: BottomNavigationBarType.fixed,
  ),
);

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: DiscogradeSplashLogo(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Text(
              'Could not connect to Firebase.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

GoRouter _createRouter() => GoRouter(
  initialLocation: '/login',
  refreshListenable: _authRouterRefresh,
  redirect: (context, state) async {
    final user = FirebaseAuth.instance.currentUser;
    final signedIn = user != null;
    final isAuthRoute =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';
    if (!signedIn && !isAuthRoute) return '/login';
    if (signedIn && isAuthRoute && AuthService.googleSignInInProgress) {
      return null;
    }
    if (user != null) {
      final needsProfile = await AuthService.needsProfileSetup(user.uid);
      if (needsProfile && state.matchedLocation != '/complete-profile') {
        return '/complete-profile';
      }
      if (!needsProfile && state.matchedLocation == '/complete-profile') {
        return '/home';
      }
    }
    if (signedIn && isAuthRoute) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, _) => const TwoStepSignUpScreen()),
    GoRoute(
      path: '/complete-profile',
      builder: (_, _) => const TwoStepSignUpScreen(profileOnly: true),
    ),
    GoRoute(
      path: '/search',
      builder: (_, state) =>
          SearchScreen(initialQuery: state.uri.queryParameters['q'] ?? ''),
    ),
    GoRoute(
      path: '/ai-discovery',
      builder: (_, _) => const AiDiscoveryScreen(),
    ),
    GoRoute(
      path: '/album/:albumId',
      builder: (_, state) =>
          AlbumDetailScreen(albumId: state.pathParameters['albumId']!),
    ),
    GoRoute(
      path: '/thread/:threadId',
      builder: (_, state) =>
          ThreadDetailScreen(threadId: state.pathParameters['threadId']!),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _TabShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/charts', builder: (_, _) => const ChartsScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/forums', builder: (_, _) => const ForumsScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ],
        ),
      ],
    ),
  ],
);

class _TabShell extends StatelessWidget {
  const _TabShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    (
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_outlined,
    ),
    (
      label: 'Charts',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_outlined,
    ),
    (
      label: 'Forums',
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum_outlined,
    ),
    (
      label: 'Profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (next) => navigationShell.goBranch(next),
        items: [
          for (final item in _items)
            BottomNavigationBarItem(
              icon: Icon(item.icon, size: 23),
              activeIcon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.activeIcon, size: 23),
                  const SizedBox(height: 3),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0E8A8A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: const Color(0xFFF5F5F5),
      surfaceTintColor: Colors.transparent,
    ),
    body: Center(
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
