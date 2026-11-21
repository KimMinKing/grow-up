import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'state/auth_gateway.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.auth,
    required this.onComplete,
    this.onGuest,
  });

  final AuthGateway auth;
  final VoidCallback onComplete;
  final VoidCallback? onGuest;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  StreamSubscription<String?>? authSubscription;
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  Set<SocialProvider> availableProviders = {};
  bool checkingProviders = true;
  bool providerCheckFailed = false;
  bool signingUp = false;
  bool usingCode = false;
  bool codeForSignup = false;
  bool awaitingCode = false;
  bool busy = false;
  bool showPassword = false;
  bool completed = false;
  String? error;

  @override
  void initState() {
    super.initState();
    authSubscription = widget.auth.authChanges.listen((_) {
      if (widget.auth.currentUserId != null) _complete();
    });
    _checkProviders();
  }

  void _complete() {
    if (!mounted || completed) return;
    completed = true;
    widget.onComplete();
  }

  Future<void> _checkProviders() async {
    if (mounted) {
      setState(() {
        checkingProviders = true;
        providerCheckFailed = false;
      });
    }
    try {
      final providers = await widget.auth.availableSocialProviders();
      if (mounted) setState(() => availableProviders = providers);
    } catch (_) {
      if (mounted) setState(() => providerCheckFailed = true);
    } finally {
      if (mounted) setState(() => checkingProviders = false);
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  String _errorMessage(Object exception) {
    if (exception is AuthException) {
      switch (exception.code) {
        case 'invalid_credentials':
          return '이메일 또는 비밀번호를 확인해 주세요.';
        case 'email_not_confirmed':
          return '이메일 인증을 완료한 뒤 로그인해 주세요.';
        case 'user_already_exists':
          return '이미 가입한 이메일입니다. 로그인해 주세요.';
        case 'weak_password':
          return '더 안전한 비밀번호를 입력해 주세요.';
        case 'over_email_send_rate_limit':
          return '메일 요청이 너무 많습니다. 잠시 뒤 다시 시도해 주세요.';
      }
      return exception.message;
    }
    return '처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.';
  }

  Future<void> _submit() async {
    final address = email.text.trim();
    if (!address.contains('@') ||
        address.startsWith('@') ||
        address.endsWith('@')) {
      setState(() => error = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    if (password.text.isEmpty) {
      setState(() => error = '비밀번호를 입력해 주세요.');
      return;
    }
    if (signingUp && password.text.length < 6) {
      setState(() => error = '비밀번호는 6자 이상 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (signingUp) {
        final signedIn = await widget.auth.signUpWithPassword(
          address,
          password.text,
        );
        if (!mounted) return;
        if (signedIn) {
          _complete();
        } else {
          setState(() {
            awaitingCode = true;
            codeForSignup = true;
          });
        }
      } else {
        await widget.auth.signInWithPassword(address, password.text);
        _complete();
      }
    } catch (e) {
      if (mounted) setState(() => error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendCode() async {
    final address = email.text.trim();
    if (!address.contains('@') ||
        address.startsWith('@') ||
        address.endsWith('@')) {
      setState(() => error = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.sendEmailCode(address);
      if (mounted) {
        setState(() {
          awaitingCode = true;
          codeForSignup = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (code.text.trim().isEmpty) {
      setState(() => error = '메일로 받은 인증번호를 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (codeForSignup) {
        await widget.auth.confirmSignUp(email.text.trim(), code.text);
      } else {
        await widget.auth.verifyEmailCode(email.text.trim(), code.text);
      }
      _complete();
    } catch (e) {
      if (mounted) setState(() => error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _social(SocialProvider provider) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.signInWithSocial(provider);
      // OAuth completes when the browser redirects back to the app.
      if (mounted) setState(() => busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.auto_awesome, size: 42, color: colors.primary),
                  const SizedBox(height: 12),
                  Text(
                    '전설키우기',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '오늘의 실천으로 나만의 전설을 키워요.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!awaitingCode) ...[
                    OutlinedButton.icon(
                      onPressed:
                          busy ||
                              !availableProviders.contains(
                                SocialProvider.google,
                              )
                          ? null
                          : () => _social(SocialProvider.google),
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Google로 계속하기'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed:
                          busy ||
                              !availableProviders.contains(SocialProvider.kakao)
                          ? null
                          : () => _social(SocialProvider.kakao),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('카카오로 계속하기'),
                    ),
                    if (!checkingProviders &&
                        (availableProviders.length < 2 ||
                            providerCheckFailed)) ...[
                      const SizedBox(height: 8),
                      Text(
                        providerCheckFailed
                            ? '간편 로그인 상태를 확인하지 못했어요.'
                            : '비활성화된 간편 로그인은 제공자 설정 후 사용할 수 있어요.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (providerCheckFailed)
                        TextButton(
                          onPressed: _checkProviders,
                          child: const Text('다시 확인'),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '이메일',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!usingCode)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('로그인')),
                          ButtonSegment(value: true, label: Text('회원가입')),
                        ],
                        selected: {signingUp},
                        onSelectionChanged: busy
                            ? null
                            : (value) => setState(() {
                                signingUp = value.first;
                                error = null;
                              }),
                      ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: email,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: '이메일'),
                    ),
                    const SizedBox(height: 12),
                    if (!usingCode) ...[
                      TextField(
                        controller: password,
                        enabled: !busy,
                        obscureText: !showPassword,
                        onSubmitted: (_) => _submit(),
                        autofillHints: [
                          signingUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: '비밀번호',
                          suffixIcon: IconButton(
                            tooltip: showPassword ? '비밀번호 숨기기' : '비밀번호 보기',
                            onPressed: () =>
                                setState(() => showPassword = !showPassword),
                            icon: Icon(
                              showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : (usingCode ? _sendCode : _submit),
                      child: Text(
                        usingCode
                            ? '인증번호 받기'
                            : signingUp
                            ? '이메일로 회원가입'
                            : '이메일로 로그인',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              usingCode = !usingCode;
                              signingUp = false;
                              error = null;
                            }),
                      child: Text(
                        usingCode ? '비밀번호로 로그인' : '비밀번호 없이 인증번호로 로그인',
                      ),
                    ),
                  ] else ...[
                    Text(
                      codeForSignup ? '이메일 인증' : '인증번호 로그인',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('${email.text.trim()}로 보낸 인증번호를 입력해 주세요.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: code,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: const InputDecoration(labelText: '인증번호'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy ? null : _confirm,
                      child: const Text('인증하고 시작하기'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              awaitingCode = false;
                              signingUp = false;
                              usingCode = false;
                              error = null;
                            }),
                      child: const Text('이미 인증했어요 · 로그인'),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: TextStyle(color: colors.error)),
                  ],
                  if (widget.onGuest != null) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: busy ? null : widget.onGuest,
                      child: const Text('로그인 없이 이 기기에서 시작하기'),
                    ),
                    Text(
                      '로그인하지 않으면 기록은 이 기기에만 저장됩니다.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
