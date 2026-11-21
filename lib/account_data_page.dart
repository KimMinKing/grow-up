import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountDataPage extends StatelessWidget {
  const AccountDataPage({
    super.key,
    required this.goalSyncAvailable,
    this.dailySyncAvailable = false,
    required this.serverGameAvailable,
    required this.accountDeletionEnabled,
  });

  final bool goalSyncAvailable;
  final bool dailySyncAvailable;
  final bool serverGameAvailable;
  final bool accountDeletionEnabled;

  static const _privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const _accountDeletionUrl = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
  );

  bool _validPublicUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  Future<void> _openPublicPage(BuildContext context, String value) async {
    try {
      if (await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // The user can retry from this screen.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('페이지를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('내 데이터')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 정보가 저장되는 곳',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('현재 시험판에서 사용하는 저장 위치와 삭제 범위예요.'),
                const SizedBox(height: 18),
                _InfoCard(
                  icon: Icons.phone_android_outlined,
                  title: '이 기기에 저장',
                  body:
                      '목표·실천 기록, 할 일, 메모, 로드맵, 신수 이름과 로컬 게임 진행이 저장됩니다. '
                      '로그아웃해도 남아 있어요.',
                ),
                const SizedBox(height: 10),
                _InfoCard(
                  icon: Icons.cloud_outlined,
                  title: '계정과 서버에 저장',
                  body:
                      '이메일 주소와 로그인 정보는 Supabase 인증 서비스에서 처리합니다. '
                      '${serverGameAvailable ? '정식 파견·뽑기를 사용하면 계정의 게임 진행도 서버에 저장됩니다. ' : ''}'
                      '${goalSyncAvailable ? '목표·실천 기록은 직접 동기화를 누를 때 서버로 전송됩니다.' : '목표·실천 기록의 동기화는 현재 꺼져 있습니다.'} '
                      '${dailySyncAvailable ? '할 일·메모도 직접 동기화를 누를 때 서버로 전송됩니다.' : '할 일·메모는 현재 기기에만 저장됩니다.'}',
                ),
                const SizedBox(height: 10),
                const _InfoCard(
                  icon: Icons.save_alt_outlined,
                  title: '백업 파일',
                  body:
                      '기록을 내보내면 선택한 위치에 JSON 파일을 저장합니다. '
                      '기기 기록이나 계정을 삭제해도 이 파일은 자동으로 지워지지 않아요.',
                ),
                const SizedBox(height: 10),
                _InfoCard(
                  icon: Icons.delete_outline,
                  title: '삭제 방법',
                  body:
                      '${accountDeletionEnabled ? '회원탈퇴를 누르면 Supabase 계정과 연결된 앱 데이터베이스 기록을 삭제합니다.' : '서버 계정 삭제 기능은 준비 중입니다. 현재 이 화면에서 회원탈퇴를 진행할 수 없습니다.'} '
                      '기기에 저장된 기록은 별도로 「기기 기록 삭제」를 눌러 지울 수 있습니다. '
                      '이미 발송된 메일과 내보낸 백업 파일은 앱에서 삭제할 수 없습니다. '
                      '서비스 제공자의 백업과 로그에는 별도 보관 기간이 적용될 수 있습니다.',
                ),
                if (_validPublicUrl(_privacyPolicyUrl)) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _openPublicPage(context, _privacyPolicyUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('개인정보처리방침 열기'),
                  ),
                ],
                if (accountDeletionEnabled &&
                    _validPublicUrl(_accountDeletionUrl)) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _openPublicPage(context, _accountDeletionUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('웹에서 계정 삭제 요청'),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body),
        ],
      ),
    ),
  );
}
