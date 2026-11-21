import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'daily_content_widgets.dart';
import 'state/game_store.dart';
import 'state/growth_store.dart';
import 'state/task_reminders.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({
    super.key,
    required this.store,
    required this.gameStore,
  });

  final GrowthStore store;
  final GameStore gameStore;

  Widget? _settingsIcon(BuildContext context, IconData icon) =>
      MediaQuery.textScalerOf(context).scale(14) >= 24 ? null : Icon(icon);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('앱 설정')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([store, gameStore]),
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('화면과 게임', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          secondary: _settingsIcon(
                            context,
                            Icons.dark_mode_outlined,
                          ),
                          title: const Text('어두운 테마'),
                          subtitle: const Text('밤에 편해요'),
                          value: store.darkTheme,
                          onChanged: store.setDarkTheme,
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          secondary: _settingsIcon(
                            context,
                            Icons.card_giftcard_outlined,
                          ),
                          title: const Text('게임 보상 안내'),
                          subtitle: const Text('할 일 완료 후 보상 표시'),
                          value: store.showGameRewards,
                          onChanged: store.setShowGameRewards,
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          secondary: _settingsIcon(
                            context,
                            Icons.motion_photos_off_outlined,
                          ),
                          title: const Text('전투 효과 줄이기'),
                          subtitle: const Text('움직임 끄기'),
                          value: gameStore.reduceBattleEffects,
                          onChanged: (value) async {
                            try {
                              await gameStore.setReduceBattleEffects(value);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('전투 효과 설정을 저장하지 못했어요.'),
                                ),
                              );
                            }
                          },
                        ),
                        if (!kIsWeb &&
                            defaultTargetPlatform ==
                                TargetPlatform.android) ...[
                          const Divider(height: 1),
                          SwitchListTile.adaptive(
                            secondary: _settingsIcon(
                              context,
                              Icons.vibration_outlined,
                            ),
                            title: const Text('전투 진동'),
                            subtitle: const Text(
                              '기본 꺼짐 · 기기 동작 줄이기 시 진동 없음',
                            ),
                            value: gameStore.battleHaptics,
                            onChanged: (value) async {
                              try {
                                await gameStore.setBattleHaptics(value);
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('전투 진동 설정을 저장하지 못했어요.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('알림', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      child: TaskQuietHoursPanel(store: store),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final allowed = await taskReminderService
                            .requestPermission();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              allowed
                                  ? '알림을 사용할 수 있어요.'
                                  : '알림을 허용하지 않았어요. 휴대폰의 앱 알림 설정도 확인해 주세요.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('알림 권한 확인'),
                    ),
                  ] else
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('시간 알림은 Android 앱에서 사용할 수 있어요.'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '할 일의 알림 시각은 각 할 일에서 정할 수 있어요.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
