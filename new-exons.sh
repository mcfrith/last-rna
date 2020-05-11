#! /bin/sh

export LC_ALL=C

PATH=$PATH:$(dirname $0)

[ $# -eq 2 ] || {
    echo "usage: $0 path/to/ucscGene.txt path/to/alignments.maf > out.bed"
    exit 2
}
genes=$1
alignments=$2

maxMismap=1e-6

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

topOverlap () {
    sumPerKey "$@" | tr '!' ' ' | sort -k1,1 -k3,3nr -k2,2 | topPerKey
}

segFromMaf () {
    grep -v '^#' "$@" | sed 's/ mismap=\([^ ]*\).*/ \1/' |
    awk '$3 <= '$maxMismap' {print $7, $5, $6, $12, $6}' RS="" |
    seg-sort | seg-merge | seg-sort
}

segFromGenes () {
    seg-import genePred "$@" | awk '$5 = "" $3' |
    seg-sort | seg-merge | seg-sort
}

segFromMaf $alignments > $tmp.r
segFromGenes $genes > $tmp.g

# RNAs that don't have abnormal "trans" splicing:
alignment-types.py $alignments | grep -v T: | cut -f1 | sort > $tmp.cis

# RNAs that overlap annotated genes:
seg-join $tmp.r $tmp.g | awk '{print $4 "!" $6, $1}' | sort | topOverlap > $tmp.k

seg-join -v1 -c1 $tmp.r $tmp.g |  # exons that don't overlap annotated genes
awk '{print $4, $2, $3, $1}' |  # RNA_id, chrom, start, length
sort |
join - $tmp.cis |  # omit exons from RNAs with abnormal splicing
join - $tmp.k |    # omit exons from RNAs that don't overlap genes at all
awk '{print $2, $3, $3+$4, $5 ":" $1}' OFS="\t" |  # convert to BED format
sort -k1,1 -k2,2n -k3,3n -k4,4
