#! /bin/sh

cd $(dirname $0)

PATH=..:$PATH

{
    rna-alignment-stats --help
    rna-alignment-stats test.psl
    rna-alignment-stats -g testFlat.txt test.psl
} | diff -u tests.out -
