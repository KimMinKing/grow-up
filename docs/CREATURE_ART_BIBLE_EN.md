# Creature Art Bible — Generation Brief (English)

**Status:** Pebble Newt has three static evolution portraits and three stage-specific four-frame idle motion sheets in river battles. It joins both device and account collections after the crossing's first victory. Separate attack, hit, and victory artwork remains planned. The other candidate species below are design concepts.

## Product and visual direction

Growup is a gentle task management app with an optional creature adventure. Its creatures should feel like companions for small real life steps: expressive, resilient and curious. The first region is a moonlit pine forest. The art is **original, high quality pixel art** with a readable silhouette at 64–128 screen pixels, a restrained navy/teal base palette and a few bright species accents. Do not imitate Pokémon, Seven Knights, Habitica, or any existing franchise, character, logo or interface. Avoid armor clutter, weapons, human costumes and a predatory gacha aesthetic.

The current three starter references are `assets/game/pine-fox.png`, `assets/game/wave-otter.png`, and `assets/game/star-crow.png`. Upload the matching image as an image reference whenever generating a new stage for those species. Keep their identity, face shape, key markings and colors. The current static files are 1312×1199 transparent PNGs; their 4-frame motion experiments use approximately 543×724 pixels per frame. The new assets are separate artwork and must not be silently substituted for the current files until they pass visual review.

### Candidate collection index

| ID | Display name | Region | Silhouette cue | Principal accents | Visual tier concept |
|---|---|---|---|---|---|
| `pine_fox` | Pine Fox | Pine forest | Leaf ears + pine tail | Moss, cream, amber | Starter |
| `wave_otter` | Wave Otter | Pine forest stream | Curling wave tail | Navy, cyan, cream | Starter |
| `star_crow` | Star Crow | Pine forest sky | Forked tail + star wings | Navy, violet, gold | Starter |
| `moss_tortoise` | Mossback Tortoise | Pine forest | Fern shell dome | Moss, brown, amber | Standard candidate |
| `lantern_moth` | Lantern Moth | Pine forest | Broad lantern wings | Navy, mint, cream | Uncommon candidate |
| `briar_hare` | Briar Hare | Pine forest | Notched ears + vine mane | Russet, green, teal | Standard candidate |
| `reed_heron` | Reed Heron | Tidal marsh | Long legs + reed wings | Blue-gray, teal, copper | Uncommon candidate |
| `pebble_newt` | Pebble Newt | Tidal marsh | Low body + pebble ridge | Slate, turquoise, gold | Standard candidate |
| `rainbell_frog` | Rainbell Frog | Tidal marsh | Round body + throat bell | Emerald, pale blue, amber | Uncommon candidate |
| `cinder_lynx` | Cinder Lynx | Dawn ridge | Ear tufts + ember tail | Charcoal, orange, cream | Rare candidate |
| `cloud_antelope` | Cloud Antelope | Dawn ridge | Cloud-curled horns | Cream, blue-gray, violet | Rare candidate |
| `prism_pangolin` | Prism Pangolin | Dawn ridge | Scale ridge + spiral tail | Indigo, turquoise, cream | Rare candidate |

Visual tiers are proposal labels for silhouette and presentation only. The three implemented starters are all `일반` in the current game data. Do not change stats, draw probabilities or collection limits based on this table.

## Universal production prompt

Combine this paragraph with **one species identity** and **one stage direction** from the sections below. Generate **one creature and one stage per request**, then repeat for the other stages using the approved previous image as a reference. Use the same camera, ground line and pixel scale across the three images of one species.

> Original fantasy companion creature for a gentle Korean task-and-adventure game. Full body, three-quarter view facing screen right, eyes visible, standing on an implied ground plane, transparent background, no scenery, no cast shadow outside the transparent canvas. Deliberate crisp pixel art with consistent square pixels, controlled clusters, clean silhouette, readable at 96 display pixels, expressive face, at most 24 principal colors plus shading, no gradients, no smooth painterly brushwork, no text, no UI, no border, no watermark, no copied franchise design. Keep all limbs, ears, tail, wings and effects inside the canvas. Leave at least 8% transparent margin on every side and align the lowest foot to the same baseline in every stage. Preserve the species' face, signature marking, core palette and anatomy while changing size, posture and silhouette as specified for this evolution stage.

**Output:** transparent PNG at 1024 px or larger on the short side. After approval, pad rather than stretch it to a shared 1312×1199 portrait canvas. Save separate files named `<species_id>-seed.png`, `<species_id>-awakened.png`, `<species_id>-transcendent.png`. The generation model may produce larger images; the final pixel grid and alpha edges must be manually checked before reduction. Do not generate a sheet of three stages in one prompt because that often changes identity and scale between panels.

### Stage language and readability

| App stage | Levels | Required shape change | Restraint |
|---|---:|---|---|
| Seed / 태동 | 1–2 | Compact juvenile body, oversized eyes, small feature or effect | Cute, but still the same animal rather than a generic baby |
| Awakened / 각성 | 3–4 | Longer or stronger body, confident pose, mature anatomy, one expanded signature feature | No full costume or unrelated mutation |
| Transcendent / 초월 | 5–6 | Distinct heroic silhouette, a second structural change, controlled magical motif | The face and species must remain recognizable; no screen-filling glow |

At 64 display pixels, a user should distinguish the stages by **body outline even in grayscale**. Use glow only as a secondary cue. Each species has one stable marking and one stable accent color. All three stage images should share a visible eye color and recognizable head shape.

## Existing species — preserve the current identity

### 01. Pine Fox / 솔여우 (`pine_fox`)

**Identity prompt:** A small forest fox with leaf-shaped ears, warm amber eyes, cream muzzle and chest, moss-green fur, dark brown paws, and a broad tail with layered pine-needle and cream markings. Friendly guide of the forest paths; balanced role. The head, two leaf ears, amber eyes and pine tail are the invariant identifiers. Use `pine-fox.png` as the reference.

| Stage | Add this exact direction to the identity and universal prompts |
|---|---|
| Seed | Compact round fox, paws close together, very large ears, one short pine-fan tail, cautious but eager stance. Moss-green back and warm cream face dominate. No floating magic. |
| Awakened | Taller athletic fox with visibly longer legs and a lifted chest; pine-fan tail divides into two layered fronds. Ears widen and angle forward, paws are planted in a confident scout stance. A few small turquoise pollen lights surround the tail, without obscuring it. |
| Transcendent | Sleek adult forest guardian, roughly one head taller in visual proportion, with a long sweeping triple-layer pine tail and a small natural cedar crest growing between the ears. Darker forest-green mantle of fur across shoulders, cream face still unmistakable, amber eyes bright. A thin ring of floating leaf motes follows the tail; no metal armor or crown. |

### 02. Wave Otter / 파도수달 (`wave_otter`)

**Identity prompt:** A playful water otter with a navy-blue back, pale cream face and belly, bright cyan water curls on cheeks and tail, round ears and lively blue eyes. Explorer role. Preserve the round otter face, cream mask, cyan cheek curls and curling wave tail from `wave-otter.png`.

| Stage | Add this exact direction |
|---|---|
| Seed | Short, low otter body with wide paws, an oversized head, and one small wave curling at the tail tip. Curious forward lean, soft cream belly, tiny cyan droplets. |
| Awakened | Longer streamlined body and stronger shoulders, webbed paws clearly readable, tail forming a larger single cresting wave. The otter stands half-upright like a river scout; cheek curls flow backward. Two small water ribbons follow its movement. |
| Transcendent | Elegant adult river navigator with a broad wave-shaped tail that splits into two flowing arcs, pronounced shoulder fur like rippling water, and a slender turquoise dorsal stripe. One front paw is raised as if steering a current. Water arcs frame but never cover the face or limbs; no trident or costume. |

### 03. Star Crow / 별까마귀 (`star_crow`)

**Identity prompt:** A small magical crow with midnight-navy and purple feathers, cream chest and face accents, amber-orange eyes and feet, a short dark beak, and small gold star patterns in the wings. Observant sky scout. Preserve the face, orange eyes, gold specks and forked feather tail from `star-crow.png`.

| Stage | Add this exact direction |
|---|---|
| Seed | Rounded chick-like crow standing on two feet, folded wings, large bright orange eyes, a few tiny stars on the wing tips. Gentle curious head tilt. |
| Awakened | Leaner crow with a longer neck and legs, one wing half-open to reveal a bold constellation pattern; tail gains a second feather tier. Attentive sentinel posture and a sparse violet star trail. |
| Transcendent | Regal but still approachable adult crow with two broad layered wings partly spread, long forked tail and a crescent-shaped pale chest marking. Gold star clusters run along the feather edges and a few distinct bright points hover behind, like a small personal sky. Do not turn the wings into a cloak or obscure the bird's body. |

## Planned species — art concepts only

The following nine creatures make a **candidate 12-species first collection**, with six forest companions and three each for a future marsh and ridge region. Names, rarity, combat abilities, drop rates and unlock stages are provisional. Do not add IDs to the app or promise availability until the art, encounter design and reward economy are approved. Each row is a separate stage direction to combine with the universal prompt and its species identity.

### 04. Mossback Tortoise / 이끼거북 (`moss_tortoise`) — pine forest, front-line guardian

**Identity prompt:** A low forest tortoise with a domed deep-green shell, moss and tiny ferns growing from shell seams, warm brown skin, amber eyes and broad sturdy feet. A pale spiral shell mark must remain in every stage. No stone armor or buildings on its back.

| Stage | Direction |
|---|---|
| Seed | Palm-sized round tortoise, soft low shell, one moss tuft and a tiny fern bud, shy head peeking out. |
| Awakened | Wider shell with three distinct raised moss plates, thicker legs, two small ferns, head held forward; spiral mark expands across the shell. |
| Transcendent | Large ancient forest tortoise with a tall layered living shell, one small bonsai-like cedar sprout, four strong feet and a confident open stance; shell spiral glows faintly green but remains visible. |

### 05. Lantern Moth / 등불나방 (`lantern_moth`) — pine forest, support

**Identity prompt:** A nocturnal moth with a plush navy body, cream face, long feathered antennae and translucent mint wings with two large lantern-shaped markings. Its luminous markings are the key identifier. Soft, kind expression; no humanoid arms.

| Stage | Direction |
|---|---|
| Seed | Small round moth resting on six tiny legs, wings folded like a short cape, one dim mint lantern mark per wing. |
| Awakened | Taller thorax, larger open triangular wings, longer curved antennae, two-tier lantern marks and a few floating firefly dots. |
| Transcendent | Broad four-lobed wings like stained moonlight, elongated elegant body, antennae forming a wide arch; luminous mint lantern patterns create a clear symmetrical silhouette. Keep the body fully visible and effects sparse. |

### 06. Briar Hare / 가시토끼 (`briar_hare`) — pine forest, swift scout

**Identity prompt:** A quick woodland hare with warm russet fur, cream muzzle, green thorn-leaf markings along its back, one notched ear and a round white tail. Bright teal eyes. Thorns look like flexible leaves, not painful spikes.

| Stage | Direction |
|---|---|
| Seed | Tiny crouched hare with oversized ears, one leaf-shaped tuft on the back and forepaws ready to hop. |
| Awakened | Longer hind legs and upright athletic stance, a short vine mane down the spine, notched ear raised high and three leaf-thorns fanning from the tail. |
| Transcendent | Powerful runner with long balanced legs, swept-back ear silhouette, flowing green briar mane and a loop of leaf-shaped motes tracing a leap. Show both feet and the original white tail. |

### 07. Reed Heron / 갈대왜가리 (`reed_heron`) — tidal marsh, ranged watcher

**Identity prompt:** A slender blue-gray heron with cream throat, dark indigo crown, copper eyes, long orange legs and reed-shaped teal wing feathers. One diagonal pale line through each wing is invariant. No clothing, bow or spear.

| Stage | Direction |
|---|---|
| Seed | Short juvenile heron with rounded body, long legs that look slightly too big, folded reed wings, inquisitive tilted head. |
| Awakened | Tall poised heron standing on one leg, longer neck, one wing extended to show layered reed feathers and the pale diagonal line. |
| Transcendent | Graceful marsh sentinel with long S-curved neck, two broad reed-fan wings partly spread, trailing teal feather tips and a thin crescent of water behind its feet. |

### 08. Pebble Newt / 자갈도롱뇽 (`pebble_newt`) — tidal marsh, defender

**Identity prompt:** A friendly amphibian newt with dark slate skin, turquoise belly, round gold eyes, four toes on each foot, and smooth river pebbles embedded along its back. The three pebble spots on the head must stay recognizable. No hard metallic armor.

| Stage | Direction |
|---|---|
| Seed | Squat tiny newt with wide smiling mouth, short tail, three head pebbles and one round back stone. |
| Awakened | Longer low body and stronger limbs, tail flattened for swimming, pebbles form two overlapping rows; head spots stay visible. |
| Transcendent | Broad-shouldered river guardian with a sweeping fin tail, natural stone ridge that arches above the back, turquoise belly glowing softly and a few water rings around planted feet. |

### 09. Rainbell Frog / 빗방울개구리 (`rainbell_frog`) — tidal marsh, healer

**Identity prompt:** A plump emerald frog with a pale blue belly, amber eyes, blue drop-shaped markings on the cheeks and a small bell-shaped throat pouch. Calm, encouraging expression. The cheek drops and throat pouch are invariant; no staff or clothes.

| Stage | Direction |
|---|---|
| Seed | Round frog sitting low, tiny throat pouch and two small cheek drops; hands held near chest. |
| Awakened | Longer springy legs, fuller bell pouch and a soft blue stripe along the back; one hand raised as if calling rain. |
| Transcendent | Large confident rain caller with long hind legs, leaf-like crest above the eyes, prominent glowing throat bell and a restrained ring of three droplets; face remains unmistakably frog-like. |

### 10. Cinder Lynx / 잿불스라소니 (`cinder_lynx`) — dawn ridge, attacker

**Identity prompt:** A small mountain lynx with charcoal fur, cream chin, amber eyes, long black ear tufts and ember-orange stripes on legs and tail. The paired orange cheek stripes stay at every stage. Warm sparks, not large flames; no armor.

| Stage | Direction |
|---|---|
| Seed | Compact fluffy kitten-like lynx, oversized ear tufts, short striped tail and one tiny ember at the tail tip. |
| Awakened | Lean long-legged lynx with pronounced shoulder muscles, upright ear tufts, longer ringed tail and ember stripes extending across the back. |
| Transcendent | Tall powerful ridge runner with angular fur silhouette, twin high ear tufts, a broad sweeping ember tail and a narrow warm glow tracing the original cheek stripes; paws firmly grounded. |

### 11. Cloud Antelope / 구름영양 (`cloud_antelope`) — dawn ridge, support

**Identity prompt:** A gentle antelope with pale cream fur, blue-gray legs, violet eyes, short cloud-curled horns and a small cloud mark on its chest. The curled horn shape and chest mark are invariant. Airy but physically grounded; no wings.

| Stage | Direction |
|---|---|
| Seed | Small fawn with short legs, tiny curled horn buds, oversized ears and a single pale cloud mark. |
| Awakened | Longer agile legs, slender torso, two full spiral cloud horns and a flowing blue-gray mane; alert upright pose. |
| Transcendent | Elegant adult antelope with high branching cloud horns, long sweeping mane and a visible chest cloud motif; a thin loop of mist trails from the hooves but does not hide the legs. |

### 12. Prism Pangolin / 수정천산갑 (`prism_pangolin`) — dawn ridge, defender

**Identity prompt:** A compact pangolin with overlapping indigo scales, cream face, dark eyes, strong digging claws and a curved tail. Small turquoise crystal reflections appear inside selected scales, but the scales must read as natural keratin, not plate armor. Three bright shoulder scales are invariant.

| Stage | Direction |
|---|---|
| Seed | Round youngster with short curled tail, soft overlapping scales and three bright shoulder scales; shy but steady. |
| Awakened | Longer muscular body and tail, larger layered scales, strong foreclaws and a partial defensive curl that still shows the face. |
| Transcendent | Broad grounded guardian with a long spiral tail forming a readable arc, raised scale ridge across shoulders and controlled turquoise reflections in alternating scales; face and all four limbs visible. |

## Consistency and animation handoff

1. Approve a contact sheet of the three **static** stages for one species before requesting animation. Reject any stage that changes eye color, face, signature mark or pixel size, or differs only by a glow.
2. Produce one transparent portrait for each approved stage. Compare 96 px and 64 px downscales on both light and dark app backgrounds. Inspect for stray opaque pixels and cropped extremities.
3. Only after static stages pass, generate **separate** strips for idle, walk, attack, hit, victory and defeat. Each strip is 4 equal frames, 543×724 per frame, 2172×724 overall. Center the character on the same 543×724 cell; feet baseline at y=650; at least 12 transparent pixels at the left and right of every cell. Never allow a tail or effect to bleed into the next frame.
4. Use clear action silhouettes: idle breath and blink; walk with alternating foot contact; attack windup/strike/recover; hit recoil; victory lift; defeat tired seated pose. No always-running idle bounce in the collection or home screens; the current app intentionally uses still art there because the first motion attempt looked unnatural.
5. Deliver a small manifest per strip: species ID, stage, action, frame count, frame size, duration in milliseconds, ground anchor, facing direction, PNG path and palette swatches. Mirror frames in code only if asymmetric markings remain correct; otherwise generate both directions.
6. Keep visual rarity cosmetic. Do not silently make rarer art stronger or introduce paid draws. Confirm encounter and collection rules before wiring any of the nine planned species into rewards.

## Rejection checklist for the other image AI

- Three stages look like different characters, or the stage difference is only aura/color.
- Smooth illustration disguised by a pixel filter; inconsistent pixel grids or translucent antialiasing.
- Cut-off wings, feet or tail; changing ground baseline; glow inside required transparent margins.
- Tiny high-detail face that disappears at 64–96 px; unreadable overlap of limbs and effects.
- Existing franchise resemblance, text, UI elements, scenery embedded in a creature portrait, watermark.
- Animation frames with different character size, shifted camera or neighboring-frame bleed.

Approval is visual and manual. These prompts are an art direction baseline, not an instruction to generate or integrate images automatically.
