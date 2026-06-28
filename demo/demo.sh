#!/usr/bin/env bash
# Real demo: a tiny buggy module with two failing assertions. The fixes are applied for
# real (sed) and re-verified for real (python) at every step — that's the "verified step"
# the skill enforces. The loop narration mirrors the SKILL.md protocol.
set -euo pipefail
SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT; cd "$SBX"
say(){ printf '\033[1;36m$ %s\033[0m\n' "$1"; sleep .5; }
note(){ printf '\033[2m%b\033[0m\n' "$1"; sleep .5; }
run(){ python3 tests.py 2>&1 | tail -1; }

cat > calc.py <<'P'
def add(a, b):    return a - b        # bug
def is_even(n):   return n % 2 == 1   # bug
P
cat > tests.py <<'P'
from calc import add, is_even
assert add(2, 3) == 5, "add() is wrong"
assert is_even(4) is True, "is_even() is wrong"
print("ALL TESTS PASS")
P
git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init

echo; printf '\033[1mKeep going until it passes — verified every step, with a rollback snapshot.\033[0m\n'; sleep 1; echo
say 'python3 tests.py'
printf '   \033[31m✘ %s\033[0m\n' "$(run || true)"; sleep .6
note "/goal-loop   GOAL: make tests.py pass · scope: calc.py · snapshot: $(git rev-parse --short HEAD)"; sleep .5

echo; note "── iteration 1 ── fix add(), then VERIFY ──"
say 'sed fix add()  &&  python3 tests.py'
sed -i '' 's/return a - b/return a + b/' calc.py
printf '   \033[33m✘ %s\033[0m   (gate not passed → keep going)\n' "$(run || true)"; sleep .8

echo; note "── iteration 2 ── fix is_even(), then VERIFY ──"
say 'sed fix is_even()  &&  python3 tests.py'
sed -i '' 's/n % 2 == 1/n % 2 == 0/' calc.py
printf '   \033[32m✔ %s\033[0m\n' "$(run)"; sleep .8

echo; printf '\033[1;32mGOAL met in 2 verified iterations. main untouched — snapshot clean.\033[0m\n'; sleep 2.5
