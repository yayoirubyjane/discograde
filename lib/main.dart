import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/album_detail_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/forums_screen.dart';
import 'screens/thread_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/review_detail_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/ai_discovery_screen.dart';
import 'screens/login_screen.dart';
import 'screens/two_step_sign_up_screen.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';

final _authRouterRefresh = ChangeNotifier();
StreamSubscription<User?>? _authStateSubscription;
const _dirtyWhiteSystemOverlay = SystemUiOverlayStyle(
  statusBarColor: Color(0xFFF5F5F5),
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
);

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
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: _dirtyWhiteSystemOverlay,
          child: child ?? const SizedBox.shrink(),
        ),
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
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF5F5F5),
    foregroundColor: Color(0xFF3F3F3F),
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: _dirtyWhiteSystemOverlay,
  ),
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
    GoRoute(
      path: '/review/:reviewId',
      builder: (_, state) => ReviewDetailScreen(
        reviewId: state.pathParameters['reviewId']!,
        openComposer: state.uri.queryParameters['compose'] == 'true',
      ),
    ),
    GoRoute(
      path: '/user/:userId',
      pageBuilder: (_, state) {
        final userId = state.pathParameters['userId']!;
        return MaterialPage<void>(
          key: ValueKey(
            'user-profile-$userId-${state.uri.queryParameters['visit'] ?? 'direct'}',
          ),
          child: ProfileScreen(userId: userId),
        );
      },
      routes: [
        GoRoute(
          path: 'followers',
          pageBuilder: (_, state) {
            final userId = state.pathParameters['userId']!;
            return MaterialPage<void>(
              key: ValueKey(
                'user-profile-$userId-followers-${state.uri.queryParameters['visit'] ?? 'direct'}',
              ),
              child: UserConnectionsScreen(
                userId: userId,
                relationship: 'followers',
              ),
            );
          },
        ),
        GoRoute(
          path: 'following',
          pageBuilder: (_, state) {
            final userId = state.pathParameters['userId']!;
            return MaterialPage<void>(
              key: ValueKey(
                'user-profile-$userId-following-${state.uri.queryParameters['visit'] ?? 'direct'}',
              ),
              child: UserConnectionsScreen(
                userId: userId,
                relationship: 'following',
              ),
            );
          },
        ),
      ],
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
            GoRoute(
              path: '/notifications',
              builder: (_, _) => const NotificationsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: ':userId',
                  redirect: (_, state) => _legacyProfileRedirect(state),
                  routes: [
                    GoRoute(
                      path: 'followers',
                      redirect: (_, state) => _legacyProfileRedirect(state),
                    ),
                    GoRoute(
                      path: 'following',
                      redirect: (_, state) => _legacyProfileRedirect(state),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

String _legacyProfileRedirect(GoRouterState state) {
  final userPath = state.uri.path.substring('/profile/'.length);
  final query = state.uri.hasQuery ? '?${state.uri.query}' : '';
  return '/user/$userPath$query';
}

class _TabShell extends StatelessWidget {
  const _TabShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    (label: 'Home', icon: CupertinoIcons.house_alt),
    (label: 'Charts', icon: CupertinoIcons.chart_bar),
    (label: 'Forums', icon: CupertinoIcons.chat_bubble_2),
    (label: 'Notifications', icon: CupertinoIcons.bell),
    (label: 'Profile', icon: CupertinoIcons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomOffset = media.padding.bottom + 12 < 24
        ? 24.0
        : media.padding.bottom + 12;
    final navigationWidth = (media.size.width - 72)
        .clamp(0.0, 336.0)
        .toDouble();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          navigationShell,
          if (media.viewInsets.bottom == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomOffset,
              height: 60,
              child: Center(
                child: Container(
                  width: navigationWidth,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x1A000000)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (var index = 0; index < _items.length; index++)
                          Expanded(
                            child: _TabNavigationItem(
                              item: _items[index],
                              selected: index == navigationShell.currentIndex,
                              onTap: () => navigationShell.goBranch(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabNavigationItem extends StatefulWidget {
  const _TabNavigationItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({String label, IconData icon}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabNavigationItem> createState() => _TabNavigationItemState();
}

class _TabNavigationItemState extends State<_TabNavigationItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovered || _focused;
    final color = widget.selected
        ? const Color(0xFF3F3F3F)
        : Color(0xFF3F3F3F).withValues(alpha: highlighted ? 0.7 : 0.4);

    return Semantics(
      label: widget.item.label,
      button: true,
      selected: widget.selected,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: const Color(0x1F3F3F3F),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.item.label == 'Notifications')
                _UnreadNotificationIcon(color: color)
              else
                Icon(widget.item.icon, size: 24, color: color),
              if (widget.selected)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E8A8A),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              if (highlighted)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0x803F3F3F)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox.expand(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadNotificationIcon extends StatelessWidget {
  const _UnreadNotificationIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Icon(CupertinoIcons.bell, size: 24, color: color);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        final hasUnread = snapshot.data?.docs.any(
              (notification) => notification.data()['read'] != true,
            ) ??
            false;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(CupertinoIcons.bell, size: 24, color: color),
            if (hasUnread)
              Positioned(
                top: -2,
                right: -3,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E8A8A),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
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
