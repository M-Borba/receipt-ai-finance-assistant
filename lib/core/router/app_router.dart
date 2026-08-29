import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/receipts/presentation/screens/receipt_detail_screen.dart';
import '../../features/receipts/presentation/screens/receipt_list_screen.dart';
import '../../features/receipts/presentation/screens/scan_receipt_screen.dart';
import '../../features/insights/presentation/screens/insights_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/groups/presentation/screens/group_detail_screen.dart';
import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final onSplash = location == '/splash';
      final onAuth = location.startsWith('/auth');

      // Mientras Firebase resuelve la sesión, `authState.value` es null. Tratar
      // eso como "no logueado" mandaba al login por un instante y se comía el
      // deep link con el que se abrió la app.
      if (authState.isLoading) {
        if (onSplash) return null;
        return '/splash?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      final isLoggedIn = authState.value != null;

      if (!isLoggedIn) return onAuth ? null : '/auth/login';

      if (onAuth || onSplash) {
        final from = state.uri.queryParameters['from'];
        if (from != null &&
            from.startsWith('/') &&
            !from.startsWith('/auth') &&
            !from.startsWith('/splash')) {
          return from;
        }
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/receipts',
            name: 'receipts',
            builder: (context, state) => const ReceiptListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'receiptDetail',
                builder: (context, state) => ReceiptDetailScreen(
                  receiptId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/scan',
            name: 'scan',
            builder: (context, state) => const ScanReceiptScreen(),
          ),
          GoRoute(
            path: '/expenses',
            name: 'expenses',
            builder: (context, state) => const ExpensesScreen(),
          ),
          GoRoute(
            path: '/groups',
            name: 'groups',
            builder: (context, state) => const GroupsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'groupDetail',
                builder: (context, state) => GroupDetailScreen(
                  groupId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/insights',
            name: 'insights',
            builder: (context, state) => const InsightsScreen(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _routes = [
    '/dashboard',
    '/receipts',
    '/scan',
    '/expenses',
    '/groups',
  ];

  /// El índice se deriva de la ruta actual. Guardarlo en un `State` lo dejaba
  /// desincronizado cada vez que se navegaba con `context.go` desde otra
  /// pantalla, con un deep link o con el botón atrás.
  static int _indexFor(String location) {
    final match = _routes.lastIndexWhere((r) => location.startsWith(r));
    return match == -1 ? 0 : match;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexFor(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == selectedIndex) return;
          context.go(_routes[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_outlined),
            selectedIcon: Icon(Icons.receipt),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Escanear',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Gastos',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Grupos',
          ),
        ],
      ),
    );
  }
}
