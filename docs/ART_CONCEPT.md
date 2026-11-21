# 대표 신수 콘셉트 시안

작성 2026-10-30. 이미지 생성은 내장 `image_gen` 도구를 사용했다. **v2가 현재 검토 시안**이며 원래 세 장은 비교용으로 보관한다. 세 장은 성장 공간의 대표 신수를 시험하기 위한 콘셉트 PNG다. 정식 도트 스프라이트, 애니메이션 프레임, 최종 캐릭터 확정본은 아니다.

| 단계 | 이미지 | 변화 |
|---|---|---|
| 태동 | [guardian-taedong-v2.png](../assets/concept/guardian-taedong-v2.png) | 어린 기본 동물. 뿔·이마 표식·비늘·오라 없음 |
| 각성 | [guardian-gakseong-v2.png](../assets/concept/guardian-gakseong-v2.png) | 작은 뿔 둘, 이마 초승달, 일부 문양이 처음 생김 |
| 초월 | [guardian-chowol-v2.png](../assets/concept/guardian-chowol-v2.png) | 긴 뿔, 넓어진 몸, 등 비늘과 큰 꼬리로 실루엣 변화 |

## 공통 디자인 규칙

- 독자적인 여우·용 혼합 신수. 기존 게임 캐릭터나 특정 작품의 모습을 따라하지 않는다.
- 모든 단계에 네 다리, 꼬리 하나, 호박색 눈과 남색·아이보리 바탕을 유지한다. 뿔과 이마 초승달은 각성부터 나타난다.
- 남색·청록·아이보리·호박색을 주 팔레트로 한다.
- 3/4 정면 전신, 배경 투명, 글자·장비·다른 인물 없음. 이전 고해상도 일러스트보다 훨씬 작은 단순 도트를 지향한다.
- 세 형태가 같은 개체의 직접 진화로 보이도록 얼굴·표식·꼬리 무늬를 유지한다.

## v2 수정 프롬프트 기록

1. **태동:** `Redesign the referenced guardian as a much simpler baby: true low-resolution 64x64 logical pixel sprite, hard square pixels, limited flat palette, large transparent margins. Four short paws, one simple tail, amber eyes, indigo fur, ivory muzzle and teal tuft. No horns, forehead mark, scales, swirls, glow, aura or accessories.`
2. **각성:** `Edit the baby pixel sprite into a clearly older second stage at the same simple sprite scale. Add exactly two short curved horns, a teal crescent forehead mark, a small shoulder scale patch and one tail swirl. Keep four paws, one tail, amber eyes and original palette. No aura or flames yet.`
3. **초월:** `Edit the second stage into a final evolution with a mature broad chest, taller legs, two long backward-curving horns, simple stepped scale mantle and much larger sweeping single tail. Keep face, forehead crescent, amber eyes and palette. Use large hard pixel blocks, limited flat colors and a few isolated sparkle pixels; no painterly details.`

## 시안 검토 항목

- v2는 이전보다 도트가 분명하지만 출력 파일은 여전히 1312×1199 PNG다. **64×64 원본 스프라이트가 생성된 것은 아니다.** 개발 화면에서는 우선 약 160px 표시 크기를 검토하고 128/160/192px에서 판독성을 비교한다. 정식 자산 단계에 64×64 내지 96×96 격자로 다시 제작하고 정수 배율/최근접 확대를 적용한다.
- **다음 정식 아트 수정 기준:** 현재 v2도 태동과 각성의 몸 크기·자세가 비슷하다. 태동은 더 작고 둥근 새끼 동물, 각성은 키와 몸통 비율이 자란 중간 단계, 초월은 확실히 크고 수호자다운 체형으로 만든다. 뿔·문양의 추가뿐 아니라 멀리서 보이는 몸 윤곽을 달리한다. 현재 시안은 앱 화면 배치 테스트에만 사용한다.
- 성장 홈은 신수가 화면을 가리지 않아야 한다. 퀘스트 완료 버튼과 목표 진척이 먼저 읽히는지 확인한다.
- 원래 신수의 이름과 전승 설정은 아직 정하지 않았다.
