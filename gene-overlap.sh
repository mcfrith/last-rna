#! /bin/sh

export LC_ALL=C

[ $# -eq 2 ] || {
    echo "usage: $0 path/to/ucscGene.txt path/to/alignments.maf > out.txt"
    exit 2
}
genes=$1
alignments=$2

maxMismap=1  # ?

tmp=${TMPDIR:-/tmp}/$$
trap 'rm -f $tmp.*' EXIT

topPerKey () {
    awk '$1 != k {print; k = $1}' "$@"
}

sumPerKey () {
    awk '
$1 != k {if (k) print k, s; s = 0; k = $1} {s += $2} END {if (k) print k, s}
' "$@"
}

segAddQueryLengths () {
    awk '{print $4, $0}' "$@" | sort > $tmp.z
    sumPerKey $tmp.z | join - $tmp.z | awk '$6 = $6 "&" $2' | cut -d' ' -f3- | seg-sort
}

topOverlap () {
    sumPerKey "$@" | tr '!' ' ' | sort -k1,1 -k3,3nr -k2,2 | topPerKey
}

segFromMaf () {
    grep -v '^#' "$@" | sed 's/ mismap=\([^ ]*\).*/ \1/' |
    awk '$3 <= '$maxMismap' {print $7, $5, $6, $12, $6}' RS="" |
    seg-sort | seg-merge | segAddQueryLengths
}

segFromGenes () {
    seg-import genePred "$@" | awk '$5 = "" $3' |
    seg-sort | seg-merge | segAddQueryLengths
}

segFromMaf $alignments > $tmp.r
segFromGenes $genes > $tmp.g

echo "#RNA RNAlen GENE GENElen overlap" | tr ' ' '\t'

seg-join $tmp.r $tmp.g | awk '{print $4 "!" $6, $1}' | sort | topOverlap |
tr '& ' '\t\t' | sort -k3,3
