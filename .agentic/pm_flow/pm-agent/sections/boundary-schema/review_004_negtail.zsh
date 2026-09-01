#!/bin/zsh
set -u
for f in heading-keyed no-exclusion blank-deps; do
  print "########## $f ##########"
  tail -6 "/tmp/pm-review-004/neg/$f.err"
  print
done
