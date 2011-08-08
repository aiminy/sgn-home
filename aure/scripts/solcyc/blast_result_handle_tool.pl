#!/usr/bin/perl

=head1 NAME

 blast_results_handle_tool.pl
 This script parse the blast results and produce different outputs (version.1.0.).

=cut

=head1 SYPNOSIS

 blast_result_handle_tool.pl [-h] -r <blast_result_file> [-f <filter_option> -v <filter_value>] [-F] [-d <defline_file>]
 [-s <sequence_file>] [-q <quality_file>] [-t <tab_file>]

=head2 I<Flags:>

=over


=item -r

B<blast_result_file>            blast result file in m8 format (mandatory)

=item -f

B<filter_option>                filter type, the options are: '%identity', 'align_length', 'e_value' or 'hit_score'

=item -v

B<filter_value>                 filter value for the filter options (used with filter options)

=item -F

B<filter_by_default>            filter by default filter the blast results and give the best hit for each subject

=item -d

B<defline_file>                 add the description of the deflines in the blast results or sequence or quality file.

=item -s

B<sequence_file>                sequence file in fasta format

=item -q

B<quality_file>                 quality file in fasta format

=item -t

B<tab_file>                     file in tabular file to annotate with the id in the first column

=item -h

B<help>                         print the help

=back

=cut

=head1 DESCRIPTION

 This script parse the blast result file in fasta format and give some options:

   1- Filter the blast result file using -f and -v (and specify the parameters) or -F and get the best hit match.

   2- Add a new column with the description from the defline file (-d <defline_file>)

   3- Add a description for the best hit match to the sequence or quality file (-d <defline_file> and -s or -q)

 Note about deflines: A defline file can be produced using the following commands:

   fastacmd -D 1 -d my_blast_db_formated | sed -n '/^>/{s/[[:space:]]+/\t/; p;}' | sort | gzip -c > defline.gz


=cut

=head1 AUTHORS

  Aureliano Bombarely Gomez.
  (ab782@cornell.edu).

=cut

=head1 METHODS

 blast_result_handle_tool.pl


=cut

use strict;
use warnings;

use File::Basename;
use Getopt::Std;
use Bio::SeqIO;
use Math::BigFloat;

our ($opt_r, $opt_f, $opt_v, $opt_F, $opt_d, $opt_s, $opt_q, $opt_t, $opt_h);
getopts("r:f:v:Fd:s:q:t:h");
if (!$opt_r && !$opt_f && !$opt_v && !$opt_F && !$opt_d && !$opt_s && !$opt_q && !$opt_t && !$opt_h) {
    print "There are n\'t any tags. Print help\n\n";
    help();
}

print STDERR "\nValidating the input parameters...\n";
validate_input();
print STDERR "\nParsing the blast report file -r $opt_r...\n";
my @blast_lines_href=parse_blast_file($opt_r);
my $output_file=$opt_r;

if ($opt_F || $opt_f && $opt_v) {
    print STDERR "\nFiltering the blast report file -r $opt_r according";
    if ($opt_F) {
	print STDERR " -F option (get the best hit_score match)...\n";
    } elsif ($opt_f && $opt_v) {
	print STDERR " -f $opt_f -v $opt_v filter options...\n";
    }
    my @filter_blast_parsed_href=filter_blast(\@blast_lines_href, $opt_f, $opt_v);
    @blast_lines_href=@filter_blast_parsed_href;
    $output_file .= '.filtered';
    if ($opt_f && $opt_v) {
	$output_file .= '_'.$opt_f.'_'.$opt_v;
    }
}
    
if ($opt_d) {
    print STDERR "\nParsing the defline file -d $opt_d...\n";
    my $descriptions_href=parse_defline_file($opt_d);
    print STDERR "\nAdding description to the blast result hashes...\n";
    my @blast_results_with_deflines_href=add_description_to_blast(\@blast_lines_href, $descriptions_href);
    $output_file .= '.annotated.tab';
    print STDERR "\nPrinting the blast result hashes with descriptions into a output file: $output_file...\n";
    print_blast_results($output_file, \@blast_results_with_deflines_href);
    if ($opt_s) {
	print STDERR "\nAdding and printing sequences with annotations...\n"; 
	add_description_to_sequence(\@blast_results_with_deflines_href, $opt_s, 'fasta');
    }
    if ($opt_q) {
	print STDERR "\nAdding and printing qscores with annotations...\n";
	add_description_to_sequence(\@blast_results_with_deflines_href, $opt_q, 'qual');
    }
    if ($opt_t) {
        print STDERR "\nProcessing and writing a new tab file with the descriptions...\n";
        add_description_to_tabfile(\@blast_results_with_deflines_href, $opt_t);
    }
} else {
    print STDERR "\nPrinting the blast result hashes into a output file: $output_file...\n";
    print_blast_results($output_file, \@blast_lines_href);
}


print STDERR "\n";

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
      This script parse the blast result file in fasta format and give some options:

       1- Filter the blast result file using -f and -v (and specify the parameters) or -F and get the best hit match.

       2- Add a new column with the description from the defline file (-d <defline_file>)

       3- Add a description for the best hit match to the sequence or quality file (-d <defline_file> and -s or -q)

     Note about deflines: A defline file can be produced using the following commands:

       fastacmd -D 1 -d my_blast_db_formated | sed -n '/^>/{s/[[:space:]]+/\t/; p;}' | sort | gzip -c > defline.gz

    Usage:
      blast_result_handle_tool.pl [-h] -r <blast_result_file> [-f <filter_option> -v <filter_value>] [-F] [-d <defline_file>]
 [-s <sequence_file>] [-q <quality_file>]
      
    Flags:
      -r   blast result file in m8 format (mandatory)
      -f   filter type, the options are: '%identity', 'align_length', 'e_value' or 'hit_score'
      -v   filter value for the filter options (used with filter options)
      -F   filter by default filter the blast results and give the best hit for each subject
      -d   add the description of the deflines in the blast results or sequence or quality file.
      -s   sequence file in fasta format
      -q   quality file in fasta format
      -t   tabular file with the id in the first column
      -h   this help

EOF
exit (1);
}

=head2 validate_input

  Usage: my ($out_basename,$dbh)=validate_input()
  Desc: check the input parameters
  Ret: $out_basename, a scalar that contains the basename for the output files, and $dbh, database conection object
  Args: none (use our variables)
  Side_Effects: die if it find something wrong
  Example: my ($out_basename,$dbh)=validate_input()

=cut

sub validate_input {
  
  if (!$opt_r) {
      die "Sorry, the -r <blast_results_file> was not supplied.\n";
  } else {
      unless (-s $opt_r) {
	  die "Sorry, the -r <blast_result_file> ($opt_r) does not exists or have zero size.\n";
      }
  }

  my $blast_resultfile_columns_n=count_columns($opt_r);
  if ($blast_resultfile_columns_n != 12) {
      die "Sorry, the -r $opt_r file have not the right number of columns (have $blast_resultfile_columns_n)\n";
  }
  
  if ($opt_f && !$opt_v) {
      die "Sorry, the -f <filter_type> must be used with -v <filter_value> parameter\n";
  } elsif ($opt_v && !$opt_f) {
      die "Sorry, the -v <filter_vlaue> must be used with -f <filter_type> parameter\n";
  } else {
      if ($opt_f) {
	  unless ($opt_f eq '%identity' or $opt_f eq 'align_length' or $opt_f eq 'e_value' or $opt_f eq 'hit_score' ) {
	      die "Sorry, -f <filter_type> only can have values:'%identity','align_length','e_value' or 'hit_score'\n";
	  }
      }
     
      if ($opt_v) { 
	  my $value=Math::BigFloat->new($opt_v);
	  if ($value->is_nan()) {
	      die "Sorry, -v <filter_value> must be an integer\n";
	  }
      }
  }
  if ($opt_F && $opt_f) {
      die "Sorry, the -F <filter_by_default> only can be used without -f <filter_type> or -v <filter_value> option\n";
  } elsif ($opt_F && $opt_v) {
      die "Sorry, the -F <filter_by_default> only can be used without -f <filter_type> or -v <filter_value> option\n";
  }
  if ($opt_d) {
      unless (-s $opt_d) {
	  die "Sorry, -d <defline_file> ($opt_d) does not exists or have zero size\n";
      }
  } else {
      if ($opt_s || $opt_q || $opt_t) {
	  print STDERR "Sorry, parameters -s <sequence_file>, -q <quality_file> and/or -t <tabular_file> ";
          die "only can be used with -d <defline_file> parameter\n";
      }
  }
  if ($opt_s) {
      unless (-s $opt_s) {
	  die "Sorry, -s <sequence_fasta_file> ($opt_s) does not exists or have zero size\n";
      }
  }
  if ($opt_q) {
      unless (-s $opt_q) {
	  die "Sorry, -q <quality_fasta_file> ($opt_q) does not exists or have zero size\n";
      }
  }
  if ($opt_t) {
      unless (-s $opt_t) {
	  die "Sorry, -t <tab_file> ($opt_t) does not exists or have zero size\n";
      }
  }
}


=head2 count_columns

  Usage: my $columns_number=count_columns($file);
  Desc: this subroutine counts the number of columns in a file and returns the number
  Ret: A scalar, the number of columns of the file
  Args: $file (the file)
  Side_Effects: none
  Example: my $columns_number=count_columns($file);

=cut

sub count_columns {
  my $filename=shift;
  my @columns;
  my ($line, $max_value)=(0,0);
  open my $input, '<', "$filename" or die "Sorry, I can not open the input file: $filename.\n";
      while (<$input>) {
         chomp($_);
         @columns = split(/\t/,$_);
         my $columns_number=scalar(@columns);
         if ($columns_number > $max_value) {
             $max_value=$columns_number;
         }
     }

  close $input;
  return $max_value;
}


=head2 parse_blast_file

  Usage: my @blast_lines_href=parse_blast_file($blast_file);
  Desc: parse the blast file into hash elements with the line as keys and the file element (example query_id) as value
  Ret: an array of blast_lines_href
  Args: $blast_file, blast result file name in m8 format
  Side_Effects: die if can not open the file
  Example: my @blast_lines_href=parse_blast_file($blast_file);

=cut 

sub parse_blast_file {
  my $blast_file=shift;

  my $total_lines=`cut -f1 $blast_file | wc -l`;
  chomp($total_lines);
  my (%query_id, %subject_id, %identity, %align_lenght, %mismatches, %gap_openings, %q_start, %q_end, %s_start, %s_end, 
      %e_value, %hit_score);

  open my $fh, '<', $blast_file || die "I cannot open the file:$blast_file\n";
  my $line=0;
  print STDERR "\n";
  while (<$fh>) {
      $line++;
      print STDERR "\tParsing line:$line of $total_lines lines from the file:$blast_file\t\t\r";
      chomp($_);
      my @data=split(/\t/, $_);
      $query_id{$line}=$data[0];
      $subject_id{$line}=$data[1];
      $identity{$line}=$data[2];
      $align_lenght{$line}=$data[3];
      $mismatches{$line}=$data[4];
      $gap_openings{$line}=$data[5];
      $q_start{$line}=$data[6];
      $q_end{$line}=$data[7];
      $s_start{$line}=$data[8];
      $s_end{$line}=$data[9];
      $e_value{$line}=$data[10];
      $hit_score{$line}=$data[11];
  }
  print STDERR "\n";
  close $fh;
  return (\%query_id, \%subject_id, \%identity, \%align_lenght, \%mismatches, \%gap_openings, \%q_start, \%q_end, 
          \%s_start, \%s_end, \%e_value, \%hit_score);

}

=head2 parse_defline_file

  Usage: my $descriptions_href=parse_defline_file($defline_file);
  Desc: parse the defline file and return a href with query_id as keys and description as values 
  Ret: hash reference with query_id as keys and description as values
  Args: $defline_file, filename
  Side_Effects: uncompress the file if it is compressed using gzip or bzip2. die if can not open the file.
  Example: my $descriptions_href=parse_defline_file($defline_file);

=cut

sub parse_defline_file {
  my $predefline_file=shift;
  my $defline_file=$predefline_file;

  ## decompress the file using the file extension.
  if ($predefline_file =~ m/\.gz$/) {
      $defline_file =~ s/\.gz$//i;
      print STDERR "The file $predefline_file is compressed using gzip.\n";
      print STDERR "Running gunzip -c $predefline_file > $defline_file\n";
      system "gunzip -c $predefline_file > $defline_file";
  } elsif ($predefline_file =~ m/\.bz2$/) {
      $defline_file =~ s/\.bz2$//i;
      print STDERR "The file $predefline_file is compressed using bzip2.\n";
      print STDERR "Running bunzip -c $predefline_file > $defline_file\n";
      system "bunzip -c $predefline_file > $defline_file";
  }

  ## there are different ways to parse a defline file, depends of the type, so the first thing it is see what kind
  ## of file it is.
  my $defline_type='unknown';
  my $first_line=`head -n 1 $defline_file`;
  chomp($first_line);
  my @head=split(/\s/, $first_line);
  if ($head[0] =~ m/>gi\|\d+\|\w+\|.+\|/) {
      $defline_type='genbank';
  } elsif ($head[0] =~ m/>lcl\|AT\w+\.\d+/i) {
      $defline_type='arabidopsis';
  } elsif ($head[0] =~ m/>gnl\|BL_ORD_ID\|\d+/) {
      $defline_type='swissprot';
  }
  print STDERR "The defline type is: $defline_type\n"; 

  open my $fh, '<', $defline_file || die "I can not open the file:$defline_file\n"; 
  my $total_lines=`cut -f1 $defline_file | wc -l`;
  chomp($total_lines);
  my $line=0;
  my %query_description;
  while (<$fh>) {
      $line++;
      print STDERR "\tParsing line $line of $total_lines of the file:$defline_file\t\t\r";
      chomp($_);
      my ($query_id, $description);

      ## * the nr genbank annotations have merge different description for different accessions that are the same sequence
      ## we are going to get only the first description, so we are going to split using '>' simbol and get the second
      ## array element (the first is nothing because the line begin with '>'. After we split using space and get the first
      ## array element as id (gi|...) and the rest of the array as description.
      ## * the arabidopsis query_id used in the blast result file is ATXXXXXXX.X but in the defline file the id appears as
      ## lcl|ATXXXXXXX.X so we need parse this too. 
      ## * for the swissprot the query_id is not the first accession word, it is the second, so the parse it is different
      ## too.
      ## * finally if there aren't any defline format this script take all the characters from '>' to the first space ' '
      ## as id and the rest of the line as a description   
  
      if ($defline_type eq 'genbank') {
	  my @breakline=split(/>/, $_);
	  my $first_description=$breakline[1];
	  my @parse_first_description=split(/ /, $first_description);
	  $query_id=shift(@parse_first_description);
	  $description=join(" ", @parse_first_description);
      } elsif ($defline_type eq 'arabidopsis') {
	  my @breakline=split(/ /, $_);
	  $query_id=shift(@breakline);
	  my $unused=shift(@breakline);
	  $query_id =~ s/>lcl\|//g;
	  $description=join(" ", @breakline);
      } elsif ($defline_type eq 'swissprot') {
	  my @breakline=split(/ /, $_);
	  my @unused=shift(@breakline);
	  $query_id=shift(@breakline);
	  $query_id =~ s/^>//;
	  $description=join(" ", @breakline);
      } else {
	  my @breakline=split(/ /, $_);
	  $query_id=shift(@breakline);
	  $query_id =~ s/^>//;
	  $description=join(" ", @breakline);
      }

      unless (exists $query_description{$query_id}) {
	  $query_description{$query_id}=$description;
      }
  }
  print STDERR "\n";
  close $fh;
  return \%query_description;
}

=head2 filter_blast

  Usage: my @filter_blast_parsed_href=filter_blast($blast_parsed_aref, $filter_type, $filter_value);
  Desc: filter the blast result hashes using filter type and filter value.
  Ret: An array of hash references with new line as keys and blast elements as values
  Args: $blast_parsed_aref, the array reference with the blast results parsed hash references, $filter_type, filter type
        parameter and $filter_value, filter value parameter
  Side_Effects: none
  Example: my @filter_blast_parsed_href=filter_blast($blast_parsed_aref, $filter_type, $filter_value);

=cut

sub filter_blast {
  my $blast_parsed_aref=shift;
  my $filter_type=shift;
  my $filter_value=shift;  

  my ($query_id_href, $subject_id_href, $identity_href, $align_length_href, $mismatches_href, $gap_openings_href, 
      $q_start_href, $q_end_href, $s_start_href, $s_end_href, $e_value_href, $hit_score_href)=@$blast_parsed_aref;
  my (%filter_query_id, %filter_subject_id, %filter_identity, %filter_align_length, %filter_mismatches, 
      %filter_gap_openings, %filter_q_start, %filter_q_end, %filter_s_start, %filter_s_end, %filter_e_value, 
      %filter_hit_score);
  my %query_id=%{$query_id_href};
  my %subject_id=%{$subject_id_href};
  my %identity=%{$identity_href};
  my %align_length=%{$align_length_href};
  my %mismatches=%{$mismatches_href};
  my %gap_openings=%{$gap_openings_href};
  my %q_start=%{$q_start_href};
  my %q_end=%{$q_end_href};
  my %s_start=%{$s_start_href};
  my %s_end=%{$s_end_href};
  my %e_value=%{$e_value_href};
  my %hit_score=%{$hit_score_href};

  my @lines=sort {$a <=> $b} keys %query_id;
  my $total_lines=scalar(@lines);
  my $new_line=0;
  my ($nr_query_id, $nr_hit_score)=('first',0);
  print STDERR "\n";
  foreach my $line (@lines) {
      print STDERR "\tFiltering line:$line of $total_lines\t\t\r";
      my $true_filter=0;
      my $query_id=$query_id{$line};
      my $subject_id=$subject_id{$line};
      my $identity=$identity{$line};
      my $align_length=$align_length{$line};
      my $mismatches=$mismatches{$line};
      my $gap_openings=$gap_openings{$line};
      my $q_start=$q_start{$line};
      my $q_end=$q_end{$line};
      my $s_start=$s_start{$line};
      my $s_end=$s_end{$line};
      my $e_value=$e_value{$line};
      my $hit_score=$hit_score{$line};
      
      ## depending of the filter type this script use a concrete hash value. If this hash value is >= than the filter 
      ## value, switch the true_filter value to 1 and add new hash values to filter hashes.
 
      if ($filter_type) {
	  if ($filter_type eq '%identity') {
	      if ($identity >= $filter_value) {
		  $new_line++;
		  $true_filter=1;
	      }    
	  } elsif ($filter_type eq 'align_length') {
	      if ($align_length >= $filter_value) {
		  $new_line++;
		  $true_filter=1;
	      }
	  } elsif ($filter_type eq 'e_value') {
	      my $filter_value_obj=Math::BigFloat->new($filter_value);
	      my $filter_value_as_common_not=$filter_value_obj->bstr();
	      if ($e_value <= $filter_value_as_common_not) {
		  $new_line++;
		  $true_filter=1;
	      }
	  } elsif ($filter_type eq 'hit_score') {
	      if ($hit_score >= $filter_value) {
		  $new_line++;
		  $true_filter=1;
	      }
	  }
      } else {

      ## if exists -F parameter, this script takes the best hit value for each query_id. To do it, switch true_filter 
      ## value to 1, copy the query_id and hit_score to nr-variables and add new hash values. If the new line with the
      ## same query_id has hit_score higher than nr_hit_score switch another time true_filter variable to 1 and overwrite
      ## the hash values for the same new_line

	  if ($opt_F) {
	      if ($nr_query_id ne $query_id) {
		  $nr_query_id=$query_id;
		  $nr_hit_score=$hit_score;
		  $true_filter=1;
		  $new_line++;
	      } else {
		  if ($nr_hit_score < $hit_score) {
		      $nr_hit_score=$hit_score;
		      $true_filter=1;
		  }
	      }
	  }
      }
      if ($true_filter == 1) {
	  $filter_query_id{$new_line}=$query_id;
	  $filter_subject_id{$new_line}=$subject_id;
	  $filter_identity{$new_line}=$identity;
	  $filter_align_length{$new_line}=$align_length;
	  $filter_mismatches{$new_line}=$mismatches;
	  $filter_gap_openings{$new_line}=$gap_openings;
	  $filter_q_start{$new_line}=$q_start;
	  $filter_q_end{$new_line}=$q_end;
	  $filter_s_start{$new_line}=$s_start;
	  $filter_s_end{$new_line}=$s_end;
	  $filter_e_value{$new_line}=$e_value;
	  $filter_hit_score{$new_line}=$hit_score;
      }
      
  }
  print STDERR "\n";
  return  (\%filter_query_id, \%filter_subject_id, \%filter_identity, \%filter_align_length, \%filter_mismatches, 
           \%filter_gap_openings, \%filter_q_start, \%filter_q_end, \%filter_s_start, \%filter_s_end, \%filter_e_value, 
           \%filter_hit_score);
}

=head2 add_description_to_blast

  Usage: my @blast_result_with_deflines_aref=add_description_to_blast($blast_parsed_aref, $description_href);
  Desc: add a new hash reference with the annotations to the blast results file.
  Ret: An array reference with the blast results as hash references, incluided a new hash with the references
  Args: $blast_parsed_aref, blast result array reference with hash references as elements, and $description_href, a hash
        reference with line as keys and descriptions (deflines) as values
  Side_Effects: print a message if the subject_id is not into the defline hash
  Example: my @blast_result_with_deflines_aref=add_description_to_blast($blast_parsed_aref, $description_href);

=cut

sub add_description_to_blast {
  my $blast_parsed_aref=shift;
  my $description_href=shift;
  my %description=%{$description_href};

  my ($query_id_href, $subject_id_href, $identity_href, $align_lenght_href, $mismatches_href, $gap_openings_href, 
      $q_start_href, $q_end_href, $s_start_href, $s_end_href, $e_value_href, $hit_score_href)=@$blast_parsed_aref;
 
  my %query_id=%{$query_id_href};
  my %subject_id=%{$subject_id_href};

  my @lines=sort {$a <=> $b} keys %query_id;
  my $total_lines=scalar(@lines);
  print STDERR "\n";
  my %subject_description;
  foreach my $line (@lines) {
      print STDERR "\tAdding description line to line:$line of $total_lines\t\t\r";
      my $subject_id=$subject_id{$line};
      my $description = $description{$subject_id} || print STDERR "The subject_id:$subject_id have not any defline\n";
      $subject_description{$line}=$description || '';
  }
  print STDERR "\n";
  return ($query_id_href, $subject_id_href, $identity_href, $align_lenght_href, $mismatches_href, $gap_openings_href, 
      $q_start_href, $q_end_href, $s_start_href, $s_end_href, $e_value_href, $hit_score_href, \%subject_description);

}

=head2 description_constructor

  Usage: my $query_annotated_href=description_constructor($blast_results_wdeflines_aref);
  Desc: process the blast results hashes and return a single hash reference with the query_id and the description
  Ret: A hash reference with query_id as keys and descriptions as value
  Args: $blast_results_wdeflines_aref, array reference of blast results hash references
  Side_Effects: none
  Example: my $query_annotated_href=description_constructor($blast_results_wdeflines_aref);

=cut

sub description_constructor {
  my $blast_result_wdeflines_aref=shift;

  my ($query_id_href,$subject_id_href,$identity_href,$align_lenght_href,$mismatches_href,$gap_openings_href,$q_start_href,
      $q_end_href,$s_start_href,$s_end_href,$e_value_href,$hit_score_href,$defline_href)=@{$blast_result_wdeflines_aref};
    
  my %query_id=%{$query_id_href};
  my %subject_id=%{$subject_id_href};
  my %e_value=%{$e_value_href};
  my %defline=%{$defline_href};
  my @lines=sort {$a <=> $b} keys %query_id;
  my %query_annotated;

  foreach my $line (@lines) {
      my $query_id=$query_id{$line};
      my $defline_type;
      my $subject_id=$subject_id{$line};
      if ($subject_id =~ m/^gi\|/) {
	  $defline_type='(*GB)';
      } elsif ($subject_id =~ m/^AT\dG\d+/i) {
	  $defline_type='(*ATH)';
      } elsif ($subject_id =~ m/^sp\|/) {
	  $defline_type='(*SWP)';
      } else {
	  $defline_type='(*)';
      }
      my $e_value=$e_value{$line};
      my $defline=$defline{$line};
      unless (exists $query_annotated{$query_id}) {
	  $query_annotated{$query_id}=sprintf "$defline_type $subject_id (e_value=$e_value) $defline;";  
      }
  }
  return \%query_annotated;
}

=head2 print_blast_results

  Usage: print_blast_results($output_file, $blast_result_aref);
  Desc: print in the output file the results for the blast in tab format
  Ret: none
  Args: $output_file, output_file name and $blast_result_aref, array reference with the blast results hash references
  Side_Effects: none
  Example:  print_blast_results($output_file, $blast_result_aref);

=cut  

sub print_blast_results {
  my $output_file=shift;
  my $blast_result_aref=shift;
  my @blast_results_href=@{$blast_result_aref};

  open my $fh, '>', $output_file || die "I can not open the file:$output_file\n";
  my ($query_id_href, $subject_id_href, $identity_href, $align_length_href, $mismatches_href, $gap_openings_href, 
       $q_start_href, $q_end_href, $s_start_href, $s_end_href, $e_value_href, $hit_score_href, $subject_descrip_href)=
          @blast_results_href;
  my %query_id=%{$query_id_href};
  my %subject_id=%{$subject_id_href};
  my %identity=%{$identity_href};
  my %align_length=%{$align_length_href};
  my %mismatches=%{$mismatches_href};
  my %gap_openings=%{$gap_openings_href};
  my %q_start=%{$q_start_href};
  my %q_end=%{$q_end_href};
  my %s_start=%{$s_start_href};
  my %s_end=%{$s_end_href};
  my %e_value=%{$e_value_href};
  my %hit_score=%{$hit_score_href};
  my %subject_descrip;
  if ($subject_descrip_href) {
      %subject_descrip=%{$subject_descrip_href};
  }

  my @lines=sort {$a <=> $b} keys %query_id;
  my $total_lines=scalar(@lines);
  foreach my $line (@lines) {
      print STDERR "\tPrinting line:$line of $total_lines into the output file:$output_file\t\t\r";
      print $fh "$query_id{$line}\t$subject_id{$line}\t$identity{$line}\t$align_length{$line}\t$mismatches{$line}\t";
      print $fh "$gap_openings{$line}\t$q_start{$line}\t$q_end{$line}\t$s_start{$line}\t$s_end{$line}\t$e_value{$line}\t";
      print $fh "$hit_score{$line}";
      if ($subject_descrip_href) {
	  print $fh "\t$subject_descrip{$line}\n";
      } else {
	  print $fh "\n";
      }
  }
  print STDERR "\n";
}



=head2 add_description_to_sequence

  Usage: add_description_to_sequence($blast_result_wdeflines_aref, $sequence_file, $format);
  Desc: this subroutine add a description based in the blast result and the defline to sequences
  Ret: none
  Args: $blast_result_wdeflines_aref, an array reference with all the blast result as hash references elements, 
        $sequence_file, the sequence (or quality file) and $format ('fasta' or 'qual') 
  Side_Effects: create a new file (sequence.annotated.fasta file) with the sequences annotated
  Example: add_description_to_sequence($blast_result_wdeflines_aref, $sequence_file, $format);

=cut

sub add_description_to_sequence {
  my $blast_result_wdeflines_aref=shift;
  my $sequence_file=shift;
  my $format=shift;
  unless ($format eq 'fasta' or $format eq 'qual') {
      die "Only formats 'fasta' or 'qual' are permited in the add_description_to_sequence subroutine\n";
  }

  my %query_annotated=%{description_constructor($blast_result_wdeflines_aref)};  

  my $annotated_sequence_file=$sequence_file;
  $annotated_sequence_file =~ s/\.qual$//;
  $annotated_sequence_file =~ s/\.fasta$//;
  $annotated_sequence_file =~ s/\.fna$//;
  $annotated_sequence_file =~ s/\.seq$//;
  $annotated_sequence_file .= '.'.$format.'_annotated.fasta';
  my $input_seq = Bio::SeqIO->new( -file   =>      "$sequence_file",
         			   -format =>      $format
			         );

  my $output_seq = Bio::SeqIO->new( -file   => ">$annotated_sequence_file",
				    -format => $format
				 );  
  my $new_seq_obj;
  while ( my $seq_obj = $input_seq->next_seq() ) {
     my $id=$seq_obj->display_id();
     my $description;
     unless ($format eq 'qual') {
	 $description=$seq_obj->description();
     } else {
	 $description=$seq_obj->desc();
     }
     if (exists $query_annotated{$id}) {
	 $description .= '; ';
	 $description .= $query_annotated{$id};
     } else {
	 print STDERR "\nThe id:$id have not any description in the blast file.\n";
     }

     if ($format eq 'fasta') {
          my $seq=$seq_obj->seq();
	  $new_seq_obj=Bio::Seq->new( -id          => $id,
				      -description => $description, 
				      -seq         => $seq 
				      );
	  $output_seq->write_seq($new_seq_obj);
      } elsif ($format eq 'qual') {
	  my $qual_aref=$seq_obj->qual();
	  my $header;
	  if (exists $query_annotated{$id}) {
	      $header=$id.' '.$description;
	  } else {
	      $header=$id;
	  }
	  ## I don't know why don't work -id => $id, -desc => description when you use write_seq... so, I have
          ## incluided the description in the id. It isn't elegant, but works...
	  $new_seq_obj=Bio::Seq::PrimaryQual->new( -id          => $header,
					           -qual        => $qual_aref
					      );
	  
	  $output_seq->write_seq($new_seq_obj);
      } 
 }
}

=head2 add_description_to_tabfile

  Usage: add_description_to_tabfile($blast_result_wdeflines_aref, $tabular_file);
  Desc: add a new column to the tabular file with the description
  Ret: none
  Args: $blast_result_wdeflines_aref, an array reference with the blast results hashes references
  Side_Effects: create a new file with the annotations
  Example: add_description_to_tabfile($blast_result_wdeflines_aref, $tabular_file);

=cut

sub add_description_to_tabfile {
  my $blast_result_wdeflines_aref=shift;
  my $tabular_file=shift;  
  my $l=0;
  my $total_l=`cut -f1 $tabular_file | wc -l`;
  chomp($total_l);
  my %query_annotated=%{description_constructor($blast_result_wdeflines_aref)};
  
  my $output_file=$tabular_file;
  $output_file =~ s/\.tab$//;
  $output_file =~ s/\.txt$//;
  $output_file .= '.annotated.tab';
  open my $fh_out, '>', $output_file || die "I can not open the file:$output_file\n";
  open my $fh_in, '<', $tabular_file || die "I can not open the file:$tabular_file\n";
  
  print STDERR "\n";

  while (<$fh_in>) {
      $l++;
      chomp($_);
      my $line=$_;
      if ($total_l) {
	  print STDERR "\tProcessing and writing annotations for -t <$opt_t> | line:$l of $total_l\t\r";
      } else {
          print STDERR "\tProcessing and writing annotations for -t <$opt_t> | line:$l\t\r";
      }
      my @var=split(/\t/, $_);
      my $query_id=$var[0];
      if (exists $query_annotated{$query_id}) {
	  print $fh_out "$line\t$query_annotated{$query_id}\n";
      } else {
	  print $fh_out "$line\t\n";
	  print STDERR "\n\tthe id:$query_id have not any description (line:$l)\n";
      }
  }
  print STDERR "\n";
  close $fh_in;
}
