#!/bin/env bash

scriptDir=$BATS_TEST_DIRNAME
export projectRoot=${scriptDir}/../..

###################
# Prod atlasprod (in-house) Perl modules
export PERL5LIB=$projectRoot/perl_modules:$PERL5LIB
