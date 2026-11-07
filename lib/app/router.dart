import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/providers.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/domain/role_permissions.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/products/presentation/products_screen.dart';
import '../features/products/presentation/product_detail_screen.dart';
import '../features/products/presentation/add_edit_product_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import '../features/partners/presentation/partners_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/user_management_screen.dart';
import '../features/settings/presentation/diagnostics_screen.dart';
import 'app_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Reactive Router Notifier that listens to Riverpod Auth changes
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authNotifierProvider);
    final isLoggingIn = state.matchedLocation == '/login';

    // 1. Unauthenticated Route Guarding
    if (!authState.isAuthenticated) {
      return isLoggingIn ? null : '/login';
    }

    // 2. Prevent authenticated users from remaining on the login page
    if (isLoggingIn) {
      return authState.userRole == UserRole.staff ? '/stock' : '/';
    }

    final loc = state.matchedLocation;

    // 3. Staff Route Restrictions:
    // Staff cannot view financial reports, team management, or diagnostics
    if (authState.userRole == UserRole.staff) {
      if (loc == '/reports' ||
          loc.startsWith('/reports') ||
          loc == '/team' ||
          loc.startsWith('/team') ||
          loc == '/diagnostics') {
        return '/stock';
      }
    }

    // 4. Manager Route Restrictions:
    // Managers can view reports and products, but cannot manage users/team
    if (authState.userRole == UserRole.manager) {
      if (loc == '/team' || loc.startsWith('/team')) {
        return '/';
      }
    }

    return null; // Route allowed
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

List<RouteBase> _buildRoutes() {
  return [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/team',
      builder: (context, state) => const UserManagementScreen(),
    ),
    GoRoute(
      path: '/diagnostics',
      builder: (context, state) => const DiagnosticsScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/products',
              builder: (context, state) => const ProductsScreen(),
              routes: [
                GoRoute(
                  path: 'detail/:id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return ProductDetailScreen(productId: id);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock',
              builder: (context, state) => const StockScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reports',
              builder: (context, state) => const ReportsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'partners',
                  builder: (context, state) => const PartnersScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/add-product',
      builder: (context, state) => const AddEditProductScreen(),
    ),
    GoRoute(
      path: '/product/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ProductDetailScreen(productId: id);
      },
    ),
    GoRoute(
      path: '/partners',
      builder: (context, state) => const PartnersScreen(),
    ),
  ];
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: _buildRoutes(),
  );
});

/// Direct GoRouter instance for backward compatibility
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: _buildRoutes(),
);
