import 'package:flutter/material.dart';

class GameGuidePage extends StatelessWidget {
  const GameGuidePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('게임 즐기는 법')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '신수와 첫 숲길을 걸어 보세요',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('아래 화면을 따라 첫 동료를 고르고, 훈련과 숲길 전투를 진행해 보세요.'),
              const SizedBox(height: 14),
              Card(
                margin: const EdgeInsets.only(bottom: 18),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: const Text('보상·기록 규칙'),
                  subtitle: const Text('훈련권, 전투 경험, 서버 보상'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: const [
                    Text(
                      '할 일 1개나 반복 루틴 1회를 마치면 훈련 2회(하루 합계 5건까지), 목표 실천 MINI·MORE·MAX는 각각 1·2·3회를 얻어요.',
                    ),
                    SizedBox(height: 10),
                    Text('훈련에서 새 신수나 조각은 나오지 않습니다. 훈련 귀환 횟수로 지도의 장소를 엽니다.'),
                    SizedBox(height: 10),
                    Text(
                      '완료를 취소하면 목표 XP는 다시 계산됩니다. 이미 받은 훈련권은 유지되며 같은 완료를 다시 눌러도 중복 지급되지 않습니다.',
                    ),
                    SizedBox(height: 10),
                    Text(
                      '훈련권은 최근 14일 동안 완료한 행동까지 받을 수 있습니다. 더 오래된 완료 기록과 XP는 그대로 남습니다.',
                    ),
                    SizedBox(height: 10),
                    Text(
                      '전투 승리 시 편성 신수가 장소별 경험 1·2·3을 얻습니다. 같은 장소의 경험은 한국 날짜로 하루 최대 5번까지 지급되지만, 이후 승리도 별점과 최고 턴 기록은 갱신됩니다.',
                    ),
                    SizedBox(height: 10),
                    Text(
                      '지도의 전투 칭호는 이 기기의 기록입니다. 지도 전투의 서버 조각과 배지는 아직 지급되지 않습니다.',
                    ),
                  ],
                ),
              ),
              _step(
                context,
                '1',
                '첫 동료 고르기',
                '솔여우·파도수달·별까마귀 중 한 마리를 고릅니다. 첫 전투 승리 전에는 훈련 중이 아닐 때 시작 동료를 바꿀 수 있어요.',
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final name in ['pine-fox', 'wave-otter', 'star-crow'])
                      Image.asset(
                        'assets/game/$name.png',
                        width: 70,
                        height: 70,
                        filterQuality: FilterQuality.none,
                      ),
                  ],
                ),
              ),
              _step(
                context,
                '2',
                '스쿼드에 편성하기',
                '5칸 중 원하는 칸을 누르고 보유 신수를 고르세요. 첫 전투 승리 후에는 시작 신수와 다른 종 한 마리가 확정으로 합류해요.',
                _screenPreview('assets/game/guide-squad.png'),
              ),
              _step(
                context,
                '3',
                '30초 훈련 보내기',
                '훈련권 1회를 쓰고 출발해 30초 뒤 귀환을 확인하세요. 앱을 닫아도 훈련 상태는 남습니다. 1·3·7회 귀환 조건을 채운 뒤 숲길 지도에서 장소를 하나씩 탐험하세요.',
                _screenPreview('assets/game/guide-forest.png'),
              ),
              _step(
                context,
                '4',
                '이끼 문턱 첫 전투',
                '훈련을 한 번 마치면 지도에서 이끼 문턱의 장소 정보를 열고 전투 준비로 들어가세요. 전열·후열을 확인하고 훈련권 1회를 써서 두 웨이브와 이끼 수호자에게 도전합니다. 첫 승리에는 새 동료가 한 번만 합류해요. 일시정지·2배속·결과까지 보기를 사용할 수 있어요. 효과 줄이기는 화면 움직임을 멈추고 다음 전투에도 유지됩니다. 진동은 기본 꺼짐이며 직접 켤 수 있어요. 별점과 최고 턴은 다시 들어와도 남고, 패배해도 할 일 완료 기록은 바뀌지 않아요.',
                _screenPreview('assets/game/guide-battle.png'),
              ),
              _step(
                context,
                '5',
                '두 신수로 다음 전투',
                '첫 전투에서 합류한 신수는 자동 편성되지 않아요. 스쿼드의 빈칸을 눌러 함께 편성하세요. 훈련을 3번 귀환하고 첫 장소 전투에서 승리하면 반딧불이 오솔길에 도전할 수 있어요. 승리하면 편성 신수에게 전투 경험이 쌓이고 3마다 레벨이 올라요. 패배해도 별점과 장소 클리어는 늘지 않습니다.',
                _screenPreview(
                  'assets/game/guide-second-battle.png',
                  alignment: const Alignment(0, -0.5),
                ),
              ),
              _step(
                context,
                '6',
                '새벽 전망대 보스전',
                '훈련 7회 귀환과 앞의 두 장소 승리 후 새벽 전망대가 열려요. 두 신수를 성장시켜 도전하세요. 보스에게 지면 앞의 장소에서 전투 경험을 더 쌓거나 첫 두 칸의 순서를 바꿔 보세요. 승리하면 안개 강가의 강가 입구가 열리고, 여울과 달빛 나루로 이어집니다.',
                _screenPreview('assets/game/dawn-lookout-bg.png'),
              ),
              _step(
                context,
                '7',
                '발견과 뽑기',
                '도감은 발견한 종을 기록합니다. 훈련에는 발견 확률이 없어요. 정식 파견은 계정의 서버 동료를 등록한 뒤 시작하며, 귀환 조각 3개로 무료 뽑기를 할 수 있습니다. 서버 기능은 시험 중입니다.',
                _screenPreview('assets/game/guide-dex.png'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _step(
    BuildContext context,
    String number,
    String title,
    String description,
    Widget illustration,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number  $title',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          illustration,
          const SizedBox(height: 10),
          Text(description),
        ],
      ),
    ),
  );

  Widget _screenPreview(
    String asset, {
    Alignment alignment = Alignment.center,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.asset(
      asset,
      width: double.infinity,
      height: 190,
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
    ),
  );
}
