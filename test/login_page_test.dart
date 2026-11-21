import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growup/login_page.dart';
import 'package:growup/main.dart';
import 'package:growup/state/auth_gateway.dart';

class _Auth implements AuthGateway {
  final changes = StreamController<String?>.broadcast();
  String? id;
  String? email;
  String? submittedEmail;
  String? submittedPassword;
  String? confirmedCode;
  String? otpAddress;
  bool signupConfirmed = false;

  @override
  String? get currentUserId => id;
  @override
  String? get currentUserEmail => email;
  @override
  String? get currentDisplayName => null;
  @override
  DateTime? get currentUserCreatedAt => null;
  @override
  Stream<String?> get authChanges => changes.stream;
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<Set<SocialProvider>> availableSocialProviders() async => {};
  @override
  Future<void> signInWithSocial(SocialProvider provider) async {}
  @override
  Future<void> signInWithPassword(String address, String secret) async {
    submittedEmail = address;
    submittedPassword = secret;
    email = address;
    id = 'user-1';
    changes.add(id);
  }

  @override
  Future<bool> signUpWithPassword(String address, String secret) async {
    submittedEmail = address;
    submittedPassword = secret;
    return false;
  }

  @override
  Future<void> confirmSignUp(String address, String token) async {
    confirmedCode = token;
    email = address;
    id = 'user-1';
    changes.add(id);
  }

  @override
  Future<void> sendEmailCode(String address) async {
    otpAddress = address;
  }

  @override
  Future<void> verifyEmailCode(String address, String token) async {
    confirmedCode = token;
    email = address;
    id = 'user-1';
    changes.add(id);
  }

  @override
  Future<void> updateDisplayName(String name) async {}
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('login choices fit a narrow large-text screen', (tester) async {
    tester.view.physicalSize = const Size(300, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: MaterialApp(
          home: LoginPage(auth: auth, onComplete: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await auth.changes.close();
  });

  testWidgets('first launch asks for login and guest can enter', (
    tester,
  ) async {
    final auth = _Auth();
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          showAuthOnLaunch: true,
          auth: auth,
          child: const Scaffold(body: Text('앱 홈')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('이메일로 로그인'), findsOneWidget);
    expect(find.text('앱 홈'), findsNothing);
    await tester.ensureVisible(find.text('로그인 없이 이 기기에서 시작하기'));
    await tester.tap(find.text('로그인 없이 이 기기에서 시작하기'));
    await tester.pump();
    expect(find.text('앱 홈'), findsOneWidget);
    await auth.changes.close();
  });

  testWidgets('email password login enters the app', (tester) async {
    final auth = _Auth();
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(auth: auth, onComplete: () => completed++),
      ),
    );
    await tester.pump();
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Google로 계속하기'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, 'reader@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.text('이메일로 로그인'));
    await tester.pump();
    expect(auth.submittedEmail, 'reader@example.com');
    expect(auth.submittedPassword, 'secret123');
    expect(completed, 1);
    await auth.changes.close();
  });

  testWidgets('signup waits for email code', (tester) async {
    final auth = _Auth();
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(auth: auth, onComplete: () => completed++),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('회원가입'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.text('이메일로 회원가입'));
    await tester.pump();
    expect(find.text('이메일 인증'), findsOneWidget);
    expect(completed, 0);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('인증하고 시작하기'));
    await tester.pump();
    expect(auth.confirmedCode, '123456');
    expect(completed, 1);
    await auth.changes.close();
  });

  testWidgets('existing account can use an email code', (tester) async {
    final auth = _Auth();
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(auth: auth, onComplete: () => completed++),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('비밀번호 없이 인증번호로 로그인'));
    await tester.tap(find.text('비밀번호 없이 인증번호로 로그인'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'existing@example.com');
    await tester.tap(find.text('인증번호 받기'));
    await tester.pump();
    expect(auth.otpAddress, 'existing@example.com');
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('인증하고 시작하기'));
    await tester.pump();
    expect(auth.confirmedCode, '654321');
    expect(completed, 1);
    await auth.changes.close();
  });
}
