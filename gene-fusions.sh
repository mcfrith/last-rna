#! /bin/sh

export LC_ALL=C

PATH=$PATH:$(dirname $0)

[ $# -eq 2 ] || {
    echo "usage: $0 path/to/ucscGene.txt path/to/alignments.maf > out.txt"
    exit 2
}
genes=$1
alignments=$2

maxMismapProb=1e-6
minBasesIn2ndGene=20

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

segQueryLengths () {
    awk '{print $4, $1}' "$@" | sort | sumPerKey
}

segDecorate () {
    awk '{print $2 "!" $4, $0}' "$@" | sort
}

topOverlap () {
    sumPerKey "$@" | tr '!' ' ' | sort -k1,1 -k3,3nr -k2,2 | topPerKey
}

topSegs () {
    sed 's/ /!/' $1 | join - $2 | cut -d' ' -f3- | seg-sort
}

segFromMaf () {
    grep -v '^#' "$@" | sed -e 's/ mismap=/ /' -e 's/ sense=.*//' |
    awk '$3 <= '$maxMismapProb' {print $7, $5, $6, $12, $6}' RS="" |
    seg-sort | seg-merge | seg-sort
}

segFromGenes () {
    seg-import genePred "$@" | awk '$5 = "" $3' |
    seg-sort | seg-merge | seg-sort
}

segFromMaf $alignments > $tmp.r
segFromGenes $genes > $tmp.g

segQueryLengths $tmp.r > $tmp.len

alignment-types.py $alignments | sed 's/.://' | sort > $tmp.types

seg-join $tmp.r $tmp.g | cut -f1,4- | seg-sort > $tmp.j0

segDecorate $tmp.j0 > $tmp.d0
topOverlap $tmp.d0 > $tmp.1

topSegs $tmp.1 $tmp.d0 |
seg-join -v1 $tmp.j0 - > $tmp.j1

segDecorate $tmp.j1 > $tmp.d1
topOverlap $tmp.d1 > $tmp.2

echo "#RNA RNAlen pattern gene1 overlap1 gene2 overlap2" | tr ' ' '\t'

join $tmp.len $tmp.types |
join - $tmp.1 |
join - $tmp.2 |
awk '$7 >='$minBasesIn2ndGene |
tr ' ' '\t' |
sort -k4,4 -k6,6
