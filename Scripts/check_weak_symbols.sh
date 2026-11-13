#!/bin/zsh
# Refuses a build of Peel whose programs link weakly to a Swift symbol of the system that `Scripts/weak-symbols.txt`
# doesn't list. A symbol a newer SDK declares back-deployed, as macOS 27.2's `Date.<=` and `Date.>=` are, is linked
# weakly and called only on a system that says it has it, so a beta that says so without having it stops Peel. The
# symbols on the list are those Peel uses only under `#available`, or that a dependency needs.
#
#   zsh Scripts/check_weak_symbols.sh <Peel.app>

set -euo pipefail

app=${1:?the path of Peel.app}
known=${0:A:h}/weak-symbols.txt
[[ -d $app/Contents ]] || { echo "REFUSED: $app is not an app"; exit 1; }

typeset -U allowed
allowed=(${(f)"$(grep -v '^#' $known | grep -v '^$')"})

failed=0
for executable in $app/Contents/MacOS/* $app/Contents/Helpers/* $app/Contents/PlugIns/*/Contents/MacOS/*(N)
do
    file -b $executable | grep -q 'Mach-O' || continue
    weak=$(nm -m $executable 2>/dev/null | grep 'weak external' | awk '{print $4}' | grep '^_\$s' | sort -u || true)
    for symbol in ${(f)weak}
    do
        (( ${allowed[(Ie)$symbol]} )) && continue
        echo "REFUSED: ${executable#$app/} links weakly to $symbol, which $known doesn't list"
        failed=1
    done
done
(( failed == 0 )) || exit 1
echo "No program links weakly to a Swift symbol of the system that isn't listed"
