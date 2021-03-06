#!/bin/bash

# first arg:  build_dir
# second arg: report path
# third arg: should we use perlbrew?

# this is getting smelly
builddir=$1
report_path=$2
perlbrew=$3

function jitterbug_build () {
        echo "Found Build.PL, using Build.PL"
        perl Build.PL >> $logfile 2>&1
        # ./Build installdeps is not available in older Module::Build's
        cpanm --installdeps . >> $logfile 2>&1
        # Run this again in case our Build is out of date (suboptimal)
        perl -Ilib t/test_all.pl >> $logfile 2>&1
        HARNESS_VERBOSE=1 ./Build test --verbose >> $logfile 2>&1
}


echo "Creating report_path=$report_path"
mkdir -p $report_path

cd $builddir

if [ $use_perlbrew ]; then
    source $HOME/perl5/perlbrew/etc/bashrc
    for perl in $HOME/perl5/perlbrew/perls/perl-5.*
    do
        theperl=$(perl -e 'print $^V')
        logfile="$report_path/perl-$theperl.txt"

        echo ">perlbrew switch $theperl"
        perlbrew switch $theperl
        # TODO: check error condition

        jitterbug_build
    done
else
        theperl=$(perl -e 'print $^V')
        logfile="$report_path/perl-$theperl.txt"
        jitterbug_build
fi
