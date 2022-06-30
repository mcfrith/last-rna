# Aligning long DNA and RNA reads to a genome

These recipes are designed for "long" reads, e.g. nanopore or PacBio
([see
also](https://gitlab.com/mcfrith/last/-/blob/main/doc/last-cookbook.rst)).
Strong points of these recipes:

* They determine the rates of insertion, deletion, and each kind of
  substitution in the reads, and use these rates to determine the most
  probable alignments.

* They find the most-probable division of each read into (one or more)
  parts together with the most probable alignment of each part.  So
  they can handle arbitrarily complex rearrangements and duplications
  in the reads relative to the genome, and discriminate between
  similar sequences.

First, install the latest [LAST][].  **This document assumes LAST
version >= 1387!!!**

## Preparing a reference genome

Get a reference genome sequence, in FASTA format.  We need to
[index][lastdb] the genome before aligning things to it:

    lastdb -P8 -uRY4 mydb genome.fa

This will create several files with names starting in "mydb".

* `-P8` makes it faster by running 8 parallel threads, adjust as
  appropriate for your computer.  This has no effect on the results.

* `-uRY4` makes alignment faster and less memory-consuming, but less
  sensitive, than the default.  This is suitable for aligning dozens
  of gigabases to a mammal genome.

For smaller genomes, or less data, or higher sensitivity, do this:

    lastdb -P8 -uNEAR mydb genome.fa

* `-uNEAR` tunes it for finding alignments with low rates of
  substitution (especially if they have high rates of insertion or
  deletion).

## Substitution and gap rates

Next, we can [determine the rates of insertion, deletion, and
substitutions][train] between our reads and the genome:

    last-train -P8 -Q0 mydb myseq.fq > myseq.par

* You can supply the reads in either FASTA (`.fa`) or FASTQ (`.fq`)
  format: it makes no difference.

* `-P8` makes it faster by running 8 parallel threads (no effect on
  results).

* `-Q0` makes it discard fastq quality data (or you can
  keep-but-ignore it with `-Qkeep`).

The training should be done separately for different kinds of
sequence, e.g. MinION 1d and 2d, which are likely to have different
substitution and gap rates.  It should also be done separately for
sequences with unusual composition, e.g. extremely AT-rich
*Plasmodium* DNA.

## Aligning DNA (or unspliced RNA) sequences

This recipe aligns DNA reads to their orthologous bases in the genome:

    lastal -P8 --split -p myseq.par mydb myseq.fq > myseq.maf

If you have big data, you may wish to compress the output.  One way is
to modify the preceding command like this:

    lastal -P8 --split -p myseq.par mydb myseq.fq | gzip > myseq.maf.gz

If necessary, you can get faster but slightly worse compression with
e.g. `gzip -5`.

## Spliced alignment of RNA or cDNA sequences

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
probably won't avoid them completely:

    lastal -P8 --splice -D10 -d90 -m20 -p myseq.par mydb myseq.fq > myseq.maf

**This assumes the reads are from forward strands of transcripts!!!**
If your reads are a mixture of forward and reverse strands, do this to
check splice signals (such as `gt`-`ag`) in both orientations:

    lastal -P8 --split-d=2 -D10 -d90 -m20 -p myseq.par mydb myseq.fq > myseq.maf

`-d90 -m20` makes it more accurate but slow.

* For even higher accuracy (but slowness), I would use `-m50` instead
  of `-m20`.  In my tests with R9.4 2d sequences, this changed less
  than 1% of the alignments.

* For higher speed (but lower accuracy), omit `-m20`.  In my tests,
  this changed less than 2% of the alignments compared to `-m50`.

## Alignment format conversion & visualization

This converts the alignments to psl, a common format for RNA-genome
alignments, which can be displayed in genome viewers:

    maf-convert -j1e6 psl myseq.maf > myseq.psl

* `-j1e6` tells it to join exons separated by up to 10^6 bases into
  one alignment.

## Aligning RNA or cDNA to a transcriptome?

Untested suggestions:

* Basically, use the above "Aligning DNA (or unspliced RNA) sequences"
  recipe.

* Perhaps use `lastal` option `-m20` or `-m50`.  This makes it more
  sensitive but slower. It especially helps to find alignments of
  sequences that are repeated many times in the reference
  (e.g. overlapping isoforms).

## Changes

2022-06: Recommend the faster `RY4` option, and split-in-lastal
         instead of separate `last-split`.

2021-03: Previously, `lastdb` option `-R01` was suggested.  But this
         is the default setting since LAST 1205.

2021-02-16: Previously, `last-split` option `-fMAF` was suggested.
            But this is the default setting since LAST 1180.

2020-06-11: Previously, `last-split` option `-m1` was specified.  But
            this is the default setting since LAST 983.

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

## Appendix C: Fixing read identifiers

Each read should have a short, unique "name" or "identifier".
Unfortunately, these identifiers are often ridiculously long, which
makes things inefficient and inconvenient.  Worse, unique identifiers
sometimes contain spaces (which are used as field separators in many
formats).  One fix is to replace the identifiers with serial numbers.

FASTA -> FASTA with serial numbers:

    awk '/>/ {$0 = ">" ++n} 1' nasty.fa > nice.fa

FASTQ -> FASTA with serial numbers:

    awk 'NR % 4 == 2 {print ">" ++n "\n" $0}' myseq.fq > myseq.fa

Some care is needed: if you do this separately for two datasets, and
later combine them, then the serial numbers will not be unique.

## Appendix D: Repeat masking

This is an alternative recipe, which was used in several published
papers.  It makes the alignment faster by "masking" repeats (instead
of using `RY4`).

First, download [NCBI BLAST][], which includes WindowMasker.  Apply
WindowMasker to the genome:

    windowmasker -mk_counts -in genome.fa > genome.wmstat
    windowmasker -ustat genome.wmstat -outfmt fasta -in genome.fa > genome-wm.fa

This outputs a copy of the genome (`genome-wm.fa`) with interspersed
repeats in lowercase.  Now index the genome:

    lastdb -P8 -uNEAR -R11 -c mydb genome-wm.fa

* `-R11` tells it to preserve lowercase in the input, and additionally
  convert simple sequence to lowercase.

* `-c` tells it to "mask" lowercase.

The subsequent `last-train` and alignment steps are the same as above.

[LAST]: https://gitlab.com/mcfrith/last
[lastdb]: https://gitlab.com/mcfrith/last/-/blob/main/doc/lastdb.rst
[train]: https://gitlab.com/mcfrith/last/-/blob/main/doc/last-train.rst
[NCBI BLAST]: https://blast.ncbi.nlm.nih.gov/
