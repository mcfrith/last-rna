#! /usr/bin/env python

# Read MAF-format alignments from last-split, and classify the
# alignment of each query.

import itertools
import operator
import optparse
import sys

def mafInput(opts, lines):
    for line in lines:
        if line[0] == "a":
            rName = ""
            mismap = 0.0
            for i in line.split():
                if i.startswith("mismap="):
                    mismap = float(i[7:])
        elif line[0] == "s" and mismap <= opts.max_mismap:
            fields = line.split()
            if not rName:
                rName = fields[1]
                rBeg = int(fields[2])
                rEnd = rBeg + int(fields[3])
            else:
                qName = fields[1]
                strand = fields[4]
                if strand == "-":
                    rBeg, rEnd = -rEnd, -rBeg
                rNameAndStrand = rName + strand
                yield qName, rNameAndStrand, rBeg, rEnd

def spliceType(x, y, maxDistance):
    xJunk, xNameAndStrand, xBeg, xEnd = x
    yJunk, yNameAndStrand, yBeg, yEnd = y
    assert xBeg < xEnd
    assert yBeg < yEnd
    if xNameAndStrand != yNameAndStrand: return "t"
    if (xBeg < 0) != (yBeg < 0): return "t"
    if xEnd > yBeg: return "t"  # ?
    if xEnd + maxDistance < yBeg: return "b"
    return "c"

def partsFromAlignments(alignments, opts):
    exonCount = 0
    old = None
    for i in alignments:
        if old:
            t = spliceType(old, i, opts.max_intron)
            if t != "c":
                yield str(exonCount)
                yield t
                exonCount = 0
        exonCount += 1
        old = i
    yield str(exonCount)

def doOneQuery(opts, qName, alignments):
    parts = list(partsFromAlignments(alignments, opts))
    if len(parts) > 1: transSpliced = "T"
    else:              transSpliced = "C"
    if "1" in parts: unspliced = "U"
    else:            unspliced = "S"
    text = "".join(partsFromAlignments(alignments, opts))
    out = transSpliced, unspliced, text
    print qName + "\t" + ":".join(out)

def doOneFile(opts, lines):
    alignments = mafInput(opts, lines)
    for k, v in itertools.groupby(alignments, operator.itemgetter(0)):
        doOneQuery(opts, k, list(v))

def alignmentTypes(opts, args):
    if args:
        for i in args:
            if i == "-":
                doOneFile(opts, sys.stdin)
            else:
                with open(i) as f:
                    doOneFile(opts, f)
    else:
        doOneFile(opts, sys.stdin)

if __name__ == "__main__":
    usage = "%prog [options] alignments.maf"
    op = optparse.OptionParser(usage=usage)
    op.add_option("-m", "--max-mismap", type="float", default=1.0,
                  metavar="M", help="default=%default")
    op.add_option("-i", "--max-intron", type="float", default=1e6,
                  metavar="B", help="default=%default")
    opts, args = op.parse_args()
    alignmentTypes(opts, args)
