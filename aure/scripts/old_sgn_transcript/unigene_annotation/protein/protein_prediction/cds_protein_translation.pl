#!/usr/bin/perl
=head1 NAME

cds_protein_translation.pl.
A script to translate cds to proteins (version.2.0.).

=head1 SYPNOSIS
  
cds_protein_translation.pl <input fasta file> [-r] [-p <non_iupac_perc>]

=head1 DESCRIPTION

This script get the sequences of a file and translate them to protein. 
If is active the -r option find lowercase letters (like a,t,c.g,n) and 
delete them before the translation.

Also will print a new cds file without the lowercase letters 

The output filename will be: $filename.protein.fasta.

Note: Sequences with high content in non iupac nucleotides (like W, R ...)
      give problems in the translation. For these cases is recomended use
      -p option with p = 15

=head2 I<tags:>

=over 

=item -r 

remove the lower case letters

=item -p

percentage of non-iupac nucleotides (different from ATCGN) allowed (100 by default)
      
=item -h 

print this help

=back

=head1 AUTHOR

 Aureliano Bombarely Gomez.
 (ab782@cornell.edu).

=head1 METHODS
 
cds_protein_translation.pl


=cut

use strict;
use Bio::Seq;
use Bio::SeqIO;
use Getopt::Std;

my $filename=shift(@ARGV);
if ($filename =~ m/-h/) {
	help()
}
unless (-s $filename) {
    die "Sorry, the file:$filename do not exists or has zero size. Please check it.\n";
}
my $output_filename = $filename.".protein.fasta";
my $output_filename2 = $filename.".cds_without_lowercase.fasta";

our ($opt_r, $opt_p);
getopts("rp:h");

if (!$opt_r && !$opt_p && !$filename) {
    print "There are n\'t any tags. Print help\n\n";
    help();
}

my $perc_noniupac_cutoff = $opt_p || 100;
my $count=`grep '^>' $filename | cut -d ' ' -f1 | wc -l`;
chomp($count);

open my $in, '<', $filename || die "I can not open the input file $filename.\n";

my $in  = Bio::SeqIO->new(	-file 	=> 	$filename,
                       		-format => 	'fasta'
			);

my $pep_ioobj=Bio::SeqIO->new( 	-file => ">$output_filename",
				-format => 'fasta',
			);

my $cds_ioobj;
if ($opt_r) {
    $cds_ioobj=Bio::SeqIO->new( -file => ">$output_filename2",
				-format => 'fasta',
			      );
}

my $n = 0;
my $low_up_case = 0;
my $non_iupac_count = 0;
my %noniupac = ();

print STDERR "\n";
while ( my $seq_obj = $in->next_seq() ) {
        $n++;

	my $id=$seq_obj->display_id;
        print STDERR "Processing sequence (id=$id) $n of $count sequences\t\t\t\r";
        my ($match_uppercase, $match_lowercase)=(0,0);
        
        my $seq=$seq_obj->seq;
	my $seq_length = length($seq);
	my $formated_seq = $seq;
	$formated_seq =~ s/[A|T|C|G|N]//g;
	my $formated_seq_length = length($formated_seq);

	my $perc_noniupac = ( $formated_seq_length / $seq_length ) * 100;

	if ($seq =~ m/[A|T|C|G]/g) {
	    $match_uppercase=1;
	}
	if ($seq =~ m/[a|t|c|g]/g) {
	    $match_lowercase=1;
	}
        
	if ($opt_r) {
        	$seq =~ s/[a|t|c|g|n]//g;
	} 
	else {
	    if ($match_lowercase == 1 && $match_uppercase == 1) {
		$low_up_case++;
	    }
	}
        
	my $new_seq_obj=Bio::Seq->new( 
		                       -id => $id,
		                       -seq => $seq, 
	                             );

	if ($perc_noniupac <= $perc_noniupac_cutoff) {

	    my $pep_obj=$new_seq_obj->translate;
	    my $pep=$pep_obj->seq;
	    $pep_ioobj->write_seq($pep_obj);
	    if ($opt_r) {
		$cds_ioobj->write_seq($new_seq_obj);
	    }
	}
	else {
	    $non_iupac_count++;
	    $noniupac{$id} = $perc_noniupac;
	}
}

if ($non_iupac_count > 0) {

    print STDERR "\n\nThere are $non_iupac_count sequences with non-iupac nt percentage > $perc_noniupac_cutoff.\n";
    print STDERR "\nDo you want print as STOUT the list of the non-iupac sequences? (yes/no) (default no) ?\n>";

    my $ans = <>;
    chomp($ans);

    print STDERR "\n\n";

    if ($ans =~ m/yes/i) {
	foreach my $key (sort keys %noniupac) {
	    print STDOUT "$key\t$noniupac{$key}\n";	    
	}
    }
}


print STDERR "\n\n\n";
if ($low_up_case > 0 && !$opt_r) {
    print STDERR "\n###############################   Attention!!!:  ###############################\n";
    print STDERR " There are $low_up_case sequences with lower caser and upper case letters     \n";
    print STDERR " The lowercase letters in sequences are used to notify that these nucleotides \n";
    print STDERR "  has been removed in the protein prediction (estscan).                        \n";
    print STDERR "                                 <=====0=====>                              \n";
    print STDERR " Perhaps you should use -r parameter to translate these cds.                  ";
    print STDERR "\n################################################################################\n";
}
print STDERR "\n--------------------------------------------------------------------------------\n";
print STDERR "Input_file: $filename.\n";
print STDERR "REPORT: Translate $n sequences.\n";
if ($opt_r) {
	print STDERR "Active delete lower case letter option before the translation.\n";
}
print STDERR "Output_file: $output_filename.";
print STDERR "\nSequences not translated, with non-iupac percentage > $perc_noniupac_cutoff ($non_iupac_count).";
print STDERR "\n--------------------------------------------------------------------------------\n\n";


=head2 help

  Usage: help()
  Desc: print help of this script
  Ret: none
  Args: none
  Side_Effects: exit of the script
  Example: if (!@ARGV) {
               help();
           }

=cut

sub help {
  print STDERR <<EOF;
  $0: 

    Description: 
      This script get the sequences of a file and translate them to protein. 
      If is active the -r option find lowercase letters (like a,t,c.g,n) delete 
      them before the translation. 
    
      The output filename will be: $filename.protein.fasta.
 
    Note: 
      Sequences with high content in non iupac nucleotides (like W, R ...)
      give problems in the translation. For these cases is recomended use
      -p option with p = 15

    Usage: 
	  cds_protein_translation.pl <input fasta file> [-r] [-p <non_iupac_perc>]
    
    Example:
      cds_protein_translation.pl /home/aure/ipomoea_batatas/ib_unigene_estscan.cds.fasta -r

    Flags:
      -r remove the lower case letters
      -p percentage of non-iupac nucleotides (different from ATCGN) allowed (100 by default)
      -h print this help

EOF
exit (1);
}
