import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/database/database_service.dart';
import '../../../core/network/supabase_config.dart';
import 'auth_models.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  final DatabaseService dbService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _userKey = 'tzion_cached_user_profile';

  AuthNotifier({required this.dbService}) : super(const AuthState()) {
    _initAuth();
  }

  Future<void> _initAuth() async {
    state = state.copyWith(isLoading: true);
    try {
      if (SupabaseConfig.isConfigured && SupabaseConfig.client != null) {
        final session = SupabaseConfig.client!.auth.currentSession;
        if (session != null) {
          final profile = await _fetchUserProfile(session.user.id);
          if (profile != null) {
            state = AuthState(
              isAuthenticated: true,
              isLoading: false,
              userProfile: profile,
            );
            await _cacheProfile(profile);
            return;
          }
        }
      }

      // Check cached local profile if offline or Supabase unconfigured
      final cachedJson = await _storage.read(key: _userKey);
      if (cachedJson != null) {
        final Map<String, dynamic> data = jsonDecode(cachedJson);
        final profile = UserProfile.fromJson(data);
        state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          userProfile: profile,
        );
        return;
      }
    } catch (_) {
      // Fall through to unauthenticated
    }
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }

  Future<UserProfile?> _fetchUserProfile(String userId) async {
    if (!SupabaseConfig.isConfigured || SupabaseConfig.client == null) return null;
    try {
      final response = await SupabaseConfig.client!
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        return UserProfile.fromJson(response);
      }
    } catch (e) {
      // Fallback
    }
    return null;
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String businessName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    if (!SupabaseConfig.isConfigured || SupabaseConfig.client == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Supabase is not configured. (Run with --dart-define)',
      );
      return false;
    }

    try {
      final client = SupabaseConfig.client!;

      // 1. Supabase auth signup
      final authRes = await client.auth.signUp(
        email: email,
        password: password,
      );

      final user = authRes.user;
      if (user == null) {
        throw Exception('Sign up failed: No user returned');
      }

      // 2. Create business in Supabase
      final bizRes = await client
          .from('businesses')
          .insert({'name': businessName, 'currency': 'TZS'})
          .select()
          .single();

      final businessId = bizRes['id'] as String;

      // 3. Create user profile
      final profile = UserProfile(
        id: user.id,
        email: email,
        businessId: businessId,
        role: 'owner',
      );

      await client.from('user_profiles').insert(profile.toJson());

      // 4. Adopt local offline data to new businessId
      await dbService.adoptDefaultBusinessData(businessId);

      // 5. Save & update state
      await _cacheProfile(profile);
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        userProfile: profile,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    if (!SupabaseConfig.isConfigured || SupabaseConfig.client == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Supabase is not configured. (Run with --dart-define)',
      );
      return false;
    }

    try {
      final client = SupabaseConfig.client!;
      final authRes = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = authRes.user;
      if (user == null) {
        throw Exception('Sign in failed');
      }

      final profile = await _fetchUserProfile(user.id);
      if (profile == null) {
        throw Exception('User profile not found in database');
      }

      await dbService.adoptDefaultBusinessData(profile.businessId);
      await _cacheProfile(profile);

      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        userProfile: profile,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      if (SupabaseConfig.isConfigured && SupabaseConfig.client != null) {
        await SupabaseConfig.client!.auth.signOut();
      }
    } catch (_) {}
    await _storage.delete(key: _userKey);
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }

  Future<void> _cacheProfile(UserProfile profile) async {
    await _storage.write(key: _userKey, value: jsonEncode(profile.toJson()));
  }
}
