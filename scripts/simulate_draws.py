"""Check the first five free draws for the three starter species."""

from collections import Counter
from random import Random


SPECIES = ('pine_fox', 'wave_otter', 'star_crow')
WEIGHTS = (50, 30, 20)
TRIALS = 100_000
random = Random(20261101)

for starter in SPECIES:
    first_full = Counter()
    for _ in range(TRIALS):
        discovered = {starter}
        for draw_number in range(1, 6):
            missing = [species for species in SPECIES if species not in discovered]
            if missing and (draw_number == 1 or draw_number % 5 == 0):
                species = random.choice(missing)
            else:
                species = random.choices(SPECIES, weights=WEIGHTS)[0]
            discovered.add(species)
            if len(discovered) == len(SPECIES):
                first_full[draw_number] += 1
                break
    print(starter, dict(sorted(first_full.items())))
    assert sum(first_full.values()) == TRIALS
