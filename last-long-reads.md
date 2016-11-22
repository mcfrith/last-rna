# Aligning long DNA and RNA reads to a genome

These recipes have been tested on MinION R9.4 human RNA sequences, but
they should work for any similar kind of data.

## Setup

For aligning to a mammal genome, you'll need a few dozen gigabytes of
memory.

First, install the latest [LAST](http://last.cbrc.jp/) (version >=
802).

Get a reference genome sequence, in FASTA format.  We need to "index"
the genome before aligning things to it:

    lastdb -P8 -uNEAR -R01 mydb genome.fa

* This will create several files with names starting in "mydb".

* `-P8` tells it to use 8 processors: modify this as you wish.

* `-uNEAR` tunes it for finding alignments with low rates of
  substitution (especially if they have high rates of insertion or
  deletion).

* `-R01` makes it indicate "simple sequence" such as `atatatatatatat`
  by lowercase.  (This actually has no effect on the following
  alignment recipes, but it keeps open the option to discard
  simple-sequence alignments.)

## Pre-alignment

If the reads are in FASTQ (fq) format, convert them to FASTA (fa),
e.g. like this:

    awk 'NR % 4 == 1 {print ">" (++x)} NR % 4 == 2' myseq.fq > myseq.fa

Next, we can determine alignment parameters (substitution and gap
scores) that fit these sequences:

    last-train -P8 mydb myseq.fa > myseq.par

* `-P8` tells it to use 8 processors: modify this as you wish.

The training should be done separately for different kinds of
sequence, e.g. MinION 1d and 2d, which are likely to have different
substitution and gap rates.

## Aligning DNA sequences

DNA is easier than RNA, so is described first.  This recipe aligns DNA
reads to their orthologous bases in the genome, allowing for
rearrangements and duplications in the reads relative to the genome.

    lastal -P8 -p myseq.par mydb myseq.fa | last-split -m1e-6 > myseq.maf

* `-P8` tells it to use 8 processors: modify this as you wish.

* `-m1e-6` tells it to omit any alignment whose probability of having
  the wrong genomic locus is > 10^-6.  (This happens if part of a read
  matches multiple loci almost equally well.)

This recipe is perhaps more slow-and-sensitive than necessary:
[here](http://last.cbrc.jp/doc/last-tuning.html) are some ways to make
it faster.

## Aligning RNA sequences

This recipe aligns RNA reads to their orthologous bases in the genome,
allowing for exon/intron splicing.  It favors typical human splice
signals (especially `gt`-`ag`), but does not require them.  It favors
co-linear exons with typical human intron lengths, but it allows
"trans" splices between any points in the genome.

Correct alignment is difficult for some RNAs, because some exons are
short and hard to find, especially if there are many insertion or
deletion errors.  A typical mistake is to misalign (part of) an RNA to
a processed pseudogene, which lacks introns, allowing a contiguous
alignment.  This recipe tries to minimize such mistakes, but it
probably won't avoid them completely.

The recipe requires [GNU
parallel](https://www.gnu.org/software/parallel/) to be installed,
which can be done like this:

    wget http://ftpmirror.gnu.org/parallel/parallel-latest.tar.bz2
    bunzip2 parallel-latest.tar.bz2
    tar xf parallel-latest.tar
    mkdir -p ~/bin
    cp parallel-*/src/parallel ~/bin/

The recipe is:

    parallel-fasta "lastal -p myseq.par -d90 -m50 -D10 mydb | last-split -d2 -g mydb" < myseq.fa > myseq.maf

* `-d2` indicates that the RNA reads are from unknown/mixed RNA
  strands.  This makes it check splice signals (such as `gt`-`ag`) in
  both orientations.

* `-d90 -m50` makes it more slow and sensitive, perhaps excessively
  so.  In my tests with R9.4 2d sequences, replacing `-m50` with
  `-m20` made it much faster while changing less than 1% of the
  alignments.  Replacing it with `-m10` (the default) made it much
  faster still while changing less than 2% of the alignments.

## Alignment format conversion & visualization

This converts the alignments to psl, a common format for RNA-genome
alignments, which can be displayed in genome viewers:

    maf-convert -j1e6 psl myseq.maf > myseq.psl

* `-j1e6` tells it to join exons separated by up to 10^6 bases into
  one alignment.

## Appendix A: Which genome sequence to use?

For human data, I use `hg38.analysisSet` from here:
<http://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/analysisSet/>.

One advantage of this "analysis set" is that it lacks assembly
duplications.  For example, identical pseudo-autosomal regions (PARs)
are placed on both chrX and chrY in the original assembly.  So
sequences from PARs will align ambiguously to both, and likely be
discarded due to their ambiguity.  The analysis set masks the chrY
PARs, solving this problem.

If any of your samples are thought to include viruses, consider adding
the viral chromosomes to your reference genome.

## Appendix B: Which MinION sequences to use?

These are my observations of some MinION datasets from August /
September 2016.

Each dataset includes six files: `pass_2d`, `pass_fwd`, `pass_rev`,
`fail_2d`, `fail_fwd`, `fail_rev`.  The main one to use is `pass_2d`.
If that does not suffice, you can also use the lower-quality
`fail_fwd`.

It seems that `pass_fwd` and `pass_rev` have (lower-quality sequences
of) the same molecules as `pass_2d`, so there is little point in using
them.

It seems that `fail_rev` has a subset of the molecules in `fail_fwd`,
and `fail_2d` has a subset of the molecules in `fail_rev`.  Also, the
`fail_2d` sequences do not seem to be more accurate than the
`fail_fwd` ones.  So there is little point in using `fail_rev` or
`fail_2d`.
