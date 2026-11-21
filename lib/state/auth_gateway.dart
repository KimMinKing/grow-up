import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const androidLoginRedirectScheme = String.fromEnvironment(
  'LOGIN_REDIRECT_SCHEME',
  defaultValue: 'com.example.growup',
);
const androidLoginRedirect = '$androidLoginRedirectScheme://login-callback/';

enum SocialProvider { google, kakao }

abstract class AuthGateway {
  String? get currentUserId;
  String? get currentUserEmail;
  String? get currentDisplayName;
  DateTime? get currentUserCreatedAt;
  Stream<String?> get authChanges;
  Future<String?> accessToken();
  Future<void> sendEmailCode(String email);
  Future<void> verifyEmailCode(String email, String code);
  Future<bool> signUpWithPassword(String email, String password);
  Future<void> confirmSignUp(String email, String code);
  Future<void> signInWithPassword(String email, String password);
  Future<void> signInWithSocial(SocialProvider provider);
  Future<Set<SocialProvider>> availableSocialProviders();
  Future<void> updateDisplayName(String name);
  Future<void> deleteAccount();
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(
    this.client, {
    required this.supabaseUrl,
    required this.publishableKey,
  });

  final SupabaseClient client;
  final String supabaseUrl;
  final String publishableKey;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  String? get currentUserEmail => client.auth.currentUser?.email;

  @override
  String? get currentDisplayName =>
      client.auth.currentUser?.userMetadata?['display_name'] as String?;

  @override
  DateTime? get currentUserCreatedAt =>
      DateTime.tryParse(client.auth.currentUser?.createdAt ?? '');

  @override
  Stream<String?> get authChanges =>
      client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  @override
  Future<bool> signUpWithPassword(String email, String password) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? androidLoginRedirect
          : null,
    );
    if (response.user?.identities?.isEmpty == true) {
      throw const AuthException(
        'User already exists',
        statusCode: '400',
        code: 'user_already_exists',
      );
    }
    return response.session != null;
  }

  @override
  Future<void> confirmSignUp(String email, String code) async {
    final response = await client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim(),
      token: code.trim(),
    );
    if (response.session == null) {
      throw const AuthException('No session returned');
    }
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signInWithSocial(SocialProvider provider) async {
    final launched = await client.auth.signInWithOAuth(
      provider == SocialProvider.google
          ? OAuthProvider.google
          : OAuthProvider.kakao,
      redirectTo: androidLoginRedirect,
    );
    if (!launched) throw const AuthException('Could not open sign-in browser');
  }

  @override
  Future<Set<SocialProvider>> availableSocialProviders() async {
    final response = await http
        .get(
          Uri.parse('$supabaseUrl/auth/v1/settings'),
          headers: {'apikey': publishableKey},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return {};
    final settings = jsonDecode(response.body) as Map<String, dynamic>;
    final external = settings['external'] as Map<String, dynamic>? ?? {};
    return {
      if (external['google'] == true) SocialProvider.google,
      if (external['kakao'] == true) SocialProvider.kakao,
    };
  }

  @override
  Future<String?> accessToken() async =>
      client.auth.currentSession?.accessToken;

  @override
  Future<void> sendEmailCode(String email) async {
    await client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: false,
      emailRedirectTo:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? androidLoginRedirect
          : null,
    );
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    final response = await client.auth.verifyOTP(
      type: OtpType.email,
      email: email.trim(),
      token: code.trim(),
    );
    if (response.session == null) {
      throw const AuthException('No session returned');
    }
  }

  @override
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 24) {
      throw const AuthException('Invalid display name');
    }
    await client.auth.updateUser(
      UserAttributes(data: {'display_name': trimmed}),
    );
  }

  @override
  Future<void> deleteAccount() async {
    final email = currentUserEmail;
    final token = client.auth.currentSession?.accessToken;
    if (email == null || token == null) {
      throw const AuthException('Auth session missing');
    }
    final response = await client.functions.invoke(
      'delete-account',
      headers: {'Authorization': 'Bearer $token'},
      body: {'confirmation': 'DELETE_ACCOUNT', 'email': email},
    );
    if (response.status != 200 ||
        response.data is! Map ||
        response.data['deleted'] != true) {
      throw const AuthException('Account deletion was not confirmed');
    }
    await client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
