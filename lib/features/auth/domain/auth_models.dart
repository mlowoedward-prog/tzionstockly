import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  final String id;
  final String email;
  final String businessId;
  final String role; // owner, manager, staff

  const UserProfile({
    required this.id,
    required this.email,
    required this.businessId,
    this.role = 'owner',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'business_id': businessId,
        'role': role,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        businessId: json['business_id'] as String,
        role: json['role'] as String? ?? 'owner',
      );
}

@immutable
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserProfile? userProfile;
  final String? errorMessage;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.userProfile,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? userProfile,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      userProfile: userProfile ?? this.userProfile,
      errorMessage: errorMessage,
    );
  }
}
