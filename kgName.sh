#! /bin/bash

export LC_ALL=C

[ $# -eq 2 ] || {
    echo "usage: $0 path/to/knownGene.txt path/to/kgXref.txt"
    exit 2
}

join <(cut -f1,5 $2 | sort) <(sort $1) |
awk '$2 = $2 "," $1' | tr ' ' '\t' | cut -f2-
