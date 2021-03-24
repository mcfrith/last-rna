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

## Requirements

For aligning to a mammal genome, you'll need a few dozen gigabytes of
memory ([or
less](https://gitlab.com/mcfrith/last/-/blob/main/doc/last-cookbook.rst)
with `lastdb` option `-uRY`).

First, install the latest [LAST][].  **This document assumes LAST
version >= 983!!!**

## Preparing a reference genome

Get a reference genome sequence, in FASTA format.

We need to decide [whether or not to mask
repeats](https://gitlab.com/mcfrith/last/-/blob/main/doc/last-repeats.rst).
Repeat-masking harms alignment accuracy (by hiding some correct
alignments), but it *greatly* reduces the time and memory needed for
alignment.

* For DNA reads with multiple coverage of a mammal genome: I would
  probably mask repeats.

* For RNA or cDNA reads: I would probably not mask repeats.

Masking is often harmless.  Masked regions are ignored when finding
similar regions, but are included in the final alignments.  So masking
is harmless for alignments that include a bit of unmasked sequence
next to masked regions.

### Option 1: Prepare a genome without repeat-masking

We need to [index][lastdb] the genome before aligning things to it:

    lastdb -P8 -uNEAR mydb genome.fa

This will create several files with names starting in "mydb".  It will
detect and lowercase simple repeats, but it won't "mask" them.

* `-P8` makes it faster by running 8 parallel threads, adjust as
  appropriate for your computer.  This has no effect on the results.

* `-uNEAR` tunes it for finding alignments with low rates of
  substitution (especially if they have high rates of insertion or
  deletion).

### Option 2: Prepare a genome with repeat-masking

We wish to mask as little as possible for the sake of alignment
accuracy, but enough to make the alignment run-time tolerable.  LAST
can detect simple repeats such as `atatatatatatat`, but not (yet)
interspersed repeats: for that we can use WindowMasker.

First, download [NCBI BLAST][] (which includes WindowMasker).

Apply WindowMasker to the genome:

    windowmasker -mk_counts -in genome.fa > genome.wmstat
    windowmasker -ustat genome.wmstat -outfmt fasta -in genome.fa > genome-wm.fa

This outputs a copy of the genome (`genome-wm.fa`) with interspersed
repeats in lowercase.

Now index the genome:

    lastdb -P8 -uNEAR -R11 -c mydb genome-wm.fa

* `-R11` tells it to preserve lowercase in the input, and additionally
  convert simple sequence to lowercase.

* `-c` tells it to "mask" lowercase.

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

    lastal -P8 -p myseq.par mydb myseq.fq | last-split > myseq.maf

To make it faster (but less accurate), add `lastal` option `-k8`
(say).  This should still be accurate for straightforward alignments,
but perhaps not for intricately rearranged alignments.  (See also
[here](https://gitlab.com/mcfrith/last/-/blob/main/doc/last-cookbook.rst)
and
[here](https://gitlab.com/mcfrith/last/-/blob/main/doc/last-tuning.rst)).

If you have big data, you may wish to compress the output.  One way is
to modify the preceding command like this:

    lastal -P8 -p myseq.par mydb myseq.fq | last-split | gzip > myseq.maf.gz

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
probably won't avoid them completely.

The recipe requires [GNU parallel][] to be installed, which can be
done like this:

    wget http://ftpmirror.gnu.org/parallel/parallel-latest.tar.bz2
    bunzip2 parallel-latest.tar.bz2
    tar xf parallel-latest.tar
    mkdir -p ~/bin
    cp parallel-*/src/parallel ~/bin/

The recipe is:

    parallel-fasta -j8 "lastal -p myseq.par -d90 -m20 -D10 mydb | last-split -g mydb" < myseq.fq > myseq.maf

* `-j8` tells it to run 8 parallel jobs.

* **It assumes the reads are from forward strands of transcripts!!!**
  If your reads are a mixture of forward and reverse strands, add
  `last-split` option `-d2`: that makes it check splice signals (such
  as `gt`-`ag`) in both orientations.

* `-d90 -m20` makes it more accurate but slow.

    - For even higher accuracy (but slowness), I would use `-m50`
      instead of `-m20`.  In my tests with R9.4 2d sequences, this
      changed less than 1% of the alignments.

    - For higher speed (but lower accuracy), omit `-m20`.  In my
      tests, this changed less than 2% of the alignments compared to
      `-m50`.

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

[LAST]: https://gitlab.com/mcfrith/last
[lastdb]: https://gitlab.com/mcfrith/last/-/blob/main/doc/lastdb.rst
[train]: https://gitlab.com/mcfrith/last/-/blob/main/doc/last-train.rst
[NCBI BLAST]: https://blast.ncbi.nlm.nih.gov/
[GNU parallel]: https://www.gnu.org/software/parallel/
