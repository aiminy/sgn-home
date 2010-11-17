
package PhyGeCluster;

use strict;
use warnings;
use autodie;

use Carp qw| croak cluck |;
use Math::BigFloat;

use Bio::Seq::Meta;
use Bio::LocatableSeq;
use Bio::SeqIO;
use Bio::SearchIO;
use Bio::Cluster::SequenceFamily;

use Bio::Tools::Run::Alignment::Clustalw;
use Bio::Tools::Run::Alignment::Kalign;
use Bio::Tools::Run::Alignment::MAFFT;
use Bio::Tools::Run::Alignment::Muscle;
use Bio::Tools::Run::Alignment::TCoffee;
use Bio::Tools::Run::StandAloneBlast;

use Bio::AlignIO;
use Bio::Align::DNAStatistics;

use Bio::Tools::Run::Phylo::Phylip::SeqBoot;

use Bio::Matrix::IO;
use Bio::Matrix::Generic;

###############
### PERLDOC ###
###############

=head1 NAME

PhyGeCluster.pm
A class to cluster sequences and analyze clusters.

=cut

our $VERSION = '0.01';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

  use PhyGeCluster;

  ## To get each cluster from a blast file

  my $phygecluster = PhyGeCluster->new({
                                   blastfile     => $filename1,
                                   blastformat   => $format, 
                                   sequencefile  => $filename2,
                                   strainfile    => $filename3,   
                                   clustervalues => { $variable => $condition},
                                   rootname      => $name,
                                   });

  ## Accessors

  $phygecluster->set_clusters(\%clusters);
  my $clusters_href = $phygecluster->get_clusters();

  $phygecluster->set_strains(\%clusters);
  my $strains_href = $phygecluster->get_strains();

  $phygecluster->set_distances(\%clusters);
  my $distances_href = $phygecluster->get_distances();

  $phygecluster->set_bootstrapping(\%clusters);
  my $distances_href = $phygecluster->get_bootstrapping();

  ## Load new sequences into the object

  $phygecluster->load_seqfile($seqfile);

  ## Load new strains

  $phygecluster->load_strainfile($strainfile); 

  ## Calculate the alignment

  $phygecluster->run_alignment();

  ## Calculate distances

  $phygecluster->run_distances();

  ## Create bootstraing of the alignments

  $phygecluster->run_bootstrapping({ datatype => 'Sequences', quiet => 'yes' });

  ## Select by cluster sizes

  my %cluster_sizes = phygecluster->cluster_sizes();
  my %singlets = phygecluster->cluster_sizes(1,1);

  ## Prune by alignments features

  $phygecluster->prune_by_align({num_sequences => ['<',4],length => ['<',100]});

  ## Prune by strains composition

  $phygecluster->prune_by_strains({ composition => {'A' => 1,'B' => 1,'C' => 1},
                                    min_distance => [['A','B'],['A','C']] });


  ## Slice by overlapping region

=head1 DESCRIPTION

 Object to parse and cluster sequences based in blast results


=head1 AUTHOR

Aureliano Bombarely <ab782@cornell.edu>


=head1 CLASS METHODS

The following class methods are implemented:

=cut 



############################
### GENERAL CONSTRUCTORS ###
############################

=head2 constructor new

  Usage: my $phygecluster = PhyGeCluster->new($arguments_href);

  Desc: Create a phygecluster object
        Use fastblast_parser argument to use the non-bioperl
        blast parser (faster)

  Ret: a PhyGeCluster.pm object

  Args: A hash reference with the following keys: 
         + blastfile, $filename a scalar.
         + blastformat, $fileformat, a scalar
         + fastblast_parser, 1, a scalar
         + clustervalues, a hash reference argument (see parse_blastfile())
         + rootname, $name a scalar. 
         + sequencefile, $filename, a scalar 
         + strainfile, $filename, a scalar
         + run_alignments, a hash reference argument (see run_alignments())  
         + run_distances, a hash reference argument (see run_distances())
         + run_bootstrapping, a hash reference arg. (see run_bootstrapping())

  Side_Effects: Die if the argument used is not a hash or there are argument
                incompatibility (such as use fastblast_parser without blastfile)
                
                Default values when blastfile argument is used:
                { blastformat   => 'blasttable'.
                  clustervalues => { "percent_identity" => ['>', 90], 
                                     "hsp_length"       => ['>', 60], },
                  rootname      => 'cluster',
                }

  Example: my $phygecluster = PhyGeCluster->new(%arguments);

=cut

sub new {
    my $class = shift;
    my $args_href = shift;

    my $self = bless( {}, $class );                         
    
    my %clusters = ();
    my %strains = ();
    my %dist = ();
    my %bootstrap = ();

    ## Check argument compatibility

    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARGUMENT ERROR: $args_href used for new() is not HASH REF.");
	}
    }

    my $err = "ARGUMENT INCOMPATIBILITY for new() function: ";
    unless(defined $args_href->{'blastfile'}) {

	if (defined $args_href->{'fastblast_parser'}) {
	    $err .= "fastblast_parser arg. can not be used without blastfile.";
	    croak($err);	    
	}
	unless(defined $args_href->{'acefile'}) {
	    if (defined $args_href->{'strainfile'}) {
		$err .= "strainfile arg. can not be used without blastfile";
		$err .= " or acefile argument.";
		croak($err);	    
	    }
	}
	if (defined $args_href->{'sequencefile'}) {
	    $err .= "sequencefile arg. can not be used without blastfile arg.";
	    croak($err);	    
	}
    }
    else {
	if (defined $args_href->{'acefile'}) {
	    $err .= "acefile arg. can not be used with blastfile arg.";
	    croak($err);
	}
	unless (defined $args_href->{'sequencefile'})  {
	    if (defined $args_href->{'run_alignments'}) {
		$err .= "run_alignments arg. can not be used without ";
		$err .= "sequencefile arg.";
		croak($err);
	    }
	}
	else {
	    unless (defined $args_href->{'run_alignments'})  {
		if (defined $args_href->{'run_distances'}) {
		    $err .= "run_distances arg. can not be used without ";
		    $err .= "run_alignments arg.";
		    croak($err);
		}
		if (defined $args_href->{'run_bootstrapping'}) {
		    $err .= "run_bootstrapping arg. can not be used without ";
		    $err .= "run_alignments arg.";
		    croak($err);
		}
	    }
	}
    }

    if (defined $args_href->{'blastfile'}) {

	## Get the cluster information from blast file
	
	if (defined $args_href->{'fastblast_parser'}) {
	    %clusters = fastparse_blastfile($args_href);
	}
	else {
	    %clusters = parse_blastfile($args_href);
	}
    }	

    if (defined $args_href->{'acefile'}) {
	
	%clusters = parse_acefile($args_href);	
    }	

    $self->set_clusters(\%clusters);

    ## Parse the seqfile if exists

    if (defined $args_href->{'sequencefile'}) {
	$self->load_seqfile($args_href);	
    }

    ## Parse the strain file if exists

    if (defined $args_href->{'strainfile'}) {
	%strains = parse_strainfile($args_href);
    }

    $self->set_strains(\%strains);

    ## This will use the run_alignment and run_distance function
    ## only if the sequencefile argument was detailed (it was checked in the
    ## begining of the function). Also it will run bootstrapping if it is
    ## defined the argument

    if (defined $args_href->{'run_alignments'}) {
	    
	$self->run_alignments($args_href->{'run_alignments'});
		
	if (defined $args_href->{'run_distances'}) {

	    %dist = $self->run_distances($args_href->{'run_distances'});
	}

	my $bootsargs = $args_href->{'run_bootstrapping'};

	if (defined $bootsargs) {
	    
	    %bootstrap = $self->run_bootstrapping($bootsargs);
	}
    }

    $self->set_distances(\%dist);
    $self->set_bootstrapping(\%bootstrap);


    return $self;
}

=head2 constructor clone

  Usage: my $new_phygecluster = $old_phygecluster->clone();

  Desc: Create a new phygecluster object using a old one

  Ret: a PhyGeCluster.pm object

  Args: None

  Side_Effects: None

  Example: my $new_phygecluster = $old_phygecluster->clone();

=cut

sub clone {
    my $self = shift;

    ## Create an empty object:

    my $new_phygecluster = __PACKAGE__->new();

    ## Get the data from the old object

    my %clusters = %{$self->get_clusters()};
    my %strains = %{$self->get_strains()};
    my %distances = %{$self->get_distances()};
    my %bootstrap = %{$self->get_bootstrapping()};
    
    ## Clone also the Bio::Cluster::SequenceFamily, Bio::SimpleAlign.
    ## It will have the same Bio::Seq objects

    my %new_clusters = ();
    foreach my $cluster_id (keys %clusters) {
	my $old_seqfam = $clusters{$cluster_id};
	my @members = $old_seqfam->get_members();
	my $old_align = $old_seqfam->alignment();

	my $new_align = '';
	if (defined $old_align) {
	   
	    $new_align = $old_align->select(1, $old_align->num_sequences());

	    ## Select does not copy metadata, so it will transfer manually
	    my @transfers = ('description', 'score', 'percentage_identity', 
			     'source');

	    foreach my $transf_var (@transfers) {
		if (defined $old_align->$transf_var) {
		    $new_align->$transf_var($old_align->$transf_var());
		}
	    }
	}

	my $new_seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $cluster_id,
	    -members   => \@members,
	    );
	$new_seqfam->alignment($new_align);
	$new_clusters{$cluster_id} = $new_seqfam;
    }
    
    ## %strains has not internal object so it will clone this hash
    ## %distance matrix will not be modify (usually it could rerun the
    ## distances using run_distances)

    ## Set the old dat into the new object

    $new_phygecluster->set_clusters(\%new_clusters);
    $new_phygecluster->set_strains(\%strains);
    $new_phygecluster->set_distances(\%distances);
    $new_phygecluster->set_bootstrapping(\%bootstrap);

    return $new_phygecluster;
}




#################
### ACCESSORS ###
#################

=head2 get_clusters

  Usage: my $clusters_href = $phygecluster->get_clusters();

  Desc: Get a cluster data from PhyGeCluster object

  Ret: A hash refence with key=clustername and 
       value=Bio::Cluster::SequenceFamily object
 
  Args: None
 
  Side_Effects: None
 
  Example: my $clusters_href = $phygecluster->get_clusters();

=cut

sub get_clusters {
  my $self = shift;

  return $self->{clusters};
}


=head2 set_clusters

  Usage: $phygecluster->set_clusters(\%clusters);

  Desc: Set a cluster data from PhyGeCluster object

  Ret: None
 
  Args: A hash with key=clustername and value=Bio::Cluster::SequenceFamily
        object
 
  Side_Effects: Die if the argument is not a hash reference
                or if the values for the hash are not 
                Bio::Cluster::SequenceFamily objects
 
  Example: $phygecluster->set_clusters(\%clusters);

=cut

sub set_clusters {
  my $self = shift;
  my $clusters_href = shift;

  if (defined $clusters_href) {
	if (ref($clusters_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $clusters_href is not a hash reference.\n");
	}
	else {
	    
            ## Check the objects

	    foreach my $cluster_name (keys %{$clusters_href}) {
		my $cluster = $clusters_href->{$cluster_name};
		if (ref($cluster) ne 'Bio::Cluster::SequenceFamily') {
		    croak("ARGUMENT ERROR: value for cluster=$cluster_name IS
                           NOT a Bio::Cluster::SequenceFamily object.\n");
		}
	    }

	    ## If it has survive to the checking it will set the object
	    
	    $self->{clusters} = $clusters_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_clusters function\n");
  }
}


=head2 add_cluster

  Usage: $phygecluster->add_cluster($cluster_name, $member_aref);

  Desc: Add a new cluster to the PhyGeCluster object

  Ret: None
 
  Args: $cluster_name, a scalar
        $member_aref, an array reference with member as Bio::Seq objects
 
  Side_Effects: Die if the arguments are wrong or undef
 
  Example: $phygecluster->add_cluster('cluster_1', ['seq1', 'seq2']);

=cut

sub add_cluster {
  my $self = shift;
  my $cluster_name = shift ||
      croak("ARG. ERROR: No argument was supplied to add_cluster function.\n");
  my $member_aref = shift ||
      croak("ARG. ERROR: None member array ref. was added to add_cluster.\n");

  unless (ref($member_aref) eq 'ARRAY') {
      croak("ARG. ERROR: member array ref. argument is not an ARRAY REF.\n");
  }

  ## Check the members

  foreach my $memberseq (@{$member_aref}) {
      unless (ref($memberseq) =~ m/Bio::Seq/) {
	  croak("ARG. ERROR: member=$memberseq used for add_cluster is not an 
                 Bio::Seq object.\n");
      }
  }

  ## First, create the cluster object

  my $new_cluster = Bio::Cluster::SequenceFamily->new( 
      -family_id => $cluster_name,
      -members   => $member_aref,
      );

  ## Second get the clusters and add a new one
  
  my $clusters_href = $self->get_clusters();
  $clusters_href->{$cluster_name} = $new_cluster;
}


=head2 remove_cluster

  Usage: my $rm_cluster = $phygecluster->remove_cluster($cluster_name);

  Desc: Remove a new cluster to the PhyGeCluster object

  Ret: The value of the cluster removed (a Bio::Cluster::SequenceFamily object)
 
  Args: $cluster_name, a scalar
 
  Side_Effects: Die if the arguments are wrong or undef
 
  Example: my $rm_cluster = $phygecluster->remove_cluster('cluster_1');

=cut

sub remove_cluster {
  my $self = shift;
  my $cluster_name = shift ||
      croak("ARG. ERROR: No argument was supplied to remove_cluster().\n");
  
  my $clusters_href = $self->get_clusters();
  my $value = delete($clusters_href->{$cluster_name});
  return $value;
}

=head2 find_cluster

  Usage: my $cluster = $phygecluster->find_cluster($member_id);

  Desc: Find a cluster object by member_id

  Ret: A Bio::Cluster::SequenceFamily object
 
  Args: $member_id, an scalar
 
  Side_Effects: return undef if the member does not exist
 
  Example: my $cluster = $phygecluster->find_cluster('seq_id1');

=cut

sub find_cluster {
  my $self = shift;
  my $member_id = shift;
  
  my $cluster_found;
  my $clusters_href = $self->get_clusters();
  foreach my $cluster_name (keys %{$clusters_href}) {
      my $cluster = $clusters_href->{$cluster_name};
      
      foreach my $member ($cluster->get_members()){
	  if ($member->display_id eq $member_id) {
	      $cluster_found = $cluster;
	  }
      }
  }

  return $cluster_found;
}

=head2 get_strains

  Usage: my $strains_href = $phygecluster->get_strains();

  Desc: Get a strain data from PhyGeCluster object

  Ret: A hash refence with key=member_id and value=strain
 
  Args: None
 
  Side_Effects: None
 
  Example: my $strains_href = $phygecluster->get_strains();

=cut

sub get_strains {
  my $self = shift;

  return $self->{strains};
}


=head2 set_strains

  Usage: $phygecluster->set_strains(\%strains);

  Desc: Set a strain data from PhyGeCluster object

  Ret: None
 
  Args: A hash with key=member_id and value=strain
 
  Side_Effects: Die if the argument is not a hash refence
 
  Example: $phygecluster->set_strains(\%strains);

=cut

sub set_strains {
  my $self = shift;
  my $strains_href = shift;

  if (defined $strains_href) {
	if (ref($strains_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $strains_href is not a hash reference.\n");
	}
	else {	    
	    $self->{strains} = $strains_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_strains function\n");
  }
}

=head2 get_distances

  Usage: my $distances_href = $phygecluster->get_distances();

  Desc: Get distance data from PhyGeCluster object

  Ret: A hash refence with key=member_id and 
       value=Bio::Matrix::PhylipDist object
 
  Args: None
 
  Side_Effects: None
 
  Example: my $distances_href = $phygecluster->get_distances();

=cut

sub get_distances {
  my $self = shift;

  return $self->{distances};
}


=head2 set_distances

  Usage: $phygecluster->set_distances(\%distances);

  Desc: Set a distance data from PhyGeCluster object

  Ret: None
 
  Args: A hash reference with key=member_id and 
        value=Bio::Matrix::PhylipDist object
 
  Side_Effects: Die if the argument is not a hash reference
 
  Example: $phygecluster->set_distances(\%distances);

=cut

sub set_distances {
  my $self = shift;
  my $distances_href = shift;

  if (defined $distances_href) {
	if (ref($distances_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $distances_href is not a hash reference.\n");
	}
	else {	    
	    $self->{distances} = $distances_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_distances function");
  }
}


=head2 get_bootstrapping

  Usage: my $bootstrapping_href = $phygecluster->get_bootstrapping();

  Desc: Get distance data from PhyGeCluster object

  Ret: A hash refence with key=cluster_id and 
       value=array reference of Bio::SimpleAlign objects (bootstrapping)
 
  Args: None
 
  Side_Effects: None
 
  Example: my $bootstrapping_href = $phygecluster->get_bootstrapping();

=cut

sub get_bootstrapping {
  my $self = shift;

  return $self->{bootstrapping};
}


=head2 set_bootstrapping

  Usage: $phygecluster->set_bootstrapping(\%bootstrap);

  Desc: Set bootstrapping data for a PhyGeCluster object.

  Ret: None
 
  Args: A hash reference with key=cluster_id and 
        value=array reference of Bio::SimpleAlign objects
 
  Side_Effects: Die if the argument is not a hash reference, if the values for
                this hash reference are not array reference and if the members
                of these arrays references are not Bio::SimpleAlign objects
 
  Example: $phygecluster->set_bootstrapping(\%bootstrap);

=cut

sub set_bootstrapping {
  my $self = shift;
  my $bootstrap_href = shift;

  if (defined $bootstrap_href) {
	if (ref($bootstrap_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $bootstrap_href is not a hash reference.\n");
	}
	else {
	    foreach my $cl_id (keys %{$bootstrap_href}) {
		unless (ref($bootstrap_href->{$cl_id}) eq 'ARRAY') {
		    my $err = "VAL. ERROR: value for $cl_id is not an array ";
		    $err .= "reference for set_bootstrapping() function.";
		    croak($err);
		}
		else {
		    my @aligns = @{$bootstrap_href->{$cl_id}};
		    foreach my $align (@aligns) {
			unless (ref($align) eq 'Bio::SimpleAlign') {
			    my $err1 = "VAL. ERROR: $align for $cl_id in ";
			    $err1 .= "set_bootstrapping function is not a ";
			    $err1 .= "Bio::SimpleAlign object.";
			    croak($err1);
			}
		    }
		}
	    }
	    $self->{bootstrapping} = $bootstrap_href;
	}
  }
  else {
      croak("ARGUMENT ERROR: No argument was used for set_boostrapping funct.");
  }
}



###################################
## OBJECT DATA LOADING FUNCTIONS ##
###################################

=head2 load_seqfile

  Usage: $phygecluster->load_seqfile($arguments_href);

  Desc: Parse the seqquence file using parse_seqfile function and
        load the results into the PhyGeCluster object

  Ret: None

  Args: A hash reference with the following key: sequencefile

  Side_Effects: Die if the argument used is not a hash or if none 
                sequencefile is detailed.
                Ignore the sequences that are not into the 
                Bio::Cluster::SequenceFamily object

  Example: $phygecluster->load_seqfile($arguments_href);

=cut

sub load_seqfile {
    my $self = shift;
    my $args_href = shift;
    
    if (defined $args_href) {
	if (ref($args_href) ne 'HASH') {
	    croak("ARG. ERROR: $args_href is not a hash reference.\n");
	}
	unless (defined $args_href->{'sequencefile'}) {
	    croak("ARG. ERROR: 'sequencefile' is not defined for $args_href\n");
	}
	else {
	    ## First, get the sequences.

	    my %seqs = parse_seqfile->($args_href);

	    ## Get the clusters and the different members

	    my %clusters = %{$self->get_clusters()};
	    foreach my $cluster_id (keys %clusters) {
		my $seqcluster_obj = $clusters{$cluster_id};
		my @members = $seqcluster_obj->get_members();
		
		foreach my $seqmember (@members) {
		    my $seq = $seqs{$seqmember->display_id()};
		    if (defined $seq) {
			$seqmember->seq($seq->seq());
		    }
		}  
	    }
	    
	}
    }
    else {
      	croak("ARG. ERROR: No argument was used for load_seqfile function\n");
    }
}

=head2 load_strainfile

  Usage: $phygecluster->load_strainfile($arguments_href);

  Desc: Parse the strain file using parse_seqfile function and
        load the results into the PhyGeCluster object

  Ret: None

  Args: A hash reference with the following key: strainfile

  Side_Effects: Die if the argument used is not a hash or if none 
                strainfile is detailed.

  Example: $phygecluster->load_strainfile($arguments_href);

=cut

sub load_strainfile {
    my $self = shift;
    my $arg_href = shift;
    
    my %strains = ();
    
    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'strainfile'}) {
	    croak("ARG. ERROR: 'strainfile' is not defined for $arg_href.\n");
	}
	else {
	    my %strains = parse_strainfile($arg_href);
	    $self->set_strains(\%strains);
	}
    }
    else {
      	croak("ARG. ERROR: No arg. was used for load_strainfile function\n");
    }
}



#######################
## PARSING FUNCTIONS ##
#######################

=head2 parse_blastfile

  Usage: my %clusters = parse_blastfile($arguments_href);

  Desc: Parse the blast file using bioperl Bio::SearchIO
        Cluster the sequences based in clustervalues. 

  Ret: %cluster, a hash with keys=cluster_name and 
       value=Bio::Cluster::SequenceFamily object

  Args: A hash reference with the following keys: blastfile, blastformat,
        sequencefile, clustervalues and rootname.
        Permited clustervalues: evalue, expect, frac_identical, frac_conserved,
		                gaps, hsp_length,  num_conserved, 
                                num_identical, score, bits, percent_identity

  Side_Effects: Die if the argument used is not a hash, if none 
                blastfile is detailed or if the clustervalues is not
                permitted
                blastformat = 'blasttable' by default.
                clustervalues = { percent_identity => ['>', 90'], 
                                  hsp_length       => ['>', 60'] }
                rootname = 'cluster'
                Print status messages with $arg_href->{'debug'}
                Calculate the percent_identity as frac_identical * 100
                instead to use percent_identity from the blast result
                (it is a Bio::SearchIO

  Example: my %clusters = parse_blastfile($arguments_href);

=cut

sub parse_blastfile {
    my $arg_href = shift;
    
    my %clusters = ();
    my %cluster_members = ();

    ## Define the permited blast variables according the 
    ## HSP methods

    my %blastvar = ( evalue           => 1,
		     expect           => 1,
		     frac_identical   => 1,
		     frac_conserved   => 1, 
		     gaps             => 1,
		     hsp_length       => 1,
		     num_conserved    => 1, 
		     num_identical    => 1,
		     score            => 1,
		     bits             => 1,
		     percent_identity => 1, 
	);


    ## Now parsing...

    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'blastfile'}) {
	    croak("ARGUMENT ERROR: 'blastfile' isnot defined for $arg_href.\n");
	}
	else {
		
	    ## 0) Define default values
	    
	    unless (defined $arg_href->{'blastformat'}) {
		$arg_href->{'blastformat'} = 'blasttable';
	    }
	    unless (defined $arg_href->{'clustervalues'}) {
		$arg_href->{'clustervalues'} = { 
		    "percent_identity" => ['>', 90], 
		    "hsp_length"       => ['>', 60],
		};
	    }
	    else {
		foreach my $clval_key (keys %{$arg_href->{'clustervalues'}}) {
		    unless (exists $blastvar{$clval_key}) {
			my $er = "WRONG BLAST VARIABLE: $clval_key is not a ";
			$er .= "permited var. for parse_blast function.";
			croak($er);
		    }
		}
	    }

	    unless (defined $arg_href->{'rootname'}) {
		$arg_href->{'rootname'} = 'cluster';
	    }
	    
	    ## 1) Parse the file and create the clusters
	    
	    my %clustervals = %{$arg_href->{'clustervalues'}};
	    
	    my $searchio = Bio::SearchIO->new( 
		-format => $arg_href->{'blastformat'}, 
		-file   => $arg_href->{'blastfile'}
		);
	    
	    my $ht = $searchio->result_count();
	    my $hc = 0;

	    ## define the last cluster n
			    
	    my $cluster_n = 0;

	    while( my $result = $searchio->next_result() ) {
		
		my $q_name = $result->query_name();		

		while( my $hit = $result->next_hit() ) {

		    $hc++;
		    my $s_name = $hit->name();
		    if (exists $arg_href->{'report_status'}) {
			print_parsing_status($hc, $ht, 
					   "Percentage of blast file parsed:");
		    }
		    
		    while( my $hsp = $hit->next_hsp() ) {

			## define the last cluster n
			    
			$cluster_n = scalar(keys(%clusters));

			## Define the cluster name according the q_name
		
			my $cluster_name = $cluster_members{$q_name};
			    
			unless ($q_name eq $s_name) {
			    
			    ## define the conditions needed for be in 
			    ## a cluster.
			    my $conditions_n = scalar(keys(%clustervals));

			    foreach my $cluster_cond (keys %clustervals) {
				my $cutc = $clustervals{$cluster_cond};
				
				if (ref($cutc) ne 'ARRAY') {
				    my $er2 = "WRONG clustervalues format ";
				    $er2 .= "($cutc) for parse_blastfile()";
				    croak($er2);
				}
				
				my $cond = $clustervals{$cluster_cond}->[0];
				my $val = $clustervals{$cluster_cond}->[1];
				unless ($val =~ m/^\d+$/) {
				    my $er3 = "WRONG clustervalues val=";
				    $er3 .= "$cluster_cond only int. are ";
				    $er3 .= "permited for parse_blastfile()";
				    croak($er3);
				}
				    
				if ($cond =~ m/^<$/) {
				    if ($hsp->$cluster_cond < $val) {
					$conditions_n--;
				    }
				} 
				elsif ($cond =~ m/^<=$/) {
				    if ($hsp->$cluster_cond <= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^==$/) {
				    if ($hsp->$cluster_cond == $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>=$/) {
				    if ($hsp->$cluster_cond >= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>$/) {
				    if ($hsp->$cluster_cond > $val) {
					$conditions_n--;
				    }
				}
				else {
				    my $er4 = "WRONG clustervalues val=";
				    $er4 .= "$cluster_cond, it is not a ";
				    $er4 .= "permited condition ('<','<=',";
				    $er4 .= "'==','>=' or '>')\n";
				    croak($er4);
				}
			    }    
			    
			    unless (exists $cluster_members{$s_name}) {
				
				## New cluster condition, it will overwrite
				## the default cluster name 
				
				if ($conditions_n > 0) {
				    $cluster_name = $arg_href->{'rootname'} 
				    . '_' . ($cluster_n+1);
				}
				
				unless (exists $clusters{$cluster_name}) {
				    $clusters{$cluster_name} = [$s_name];
				}
				else {
				    push @{$clusters{$cluster_name}}, 
				    $s_name;
				}
				$cluster_members{$s_name} = $cluster_name;
			    }
			}
			else {  
                       
			    ## Selfblast hit. It always will add that if it
			    ## has not added before as subject (s_name) hit

			    unless (exists $cluster_members{$q_name}) {
			    
				$cluster_name =  $arg_href->{'rootname'} . 
				    '_' . 
				    ($cluster_n+1);
				    
				unless (exists $clusters{$cluster_name}) {
				    $clusters{$cluster_name} = [$q_name];
				}
				else {
				    push @{$clusters{$cluster_name}}, 
				    $q_name;
				}
				$cluster_members{$q_name} = $cluster_name;
			    }
			}
		    }		    
		}
	    }
	}
	if (exists $arg_href->{'report_status'}) {
			print "\n";
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_blast function\n");
    }
    foreach my $cl_id (keys %clusters) {

	my @seqs = ();
	foreach my $seq_id (@{$clusters{$cl_id}}) {
	    my $seq = Bio::Seq->new(
		-id => $seq_id,
		);
	    push @seqs, $seq;
	}
	
	my $seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $cl_id,
	    -members   => \@seqs,
	    );
	$clusters{$cl_id} = $seqfam;
    } 
    return %clusters;
}

=head2 fastparse_blastfile

  Usage: my %clusters = fastparse_blastfile($arguments_href);

  Desc: Parse the blast file using its own script
        Cluster the sequences based in clustervalues

  Ret: %cluster, a hash with keys=cluster_name and 
       value=Bio::Cluster::SequenceFamily object

  Args: A hash reference with the following keys: blastfile, blastformat,
        sequencefile, clustervalues and rootname.
        Permited clustervalues: query_id, subject_id, percent_identity, 
                                align_length, mismatches, gaps_openings, 
                                q_start, q_end, s_start, s_end, e_value, 
                                bit_score.

  Side_Effects: Die if the argument used is not a hash or if none 
                blastfile is detailed.
                Die if is using non permited clustervalues
                blastformat = 'blasttable' by default.
                clustervalues = { percent_identity => ['>', 90 ], 
                                  align_length     => ['>', 60 ],
                                  mismatches       => ['<', 25 ]}
                rootname = 'cluster'
                Print status messages with $arg_href->{'debug'}

  Example: my %clusters = parse_blastfile($arguments_href);

=cut

sub fastparse_blastfile {
    my $arg_href = shift;
    
    my %clusters = ();
    my %cluster_members = ();

    ## Define the possible clustervalues

    my %blastvar = (
	            'query_id'         => 0, 
		    'subject_id'       => 1, 
		    'percent_identity' => 2, 
		    'align_length'     => 3,
		    'mismatches'       => 4, 
		    'gaps_openings'    => 5,
		    'q_start'          => 6,
		    'q_end'            => 7, 
		    's_start'          => 8, 
		    's_end'            => 9,
		    'e_value'          => 10,
		    'bit_score'        => 11,
	);

    ## Now parsing...

    if (defined $arg_href) {
	
	if (ref($arg_href) ne 'HASH') {
	    croak("ARGUMENT ERROR: $arg_href is not a hash reference.\n");
	}

	unless (defined $arg_href->{'blastfile'}) {
	    croak("ARGUMENT ERROR: 'blastfile' isnot defined for $arg_href.\n");
	}
	else {

	    ## Check fastblastparser compatibilities
	    my $bl_format = $arg_href->{'blastformat'};
	    if (defined $bl_format && $bl_format !~ m/m8|blasttable/) {
		my $er0 = "ARG. ERROR: fastparse_blastfile function only ";
		$er0 .= "can be used with blasttable or m8 formats";
		croak($er0);
	    }
	    
		
	    ## 0) Define default values

	    unless (defined $arg_href->{'clustervalues'}) {
		$arg_href->{'clustervalues'} = { 
		    "percent_identity" => ['>', 90], 
		    "align_length"     => ['>', 60],
		};
	    }
	    else {
		foreach my $clval_key (keys %{$arg_href->{'clustervalues'}}) {
		    unless (exists $blastvar{$clval_key}) {
			my $er = "WRONG BLAST VARIABLE: $clval_key is not a ";
			$er .= "permited var. for fastparse_blast function.";
			croak($er);
		    }
		}
	    }
	    unless (defined $arg_href->{'rootname'}) {
		$arg_href->{'rootname'} = 'cluster';
	    }
	    
	    ## 1) Parse the file and create the clusters
	    
	    my %clustervals = %{$arg_href->{'clustervalues'}};
	    
	    my $infile = $arg_href->{'blastfile'};
	    
	    my $ht = `cut -f1 $infile | wc -l`;
	    chomp($ht);
	    my $hc = 0;

	    open my $in, '<', $infile;

	    while(<$in>) {
		chomp($_);
		$hc++;

		my %datap = ();
		my @data = split(/\t/, $_);
		foreach my $field (sort {$blastvar{$a} <=> $blastvar{$b}} 
				   keys(%blastvar) ) {

		    $datap{$field} = $data[$blastvar{$field}];
		}

		my $q_name = $datap{'query_id'};
		my $s_name = $datap{'subject_id'};
		
		## define the last cluster n
		
		my $cluster_n = scalar(keys(%clusters));

		## Define the cluster name according the q_name
		
		my $cluster_name = $cluster_members{$q_name};
		
		if (exists $arg_href->{'report_status'}) {
		    print_parsing_status($hc, $ht, 
					 "Percentage of blast file parsed:");
		}
		    
		unless ($q_name eq $s_name) {
		    
		    ## define the conditions needed for be in 
		    ## a cluster.
		    my $conditions_n = scalar(keys(%clustervals));
			
		    foreach my $cluster_cond (keys %clustervals) {
			my $cutc = $clustervals{$cluster_cond};
			if (ref($cutc) ne 'ARRAY') {
			    my $er2 = "WRONG clustervalues format ";
			    $er2 .= "($cutc) for parse_blastfile()";
			    croak($er2);
			}

			my $cond = $clustervals{$cluster_cond}->[0];
			my $val = $clustervals{$cluster_cond}->[1];
			unless ($val =~ m/^\d+$/) {
			    my $er3 = "WRONG clustervalues val=$cluster_cond";
			    $er3 .= "only int. are permited parse_blastfile()";
			    croak($er3);
			}


			if ($cond =~ m/^<$/) {
			    if ($datap{$cluster_cond} < $val) {
				$conditions_n--;
			    }
			} 
			elsif ($cond =~ m/^<=$/) {
			    if ($datap{$cluster_cond} <= $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^==$/) {
			    if ($datap{$cluster_cond} == $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^>=$/) {
			    if ($datap{$cluster_cond} >= $val) {
				$conditions_n--;
			    }
			}
			elsif ($cond =~ m/^>$/) {
			    if ($datap{$cluster_cond} > $val) {
				$conditions_n--;
			    }
			}
			else {
			    my $er4 = "WRONG clustervalues val=";
			    $er4 .= "$cluster_cond, it is not a ";
			    $er4 .= "permited condition ('<','<=',";
			    $er4 .= "'==','>=' or '>')\n";
			    croak($er4);
			}
		    }    
			    
		    unless (exists $cluster_members{$s_name}) {
				
			## New cluster condition, it will overwrite the
			## default cluster name 

			if ($conditions_n > 0) {
			    $cluster_name =  $arg_href->{'rootname'} . 
				'_' . 
				($cluster_n+1);
			}

			unless (exists $clusters{$cluster_name}) {
			    $clusters{$cluster_name} = [$s_name];
			}
			else {
			    push @{$clusters{$cluster_name}}, $s_name;
			}
			$cluster_members{$s_name} = $cluster_name;
		    }
		}
		else {  
		
		    ## Selfblast hit. It always will add that if it has not
		    ## added before as subject (s_name) hit
		
		    unless (exists $cluster_members{$q_name}) {
		    
			$cluster_name =  $arg_href->{'rootname'} . 
			    '_' . 
			    ($cluster_n+1);

			unless (exists $clusters{$cluster_name}) {
			    $clusters{$cluster_name} = [$q_name];
			}
			else {
			    push @{$clusters{$cluster_name}}, $q_name;
			}
			$cluster_members{$q_name} = $cluster_name;
		    }
		}
	    }
	    close $in;
	    if (exists $arg_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_blast function\n");
    }

    ## Finally it will convert all the cluster data into key=cluster_id and
    ## value=Bio::Cluster::SequenceFamily object

    foreach my $cl_id (keys %clusters) {

	my @seqs = ();
	foreach my $seq_id (@{$clusters{$cl_id}}) {
	    my $seq = Bio::Seq->new(
		-id => $seq_id,
		);
	    push @seqs, $seq;
	}
	
	my $seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $cl_id,
	    -members   => \@seqs,
	    );
	$clusters{$cl_id} = $seqfam;
    }

    return %clusters;
}



=head2 parse_seqfile

  Usage: my %seqs = parse_seqfile($arguments_href);

  Desc: Parse the fasta file using bioperl Bio::SeqIO
        and return a hash with keys=seq_id and values=seqobjs

  Ret: %seqs, a hash with keys=seq_id and value= with
       sequences ids.

  Args: A hash reference with the following keys: blastfile, blastformat,
        sequencefile, clustervalues and rootname.

  Side_Effects: Die if the argument used is not a hash.
                Print status messages with $arg_href->{'debug'}

  Example: my %seqs = parse_seqfile($arguments_href);

=cut

sub parse_seqfile {
    my $args_href = shift;
    
    my %seqs = ();
    
    if (defined $args_href) {
	if (ref($args_href) ne 'HASH') {
	    croak("ARG. ERROR: $args_href is not a hash reference.\n");
	}
	unless (defined $args_href->{'sequencefile'}) {
	    croak("ARG. ERROR: 'sequencefile' is not defined for $args_href\n");
	}
	else {

	    my $seqfile = $args_href->{'sequencefile'};
	    my $seqio = Bio::SeqIO->new(-format => 'fasta', 
					-file => $seqfile );
	    
	    
	    my $st = `grep -c '>' $seqfile`;
	    chomp($st);
	    my $sc = 0;
	    
	    while((my $seqobj = $seqio->next_seq())) {
		
		$sc++;
		my $seqid = $seqobj->display_id();
		$seqs{$seqid} = $seqobj;
		if (exists $args_href->{'report_status'}) {
		    print_parsing_status($sc, $st, 
					 "Percentage of seq file parsed:");
		}
	    }
	    if (exists $args_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
      	croak("ARG. ERROR: No argument was used for parse_seqfile function\n");
    }
    
    return %seqs;
}




=head2 parse_strainfile

  Usage: my %strains = parse_strainfile($arguments_href);

  Desc: Parse the strain file and return a hash with keys=seq_id 
        and values=strain

  Ret: %strain, a hash with keys=seq_id and value= strain

  Args: A hash reference with the following keys: blastfile, blastformat,
        sequencefile, strainfile, clustervalues and rootname.

  Side_Effects: Die if the argument used is not a hash.
                Die if the if do not exists $args{'strainfile'}
                Print status messages with $arg_href->{'debug'}

  Example: my %strain = parse_strainfile($arguments_href);

=cut

sub parse_strainfile {
    my $arg_href = shift;
    
    my %strains = ();
    
    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href is not a hash reference.\n");
	}
	unless (defined $arg_href->{'strainfile'}) {
	    croak("ARG. ERROR: 'strainfile' is not defined for $arg_href.\n");
	}
	else {
	    open my $fileio, '<', $arg_href->{'strainfile'};
	    my $st = `cut -f1 $arg_href->{'strainfile'} | wc -l`;
	    chomp($st);
	    my $sc = 0;

	    while(<$fileio>) {
		chomp($_);
		$sc++;
		my @cols = split('\t', $_);
		$strains{$cols[0]} = $cols[1];
		if (exists $arg_href->{'report_status'}) {
		    print_parsing_status($sc, $st, 
					 "Percentage of strain file parsed:");
		}
	    }
	    close $fileio;
	    if (exists $arg_href->{'report_status'}) {
		print "\n";
	    }
	}
    }
    else {
      	croak("ARG. ERROR: No arg. was used for parse_strainfile function\n");
    }
    
    return %strains;
}

=head2 parse_acefile

  Usage: my %clusters = parse_acefile($arguments_href);

  Desc: Parse partially an assembly file for .ace format and return a
        hash with keys=contig_id and value=Bio::Cluster::SequenceFamily object

  Ret: A hash with keys=contig_id and value=Bio::Cluster::SequenceFamily

  Args: A hash reference with the following keys: acefile, debug

  Side_Effects: Die if the argument used is not a hash.
                Die if the if do not exists $args{'acefile'}
                Print status messages with $arg_href->{'report_status'}

  Example: my %clusters = parse_acefile($arguments_href);

=cut

sub parse_acefile {
    my $arg_href = shift;
    
    ## Check variables

    if (defined $arg_href) {
	if (ref($arg_href) ne 'HASH') {
	    croak("ARG. ERROR: $arg_href isn't a hash ref. for parse_acefile");
	}
    }
    else {
	croak("ARG. ERROR: No argument was used for parse_acefile function");
    }

    ## Define the variables

    my %clusters = ();

    my $acefile = $arg_href->{'acefile'} ||
	croak("ARG. ERROR: 'acefile' isn't defined for $arg_href.\n");
    
    my $L = `cut -f1 $acefile | wc -l`;
    chomp($L);
    my $l = 0;
    
    
    ## Define the catching variables
    
    my $curr_cr = '';
    my $contig_id = '';
    my $read_id = '';
    my %contigs = ();
    my %reads = ();

    ## Counting vars:

    my ($contigs_n, $reads_n) = (0, 0);

    ## Open the file

    open my $ifh, '<', $acefile;
   
    while(<$ifh>) {
	chomp($_);
	$l++;

	if (exists $arg_href->{'report_status'}) {
	    my $contig_c = scalar(keys %contigs);
	    print_parsing_status($contig_c, $contigs_n, 
				 "Percentage of ace file parsed:");
	}
	
	if ($_ =~ m/^([A-Z][A-Z]) /) {
	    $curr_cr = $1;
	}
	elsif ($_ =~ m/^$/) {
	    $curr_cr = '';
	}
	
	if ($curr_cr eq 'AS') {
	    if ($_ =~ m/^AS\s+(\d+)\s+(\d+)/) {
		$contigs_n = $1;
		$reads_n = $2;
	    }
	}
	if ($curr_cr eq 'CO') {
	    if ($_ =~ m/^CO\s+(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\w)/) {
		$contig_id = $1;

		$contigs{$contig_id} = { 'bases_num'    => $2, 
					 'reads_num'    => $3,
					 'base_segm'    => $4,
					 'complemenent' => $5,
					 'seq'          => '',
					 'rd_members'   => {},
		};  
	    }
	    else {
		$contigs{$contig_id}->{'seq'} .= $_;
	    }
	}
	if ($curr_cr eq 'AF') {
	    if ($_ =~ m/^AF\s+(.+?)\s+(\w)\s+(-?\d+)/) {
		$read_id = $1;
		$reads{$read_id} = { 'complemenent'        => $2,
				     'pad_start_consensus' => $3,
				     'pad_bases_num'       => '',
				     'seq'                 => '',
				     'qual_clip_start'     => '',
				     'qual_clip_end'       => '',
				     'align_clip_start'    => '',
				     'align_clip_end'      => '',
		};
		unless (exists $contigs{$contig_id}->{rd_members}->{$read_id}) {
		    $contigs{$contig_id}->{rd_members}->{$read_id} = 1;
		}
	    }  	    
	}
	if ($curr_cr eq 'RD') {
	    if ($_ =~ m/^RD\s+(.+?)\s+(\d+)\s+(\d+)\s+(\d+)/) {
		$read_id = $1;
		if (exists $reads{$read_id}) {
		    $reads{$read_id}->{'pad_bases_num'} = $2;
		}
		else {
		    $reads{$read_id} = { 'complemenent'        => '',
					 'pad_start_consensus' => '',
					 'pad_bases_num'       => $2,
					 'seq'                 => '',
					 'qual_clip_start'     => '',
					 'qual_clip_end'       => '',
					 'align_clip_start'    => '',
					 'align_clip_end'      => '',
		    };
		}
		unless (exists $contigs{$contig_id}->{rd_members}->{$read_id}) {
		    $contigs{$contig_id}->{rd_members}->{$read_id} = 1;
		}
	    }
	    else {
		$reads{$read_id}->{'seq'} .= $_;
	    }
	}
	if ($curr_cr eq 'QA') {
	    if ($_ =~ m/^QA\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {

		$reads{$read_id}->{'qual_clip_start'} = $1;
		$reads{$read_id}->{'qual_clip_end'} = $2;
		$reads{$read_id}->{'align_clip_start'} = $3;
		$reads{$read_id}->{'align_clip_end'} = $4;

		my $seqobj = Bio::Seq->new( -id  => $read_id,
					    -seq => $reads{$read_id}->{'seq'},
		    );

		## To get the trim sequence, remenber that .ace files are
		## 1-based and bioperl is 1-based. The end position will
		## be length+1 (for example 1nt length will be 1-2)

		my $st = $reads{$read_id}->{'align_clip_start'};
		my $en = $reads{$read_id}->{'align_clip_end'};
		my $cs = $reads{$read_id}->{'pad_start_consensus'};
		my $le = $en - $st;
		my $ce = $en + $cs;

		my $init_gaps = '';
		my $final_gaps = '';
		if ($reads{$read_id}->{'pad_start_consensus'} =~ m/^-(\d+)/) {
		    $st = $1 + 2;
		    $reads{$read_id}->{'pad_start_consensus'} = 1;
		}
		else {
		
		    ## It will add as many gaps signs before the sequence as 
		    ## pad_start_consensus - 1.
		    if ($cs >= 0) {
			foreach my $i (1 .. $cs + $st - 2) {
			    $init_gaps .= '-';
			}
		    }
		}
		my $co_en = $contigs{$contig_id}->{'bases_num'} + 1;
		if ($co_en > $ce) {
		    foreach my $y (1 .. $co_en - $ce) {
			$final_gaps .= '-';
		    }
		}
		
		$reads{$read_id}->{'trimseq'} = $init_gaps . 
		                                $seqobj->subseq($st, $en) .
						$final_gaps;
	        $reads{$read_id}->{'trimseq'} =~ s/\*/-/g;
		my $unpadseq = $reads{$read_id}->{'trimseq'};
		$unpadseq =~ s/-//g;
		$reads{$read_id}->{'unpadseq'} = $unpadseq
	    }
	}
    }

    ## Now it will build the clusters with the sequences.

    foreach my $ctg_id (keys %contigs) {
	my %contig_data = %{$contigs{$ctg_id}};
	my %members = %{$contig_data{'rd_members'}};

	## First, create the array with Bio::Seq::Meta objects with all
	## the sequence members.

	my @align_objs = ();
	my @member_objs = ();
	foreach my $memb_id (keys %members) {
	    my %rd = %{$reads{$memb_id}};
	    my $strand = 1;
	    if ($rd{'complemenent'} eq 'C') {
		$strand = -1;
	    }
	    
	    my $seq = Bio::Seq->new( -id => $memb_id, -seq => $rd{'unpadseq'} );
	    push @member_objs, $seq;

	    my $metaseq = Bio::LocatableSeq->new( 
		-id     => $memb_id,
		-start  => $rd{'pad_start_consensus'},
		-end    => $rd{'pad_start_consensus'}+length($rd{'unpadseq'})-1,
		-strand => $strand,
		-seq    => $rd{'trimseq'},
		-verbose => 0,
		);
	    push @align_objs, $metaseq;
	}

	## Second, create the Bio::Align object.

	my $cons_seq = Bio::Seq::Meta->new( 
	    -id  => $ctg_id,
	    -seq => $contigs{$ctg_id}->{'seq'},
	    );

	my $align = Bio::SimpleAlign->new( -id        => $ctg_id, 
					   -source    => '.ace, assembly file',
					   -seqs      => \@align_objs,
					   -consensus_meta => $cons_seq, 
	    );

	## Create a Bio::Cluster::SequenceFamily object and load the 
	## alignment

	my $seqfam = Bio::Cluster::SequenceFamily->new(
	    -family_id => $ctg_id, 
	    -members   => \@member_objs,	    
	    );
	$seqfam->alignment($align),
	
	$clusters{$ctg_id} = $seqfam;
    }
    return %clusters;
}

######################
## OUTPUT FUNCTIONS ##
######################

=head2 print_parsing_status

  Usage: print_parsing_status($progress, $total, $message);

  Desc: Print as STDERR the percentage of the file parsed

  Ret: none

  Args: $progress, a scalar, an integer with the progress
        $total, a scalar, a integer with the total
        $message to print before the percentage

  Side_Effects: Die if 1st and 2nd arguments are undefined or are not integers
                Print as default message: Percentage of the file parsed: ";

  Example: print_parsing_status($progress, $total, $message);

=cut

sub print_parsing_status {
    my $a = shift ||
	croak("ERROR: 1st argument is not defined for print_parsing_status()");
    my $z = shift ||
	croak("ERROR: 2nd argument is not defined for print_parsing_status()");
    my $message = shift ||
	"Percentage of the file parsed:";

    unless ($a =~ m/^\d+$/) {
	croak("ERROR: 1st argument is not an int. for print_parsing_status()");
    }
    unless ($a =~ m/^\d+$/) {
	croak("ERROR: 1st argument is not an int. for print_parsing_status()");
    }
    
    my $perc = $a * 100 / $z;
    my $perc_obj = Math::BigFloat->new($perc);
    my $perc_formated = $perc_obj->bfround(-2);

    print STDERR "\t$message $perc_formated %\r";
}

=head2 out_clusterfile

  Usage: my %files = $phygecluster->out_clusterfile(\%args);

  Desc: Print into one or more files the clusters members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('clustercomp' by default),
         distribution => $distribution (two options: single or multiple)

  Side_Effects: None

  Example: my %files = $phygecluster->out_clusterfile({ 
                                                       distribution => single});

=cut

sub out_clusterfile {
    my $self = shift;
    my $argshref = shift;

    ## Check variables and complete with default arguments

    my $def_argshref = { rootname     => 'clustercomp', 
			 distribution => 'multiple',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_clusterfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_clusterfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %clusters = %{$self->get_clusters()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . '.multiplecluster.txt';
	open my $outfh1, '>', $outname1;
	$outfiles{'multiple'} = $outname1;
	
	foreach my $cluster_id (sort keys %clusters) {
	    my @members = $clusters{$cluster_id}->get_members();
	    foreach my $member (sort @members) {
		my $member_id = $member->display_id();
		print $outfh1 "$cluster_id\t$member_id\n";
	    }
	}	
	close $outfh1;	
    }
    else {
	foreach my $cluster_id (sort keys %clusters) {
	    my $outname2 = $argshref->{'rootname'} . '.' . $cluster_id  .'.txt';
	    open my $outfh2, '>', $outname2;
	    $outfiles{$cluster_id} = $outname2;
	    
	    my @members = $clusters{$cluster_id}->get_members();
	    foreach my $member (sort @members) {
		my $member_id = $member->display_id();
		print $outfh2 "$cluster_id\t$member_id\n";
	    }
	    close $outfh2;
	}
    }
    
    return %outfiles;
}

=head2 out_alignfile
    
  Usage: my %files = $phygecluster->out_alignfile(\%args);

  Desc: Print into one or more files the alignment of the cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
    and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('alignment' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (bl2seq, clustalw, emboss, fasta, maf, mase,
                                  mega, meme, metafasta, msf, nexus, pfam, 
                                  phylip, po, prodom, psi, selex, stockholm,
                                  XMFA, arp)
                         (see bioperl Bio::AlignIO for more details)
                         ('clustalw' by default)
         extension    => $fileextension ('aln' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_alignfile();

=cut

sub out_alignfile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { 'rootname'     => 'alignment', 
			 'distribution' => 'multiple',			 
			 'format'       => 'clustalw',
                         'extension'    => 'aln',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %clusters = %{$self->get_clusters()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multiplealignments.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $alignio1 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                          -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %clusters) {
    
	    my $align = $clusters{$cluster_id}->alignment();
            if (defined $align) {
                $alignio1->write_aln($align);
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %clusters) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    $outfiles{$cluster_id} = $outname2;
	    
	    my $alignio2 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                              -file   => ">$outname2",
                                            );

            my $align = $clusters{$cluster_id}->alignment();
            if (defined $align) {
                $alignio2->write_aln($align);
            }
	}
    }

    return %outfiles;
}

=head2 out_bootstrapfile
    
  Usage: my %files = $phygecluster->out_bootstrapfile(\%args);

  Desc: Print into one or more files the bootstrap for the alignment of the 
        cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('alignment' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (bl2seq, clustalw, emboss, fasta, maf, mase,
                                  mega, meme, metafasta, msf, nexus, pfam, 
                                  phylip, po, prodom, psi, selex, stockholm,
                                  XMFA, arp)
                         (see bioperl Bio::AlignIO for more details)
                         ('clustalw' by default)
         extension    => $fileextension ('aln' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_bootstrapfile();

=cut

sub out_bootstrapfile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { 'rootname'     => 'bootstrap', 
			 'distribution' => 'single',			 
			 'format'       => 'clustalw',
                         'extension'    => 'aln',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %bootstrap = %{$self->get_bootstrapping()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multiplealignments.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $alignio1 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                          -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %bootstrap) {
    
	    my @aligns = @{$bootstrap{$cluster_id}}; 
            foreach my $align (@aligns) {
                $alignio1->write_aln($align);
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %bootstrap) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    $outfiles{$cluster_id} = $outname2;
	    
	    my $alignio2 = Bio::AlignIO->new( -format => $argshref->{'format'},
                                              -file   => ">$outname2",
                                            );

            my @aligns = @{$bootstrap{$cluster_id}}; 
            foreach my $align (@aligns) {
                $alignio2->write_aln($align);
            }
	}
    }

    return %outfiles;
}


=head2 out_distancefile
    
  Usage: my %files = $phygecluster->out_distancefile(\%args);

  Desc: Print into one or more files the distance of the cluster members

  Ret: A hash with key=cluster_id and value=filename. When more than one
       cluster is printed in a single file the hash will be key=multiple
       and value=filename

  Args: A hash reference with the following options:
         rootname     => $basename ('distance' by default),
         distribution => $distribution (two options: single or multiple),
         format       => $format (mlagan, phylip)
                         (see bioperl Bio::MatrixIO for more details)
                         ('phylip' by default)
         extension    => $fileextension ('txt' by default)

  Side_Effects: None

  Example: my %files = $phygecluster->out_distancefile();

=cut

sub out_distancefile {
    my $self = shift;
    my $argshref = shift;
    
    ## Check variables and complete with default arguments
    
    my $def_argshref = { rootname     => 'distance', 
			 distribution => 'multiple',
			 format       => 'phylip',
			 extension    => 'txt',
    };

    if (defined $argshref) {
	unless (ref($argshref) eq 'HASH') {
	    croak("ARG.ERROR: $argshref isn't a hashref in out_alignfile");
	}
	else {
	    foreach my $key (keys %{$argshref}) {
		unless (exists $def_argshref->{$key}) {
		    croak("ARG.ERROR: $key isn't a valid arg. out_alignfile");
		}
	    }
	    foreach my $defkey (keys %{$def_argshref}) {
		unless (exists $argshref->{$defkey}) {
		    $argshref->{$defkey} = $def_argshref->{$defkey}
		}
	    }
	}
    }
    else {
	$argshref = $def_argshref;
    }

    ## Define the output hash

    my %outfiles = ();

    ## Get the clusters

    my %distances = %{$self->get_distances()};

    ## Print according the distribution. It it is multiple it will create
    ## one file for all the clusters, if not it will create one file per
    ## cluster.

    if ($argshref->{'distribution'} eq 'multiple') {
	my $outname1 = $argshref->{'rootname'} . 
                       '.multipledistances.' . 
                       $argshref->{'extension'};
	$outfiles{'multiple'} = $outname1;
	
        my $matrixio1 = Bio::Matrix::IO->new( -format => $argshref->{'format'},
                                              -file   => ">$outname1",
                                        );

	foreach my $cluster_id (sort keys %distances) {
            if (defined $distances{$cluster_id}) {
                $matrixio1->write_matrix($distances{$cluster_id});
            }
	}	
    }
    else {
	foreach my $cluster_id (sort keys %distances) {
	    my $outname2 = $argshref->{'rootname'} . '.' . 
                           $cluster_id  . '.' .
                           $argshref->{'extension'};
	    $outfiles{$cluster_id} = $outname2;
	    
	    if (defined $distances{$cluster_id}) {
		my $matrixio2 = Bio::Matrix::IO->new( 
		    -format => $argshref->{'format'},
		    -file   => ">$outname2",
		);

                $matrixio2->write_matrix($distances{$cluster_id});
	    }
	}
    }

    return %outfiles;
}


##########################
## ANALYTICAL FUNCTIONS ##
##########################

=head2 cluster_sizes

  Usage: my %cluster_sizes = phygecluster->cluster_sizes();
         my %cluster_sizes = phygecluster->cluster_sizes($min, $max);

  Desc: return a hash with keys=cluster_id and values=size

  Ret: %cluster_sizes,  with keys=cluster_id and values=size

  Args: $min, $max values to select the sizes ($min <= $size <= $max)

  Side_Effects: If $min value is detailed but $max value is absent, 
                $max = $min.
                If there are not any cluster with the size requeriments,
                it will return undef

  Example: my %cluster_sizes = phygecluster->cluster_sizes();
           my %singlets = phygecluster->cluster_sizes(1,1);
=cut

sub cluster_sizes {
    my $self = shift;
    my $min = shift;
    my $max = shift;

    if ($min && !$max) {
	$max = $min;
    }

    my %cluster_sizes = ();

    my %clusters = %{$self->get_clusters()};

    foreach my $cluster_name (keys %clusters) {
	my $size = $clusters{$cluster_name}->size();

	if (defined $min) {
	    if ($min <= $size && $size <= $max) {
		$cluster_sizes{$cluster_name} = $size;
	    }
	}
	else {
	    $cluster_sizes{$cluster_name} = $size;
	}
    }

    return %cluster_sizes;
}


=head2 calculate_overlaps

  Usage: my %overlaps = $phygecluster->calculate_overlaps();

  Desc: Calculate the overlap positions for each pair of sequences in an 
        alignment and return a hash with key=cluster_id and 
        value=Bio::Matrix::Generic with member_ids as columns and row names.
        The matrix will have as element { start => $val1, end => $val2, 
        length => $val3}

  Ret: %hash = ( $cluster_id => Bio::Matrix::Generic object );   

  Args: None.

  Side_Effects: Return overlaps only for clusters with alignments

  Example: my %overlaps = phygecluster->calculate_overlaps();
           

=cut

sub calculate_overlaps {
    my $self = shift;

    my %overlaps = ();
    my %clusters = %{$self->get_clusters()};

    foreach my $cluster_id (keys %clusters) {
	my $align = $clusters{$cluster_id}->alignment();

	if (defined $align) {
	    
	    ## Get the member ids to create the empty matrix, and get also
	    ## the start and the end of each sequence.
	    
	    my %post = ();
	    my @member_ids = ();
	    foreach my $seq ($align->each_seq()) {
		my $id = $seq->display_id();
		push @member_ids, $id;

		my $seqstr = $seq->seq();
		my @nts = split(//, $seqstr);
		my ($pos, $start, $end) = (0, 0, 0);
		foreach my $nt (@nts) {
		    $pos++;
		    if ($nt !~ m/(-|\*|\.)/) {  ## If it is not a gap
			if ($start == 0) {
			    $start = $pos;
			}
			$end = 0;
		    }
		    else {
			if ($start > 0 && $end == 0) {
			    $end = $pos - 1;
			}
		    }
		}
		if ($end == 0) {
		    $end = $pos;
		}
		$post{$id} = [$start, $end, $end-$start];
	    }

	    ## Create the matrix with the member ids.
	    my $matrix = Bio::Matrix::Generic->new( 
		-rownames          => \@member_ids,
		-colnames          => \@member_ids, 
		-matrix_id         => $cluster_id,
		-matrix_init_value => { start => 0, end => 0, length => 0 },
		);

	    ## Now it will compare pairs of sequences to get the 
	    ## overlapping region. There are four posibilities:
	    ## 1) As <= Bs; As < Be; Ae > Bs; --> Overlap St=Bs;En=Ae
	    ## 2) As >= Bs; As < Be; Ae > Bs; --> Overlap St=As;En=Be
	    ## 3) As < Bs; As < Be; Ae < Bs; No overlap.
	    ## 4) As > Bs; As > Be; Ae > Bs; No overlap.
	    ## Note: As=SeqA_start, Ae=SeqA_end, Bs=SeqB_start and Be=SeqB_end

	    foreach my $id_a (@member_ids) {
		my $as = $post{$id_a}->[0];
		my $ae = $post{$id_a}->[1];
		my @row_values = ();
		foreach my $id_b (@member_ids) {
		    my $bs = $post{$id_b}->[0];
		    my $be = $post{$id_b}->[1];
		    
		    my ($start, $end) = (0, 0);
		    if ($as <= $bs && $as < $be && $ae > $bs) {
			$start = $bs;
			$end = $ae;
			if ($ae > $be) {
			    $end = $be;
			}
		    }
		    elsif ($as >= $bs && $as < $be && $ae > $bs) {
			$start = $as;
			$end = $be;
			if ($ae < $be) {
			    $end = $ae;
			}
		    }

		    ## Any other posibility will be a non-overlapping. It will
		    ## add to the matrix the overlapping regions. The diagonal
		    ## always will have start,end and length = 0.
		    
		    if ($id_a ne $id_b) {
			if ($start > 0 && $end > 0) {
			    my $val = { start  => $start, 
					end    => $end, 
					length => $end-$start };
		
			    push @row_values, $val;
			}
			else {
			    push @row_values, { start  => 0, 
						end    => 0, 
						length => 0 };
			}
		    }
		    else {
			push @row_values, { start  => 0, 
					    end    => 0, 
					    length => 0 };
		    }
		}
		## Now it will add this row_values to the matrix
		$matrix->row($id_a, \@row_values);
	    }
	    $overlaps{$cluster_id} = $matrix;
	}    
    }
    return %overlaps;
}


=head2 best_overlaps

  Usage: my %best_overlaps = $phygecluster->best_overlaps();

  Desc: Get the pair of sequences with a longest overlap in an alignment.

  Ret: %hash = ( $cluster_id => [$member_id1, $member_id2] );   

  Args: None.

  Side_Effects: Return overlaps only for clusters with alignments

  Example: my %overlaps = $phygecluster->best_overlaps();
           

=cut

sub best_overlaps {
    my $self = shift;

    my %best_overlaps = ();
    my %overlaps = $self->calculate_overlaps();

    foreach my $cluster_id (keys %overlaps) {

	## Define a hash with key=length and value=pair, It will order the
	## hash and get the longer
	my %ovlength = ();

	my $mtx = $overlaps{$cluster_id};
	my @rownames = $mtx->row_names();
	my @colnames = $mtx->column_names();
	foreach my $row (@rownames) {
	    foreach my $col (@colnames) {
		my $entry = $mtx->get_entry($row, $col);
		$ovlength{$entry->{length}} = [$row, $col];
	    }
	}
	my @ovlength_desc = sort { $b <=> $a } keys %ovlength;
	$best_overlaps{$cluster_id} = $ovlength{$ovlength_desc[0]};
    }
    return %best_overlaps;
}

=head2 homologous_search

  Usage: phygecluster->homologous_search();

  Desc: Search homologous sequences to a cluster consensus using 
        Bio::Tools::Run::StandAloneBlast. It will add the best match according
        the highest score by default but different conditions can be used in the
        same way that in the parse_blastfile function.

  Ret: none (load the member in the phygecluster object)

  Args: $args_href, a hash reference with:
        -blast => $array_reference with the same keys that available arguments 
                   in a blast (for example -d <database> -e <evalue>...). The
                   input sequences will be the cluster consensus sequence.
        -strain => $strain, for the homologous sequences.
        -filter => $hash_reference with the following permited keys: evalue, 
                   expect, frac_identical, frac_conserved, gaps, hsp_length,
                   num_conserved, num_identical, score, bits, percent_identity
                   and a array reference with condition and value

  Side_Effects: Died if some of the parameters are wrong.
                
  Example:  phygecluster->homologous_search({ -blast  => [ -d => $database ],
                                              -strain => 'Sly',
                                              -filter => { 
                                                           hsp_length => 
                                                                   ['>', 100],
                                                         }, 
                                            })

=cut

sub homologous_search {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to homologous_search()");

    ## Check the arguments and create the factory object

    my @blast_param = ();
    my $blastdb_file;

    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Arg=$args_href homologous_search() isn't hashref.");
    }
    else {
	unless (defined $args_href->{'blast'}) {
	    croak("ARG. ERROR: No blast arg. was used for search_homologous()");
	}
	else {
	    my $blast_args = $args_href->{'blast'};
	    unless (ref($blast_args) eq 'ARRAY') {
		croak("ARG. ERROR: blast arg.($blast_args) isnt an array ref.");
	    }
	    else {
		@blast_param = @{$blast_args};
		my $enable_db = 0;
		foreach my $param (@blast_param) {
		    if ($param =~ m/^\-d(atabase)?$/) {
			$enable_db = 1;			
		    }
		    elsif ($enable_db == 1) {
			$blastdb_file = $param;
			$enable_db = 0;
		    }
		}
		unless (defined $blastdb_file) {
		    croak("ARG. ERROR: No blast database was used as argument");
		}
	    }
	    if (defined $args_href->{'filter'}) {
		unless (ref($args_href->{'filter'}) eq 'HASH') {
		    croak("ARG. ERROR: filter arg. isn't a hash ref.")
		}
	    }
	}
    }

    ## Define cluster homologous hash

    my %clusters_hmg = ();

    ## Create the tool factory

    my $factory = Bio::Tools::Run::StandAloneBlast->new(@blast_param);
    
    ## Now it will get the consensus sequence from the clusters and run the
    ## blast

    my %clusters = %{$self->get_clusters()};
    foreach my $cl_id (keys %clusters) {
	my $seqfam = $clusters{$cl_id};
	my $align = $seqfam->alignment();


	if (defined $align) {

	    ## It will get the consensus sequence stored as consensus_meta
	    ## if not, it will calculate its own consensus using 
	    ## consensus_string function.

	    my $consenseq = ''; 
	    if (defined $align->consensus_meta()) {
		$consenseq = $align->consensus_meta();
	    }
	    else {
		$consenseq = Bio::Seq->new( 
		    -id  => $cl_id,
		    -seq => $align->consensus_string(),
		    );
	    }
	    
	    ## Now it will run the blast per sequence and filter it

	    my $blast_report = $factory->blastall($consenseq);
	    
	    while( my $result = $blast_report->next_result() ) {
		
		my $q_name = $result->query_name();		

		while( my $hit = $result->next_hit() ) {

		    my $s_name = $hit->name();

		    while( my $hsp = $hit->next_hsp() ) {
		    
			## By default it will take the best match, usually
			## the first one.

			unless (defined $args_href->{'filter'}) {
			    unless (defined $clusters_hmg{$cl_id}) {
				$clusters_hmg{$cl_id} = { $s_name => 1 };
			    }
			}
			else {
			    
			    ## It should use the filter values in the same
			    ## way that in the parse_blastfile function

			    my %filters = %{$args_href->{'filter'}};
			    my $conditions_n = scalar(keys %filters);
			    foreach my $function (keys %filters) {
				
				unless (ref($filters{$function}) eq 'ARRAY') {
				    my $er = "ARG. ERROR: Value used in filter";
				    $er .= " $filters{$function} is not an ";
				    $er .= "array reference";
				    croak($er);
				}
				
				my $cond = $filters{$function}->[0];
				my $val = $filters{$function}->[1];
			    
				unless ($val =~ m/^\d+$/) {
				    my $er3 = "WRONG filtervalues val=";
				    $er3 .= "$function only int. are ";
				    $er3 .= "permited for search_homologous()";
				    croak($er3);
				}
				    
				if ($cond =~ m/^<$/) {
				    if ($hsp->$function < $val) {
					$conditions_n--;
				    }
				} 
				elsif ($cond =~ m/^<=$/) {
				    if ($hsp->$function <= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^==$/) {
				    if ($hsp->$function == $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>=$/) {
				    if ($hsp->$function >= $val) {
					$conditions_n--;
				    }
				}
				elsif ($cond =~ m/^>$/) {
				    if ($hsp->$function > $val) {
					$conditions_n--;
				    }
				}
				else {
				    my $er4 = "WRONG filtervalues val=";
				    $er4 .= "$function, it is not a ";
				    $er4 .= "permited condition ('<','<=',";
				    $er4 .= "'==','>=' or '>')\n";
				    croak($er4);
				}
			    }    
			    
			    ## It will add a new relation only if all the
			    ## conditions have been satisfied
			    if ($conditions_n == 0) {
				unless (exists $clusters_hmg{$cl_id}) {
				    $clusters_hmg{$cl_id} = {$s_name => 1};
				}
				else {
				    my %members = %{$clusters_hmg{$cl_id}};
				    unless (defined $members{$s_name}) {
					$clusters_hmg{$cl_id}->{$s_name} = 1;
				    }
				}
			    }
			}
		    }
		}
	    }
	}
    }

    ## Now all the relations should be contained in the cluster_hmlg hash.
    ## so now it will load them into the family objects. Before do that, it will
    ## get all the sequences from the database file to load them as seq objects.

    my %blastseqs = parse_seqfile({ sequencefile => $blastdb_file });
    my $strain_href = $self->get_strains();

    foreach my $cl_id2 (keys %clusters) {
	my $seqfam2 = $clusters{$cl_id2};
	
	if (defined $clusters_hmg{$cl_id2}) {
	    my @newmemb = keys %{$clusters_hmg{$cl_id2}};
	    foreach my $memb_id (@newmemb) {
		my $seq = $blastseqs{$memb_id};
		$seqfam2->add_members([$seq]);

		## Also it will add a strain if is defined strain argument

		if (defined $args_href->{'strain'}) {
		    $strain_href->{$memb_id} = $args_href->{'strain'};
		}
	    }
	}
    }
}


=head2 run_alignments

  Usage: phygecluster->run_alignments({ program => $prog, 
                                        parameters => $parameters_href});

  Desc: Create the sequence aligns for each cluster and load it into the
        Bio::Cluster::SequenceFamily object

  Ret: none (load the alignments into the Bio::Cluster::SequenceFamily object)

  Args: $args_href, a hash reference with the following permited keys:
        program => $scalar, parameters => $array_ref with program parameters

  Side_Effects: Died if some of the parameters are wrong.
                It does not run alignments over singlets (cluster with 1 member)

  Example:  phygecluster->run_alignments({ program    => $prog, 
                                           parameters => $parameters_href});

=cut

sub run_alignments {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to run_alignments()");

    ## Check the arguments and create the factory object

    my $factory;
    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Arg=$args_href for run_alignments() isn't hashref.");
    }
    else {
	my %args = %{$args_href};
	
	unless (exists $args{program}) {
	    my $er0 = "ARG. ERROR: Args. supplied to run_alignments doesn't ";
	    $er0 .= "contains 'program' specification";
	    croak($er0);
	}
	else {
	    my %perm_prog = (
		clustalw => 'Bio::Tools::Run::Alignment::Clustalw',
		kalign   => 'Bio::Tools::Run::Alignment::Kalign',
		mafft    => 'Bio::Tools::Run::Alignment::MAFFT',
		muscle   => 'Bio::Tools::Run::Alignment::Muscle',
		tcoffee  => 'Bio::Tools::Run::Alignment::TCoffee',
		);

	    ## Check the program

	    my $pprog = join(',', sort(keys %perm_prog));
	    unless (exists $perm_prog{$args{program}}) {
		my $er1 = "ARG. ERROR: program selected for run_alignments()";
		$er1 .= "is not in the list of permited programs ($pprog)";
		croak($er1);
	    }

	    unless (exists $args{parameters}) {
		my $er3 = "ARG. ERROR: Args. supplied to run_alignments ";
		$er3 .= "doesn't contains 'parameters' specification";
		croak($er3);
	    }
	    else {
		unless (ref($args{parameters}) eq 'ARRAY') {
		    my $er4 = "ARG. ERROR: 'parameters' args. supplied to ";
		    $er4 .= "run_alignments()";
		    $er4 .= "doesn't contains 'parameters' specification";
		    croak($er4);
		}
		else {
		    my @parameters = @{$args{parameters}};
		    $factory = $perm_prog{$args{program}}->new();
		}
	    }
	}	    
    }

    if (defined $factory) {
 
	my %clusters = %{$self->get_clusters()};

	foreach my $cluster_id (keys %clusters) {
	 
	    my @seq_members = $clusters{$cluster_id}->get_members();

	    ## Only make sense if the cluster has more than one member

	    if (scalar(@seq_members) > 1) {
	
		my $alignobj = $factory->align(\@seq_members);

		## Also it will set the alinments into the SequenceFamily 
		## object

		$clusters{$cluster_id}->alignment($alignobj);
	    }
	}
    }
}

=head2 run_distances

  Usage: $phygecluster->run_distances($method);

  Desc: Calculates a distance matrix for all pairwise distances of
        sequences in an alignment using Bio::Align::DNAStatistics object

  Ret: none (it loads %distances, a hash with keys=cluster_id and 
       value=Bio::Matrix::PhylipDis object into the phyGeCluster object)

  Args: $method, a scalar to pass to the Bio::Align::DNAStatistics->distance()
        function (JukesCantor,Uncorrected,F81,Kimura,Tamura or TajimaNei).

  Side_Effects: Died if the methos used is not in the list of available
                method for Bio::Align::DNAStatistics object.
                It not return keys for the clusters that do not have alignment
                or for JukesCantor or F81 methods when gaps >= alignment length.
                It will run JukesCantor distance by default.

  Example: $phygecluster->run_distances('Kimura');

=cut

sub run_distances {
    my $self = shift;
    my $method = shift || 'JukesCantor';

    
    ## Create the Bio::Align::DNAStatistics object

    my $align_stats = Bio::Align::DNAStatistics->new();

    ## Define if the method is a valid method

    my %avmethods = ();
    my @available_methods = $align_stats->available_distance_methods();

    foreach my $av_method (@available_methods) {
	$avmethods{$av_method} = 1;
    }
    
    unless (defined $avmethods{$method}) {
	my $error_message = "ERROR METHOD: $method is not an available for ";
	$error_message .= "run_distance() method.";
	$error_message .= "\nAvailable distance methods:\n\t"; 
	$error_message .= join("\n\t", @available_methods) . "\n";
	croak($error_message);
    }


    my %dist = ();

    my %failing_gapmethod = ( 
	'JukesCantor' => 1,
	'F81'         => 1, 
	);

    ## Get the alignment objects

    my %clusters = %{$self->get_clusters()};
    
    foreach my $cluster_id (keys %clusters) {

	my $alignobj = $clusters{$cluster_id}->alignment();
	
	if (defined $alignobj) {

	    ## Some alignments can have a problem because there are non-ATGC
	    ## nt that produce can produce gaps in the alignment and the number
	    ## of those gaps are bigger than the sequence length. For those
	    ## cases Bio::Align::DNAStatistics could crash for some distance
	    ## methods. As easy solution it will skip the methods where 
	    ## gaps >= distance can give problems

	    my $length = $alignobj->length();
	    my $gaps = 0;
	    my @gapchars = ('.', '-');
	    my $gaptype = '-';  ## Dash by default

	    ## Count gaps

	    foreach my $seqobj ( $alignobj->each_seq() ) {
		my @seq = split(//, $seqobj->seq());
		foreach my $nt (@seq) {
		    foreach my $gapelem (@gapchars) {
			if ($nt eq $gapelem) {
			    $gaps++;
			    $gaptype = $gapelem;
			}
		    }
		}
	    }

	    my $skip_distance = 0;

	    ## Apply the filter for the failing distance methods

	    if (defined ($failing_gapmethod{$method})) {
		if ($gaps >= $length) {
		    $skip_distance = 1;
		}
	    }

	    if ($skip_distance == 0) {

		my $distmatrix = $align_stats->distance( -align  => $alignobj,
		                                         -method => $method,
		                                       );
		$dist{$cluster_id} = $distmatrix;
	    }
	}
    }
    $self->set_distances(\%dist);
}


=head2 run_bootstrapping

  Usage: $phygecluster->run_bootstrapping($args_href);

  Desc: Calculates the bootstrapping for a phygecluster object. It stores
        the bootstrapping alignments into the object, as a hash, key=cluster_id
        and value=array reference of alignments

  Ret: none (it loads %bootstrap as keys=cluster_id and value=array reference
      of alignments).

  Args: $args_href, a hash reference with the following options:
        datatype, permute, blocksize, replicates, readweights, readcat & quiet.
        (for more information: 
         http://evolution.genetics.washington.edu/phylip/doc/seqboot.html)
 

  Side_Effects: Died if the arguments are wrong.
                Skip the clusters that do not have any alignment
                

  Example: $phygecluster->run_bootstrapping(
                                             { 
                                               datatype   => 'sequences',
                                               replicates => 1000,
                                             }
                                           );

=cut

sub run_bootstrapping {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: No args. were supplied to run_bootstrapping()");
    
    ## Bootstrap tool uses the arguments as a array, so the argument checking
    ## also will change them to this format

    my %perm_args = (
	'datatype' => {
	    'Molecular sequences'               => 1, 
	    'Discrete morphological characters' => 1, 
	    'Restriction sites'                 => 1, 
	    'Gene frequencies'                  => 1,
	    'Sequence'                          => 1, 
	    'Morph'                             => 1,
	    'Rest.'                             => 1, 
            'Gene Freqs'                        => 1,
	}, 
	'permute'     => 'yes|no',
	'blocksize'   => 'int', 
	'replicates'  => 'int', 
	'readweights' => 'yes|no', 
	'readcat'     => 'yes|no', 
	'quiet'       => 'yes|no',
	);

    ## Checking args.

    my @bootstrargs = ();
    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Arg. supplied to run_bootstrapping() arent hashref");
    }
    else {
	foreach my $argkey (keys %{$args_href}) {
	    my $val = $args_href->{$argkey};
	    unless (exists $perm_args{$argkey}) {
		my $err = "ARG. ERROR: $argkey is not a permited arg. for ";
		$err .= "run_bootstrapping() function";
		croak($err);
	    }
	    else {
		if (ref($perm_args{$argkey}) eq 'HASH') {
		    my %perm_dt = %{$perm_args{$argkey}};
		    
		    unless (exists $perm_dt{$val}) {
			my $err1 = "ARG. ERROR: $val is not a permited value ";
			$err1 .= "for arg=$argkey with run_bootstrapping()";
			croak($err1);
		    }
		}
		else {
		    if ($perm_args{$argkey} eq 'int') {
			unless ($val =~ m/^\d+$/) {
			    my $err2 = "ARG. ERROR: $val for $argkey is not ";
			    $err2 .= "an integer for run_bootstrapping()";
			    croak($err2);
			}
		    }
		    else {
			unless ($val =~ m/^(yes|no)$/) {
			    my $err3 = "ARG. ERROR: $val for $argkey do not ";
			    $err3 .= "have yes|no val. for run_bootstrapping()";
			    croak($err3);
			}
		    }
		}
		push @bootstrargs, ($argkey, $val);
	    }
	}
    }

    ## Now it will get all the run_bootstrapping factory

    my $fact_boots = Bio::Tools::Run::Phylo::Phylip::SeqBoot->new(@bootstrargs);

    ## Define the hash to store the alignments

    my %bootstr = ();
    
    ## Get the alignments for each cluster and run bootstrapping

    my %clusters = %{$self->get_clusters()};
    foreach my $cluster_id (keys %clusters) {
	my $align = $clusters{$cluster_id}->alignment();
	if (defined $align) {
	    my $bootsalign_aref = $fact_boots->run($align); 
	    $bootstr{$cluster_id} = $bootsalign_aref;
	}
    }
    
    ## Finally it will load the data into the object

    $self->set_bootstrapping(\%bootstr);
}






######################
## PRUNE FUNCTIONS ###
######################


=head2 prune_by_align

  Usage: my %removed_clusters = $phygecluster->prune_by_align($arg_href)

  Desc: Remove sequence members and clusters that have not some conditions
        derived from the align object

  Ret: A hash with the sequencefamilies objects removed from the object 
       (key=cluster_id and value=Bio::Cluster::SequenceFamily object) 
       (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
       Bio::SimpleAlign objects)

  Args: A hash reference with the following parameters:
        { functionname => [ condition => integer ] }
        functionnames could be: score, length, num_residues, num_sequences
        or percentage_identity
        
  Side_Effects: Died if some of the parameters are wrong.
              
  Example:  $phygecluster->prune_by_align(
                             { num_sequences => ['<',4], 
                               length        => ['<', 100],
			     });


=cut

sub prune_by_align {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None args. were suplied to prune_by_align()");

    unless (ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: Argument used for prune_by_align is not hashref");
    }

    ## Check the arguments

    my %valid_args = (
	score               => 'ARRAY', 
	length              => 'ARRAY',  
	num_residues        => 'ARRAY', 
	num_sequences       => 'ARRAY',
        percentage_identity => 'ARRAY',
	);

    foreach my $argkey (keys %{$args_href}) {
	
	unless (exists $valid_args{$argkey}) {
	    my $err1 = "ARG. ERROR: $argkey is not valid key argument for ";
	    $err1 .= "prune_by_align() function";
	    croak($err1);
	}
	else {
	    my $argvar = $args_href->{$argkey};
	    unless (ref($argvar) eq $valid_args{$argkey}) {
		my $err2 = "ARG. ERROR: $argvar is not a valid value argument";
		$err2 .= " (an array ref.) for prune_by_align() function";
		croak($err2);
	    }
	}
    }

    ## Now it will check each condition for the arguments
    
    my %rmclusters = ();

    my %clusters = %{$self->get_clusters()};
    foreach my $clid (keys %clusters) {
	
	my $rmcluster = 0;
	my $seqfam = $clusters{$clid};
	my $align = $seqfam->alignment();
	
	if (defined $align) {
	    foreach my $function (keys %{$args_href}) {
		my $seqfam_value = $align->$function;
		my $condition = $args_href->{$function}->[0] || 
		    croak("ERROR: None condition was detailed for $function");
		my $filtvalue = $args_href->{$function}->[1] ||
		    croak("ERROR: None filter val. was detailed for $function");
	   
		unless ($filtvalue =~ m/^\d+$/) {
		    croak("ERROR: filter value $filtvalue is not an integer");
		}
		## Now it will detail the list of comparissons

		if ($condition eq '<') {
		    if ($seqfam_value < $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '<=') {
		    if ($seqfam_value <= $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '==') {
		    if ($seqfam_value == $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '>=') {
		    if ($seqfam_value >= $filtvalue) {
			$rmcluster = 1;
		    }
		}
		elsif ($condition eq '>') {
		    if ($seqfam_value > $filtvalue) {
			$rmcluster = 1;
		    }
		}
		else {
		    my $err3 = "ERROR: The condition $condition is not a valid";
		    $err3 .= " condition (<, <=, ==, >= or >)";
		    croak($err3);
		}	    
	    }
	}

	if ($rmcluster == 1) {
	    my $rmval = $self->remove_cluster($clid);
	    $rmclusters{$clid} = $rmval;
	}
    }
    return %rmclusters;
}


=head2 prune_by_strains

  Usage: my ($rm_clusters_href, $rm_members_href)
             = $phygecluster->prune_by_strains($args_href)

  Desc: Remove sequence members and clusters that have not some conditions
        derived from the strains of the sequences of the alignment

  Ret: A two hash references with:
       1) the sequencefamilies objects removed from the object 
          (key=cluster_id and value=Bio::Cluster::SequenceFamily object)
       2) the clusters with the list of members removed (array references)
          (also modify the PhyGeCluster, Bio::Cluster::SequenceFamily and 
          Bio::SimpleAlign objects)

  Args: A hash reference with:
        composition  => $href with key=strain, value=count
        min_distance => $aref_of_aref_pairs defining distances
        max_distance => $aref_of_aref_pairs defining distances
        
  Side_Effects: Died if some of the parameters are wrong.
              
  Example:  ## To get three sequences for strains A, B and C:
            $phygecluster->prune_by_strains({ 
                                             composition => {'A' => 1, 
                                                             'B' => 1, 
                                                             'C' => 1,
                                                            },
                                            });

            ## To get three sequences where A is close to B and C
            $phygecluster->prune_by_strains({ 
                                              composition => {'A' => 1, 
                                                              'B' => 1, 
                                                              'C' => 1,
                                                             },
                                              min_distance => [
                                                               ['A','B'],
                                                               ['A','C'],
                                                              ]
                                            });
              
            ## To get four sequences where A is close to B and C to D
            $phygecluster->prune_by_strains({
                                              composition => {'A' => 1, 
                                                              'B' => 1, 
                                                              'C' => 1,
                                                              'D' => 1,
                                                            },
                                              min_distance => [
                                                                ['A','B'],
                                                                ['C','D']
                                                              ]
                                            });
             ## To get five sequences A close to B, another A close to C, and
             ## a random D. A and A' should be close to
             $phygecluster->prune_by_strains({
                                        composition  => {'A' => 2, 
                                                         'B' => 1, 
                                                         'C' => 1,
                                                         'D' => 1,
                                                        },
                                        min_distance => [    
                                                          ['A','B'],
                                                          ['A','C'],
                                                          ['A','A'],
                                                        ]
                                        });

=cut

sub prune_by_strains {
    my $self = shift;
    my $args_href = shift ||
	croak("ARG. ERROR: None hash ref. argument was used prune_by_strains");

    ## Check the arguments
   
    unless(ref($args_href) eq 'HASH') {
	croak("ARG. ERROR: $args_href is not a hash ref. for prune_by_strains");
    }

    unless($args_href->{'composition'}) {
	croak("ARG. ERROR: No composition arg. was used for prune_by_strains");
    }

    my %valid_constr = ( composition  => 'HASH', 
		 	 min_distance => 'ARRAY', 
			 max_distance => 'ARRAY',
	);

    foreach my $constr (keys %{$args_href}) {
	unless (exists $valid_constr{$constr}) {
	    croak("ERROR: Constraint $constr does not avail. prune_by_strains");
	}
	else {
	    unless (ref($args_href->{$constr}) eq $valid_constr{$constr}) {
		croak("ERROR: Value $constr isnt $valid_constr{$constr} ref.");
	    }
	}
    }

    ## Define the variables that are going to store the removed clusters
    ## and the member removed from some clusters.

    my %rm_clusters = ();
    my %rm_members = ();

    ## Define composition hash and get the number of sequences expected
    
    my $expected_seq_n = 0;
    my %composition = %{$args_href->{'composition'}};
    foreach my $compmember (keys %composition) {
	$expected_seq_n += $composition{$compmember};
    }

    ## Check that exists strains

    my %strains = %{$self->get_strains()};

    my $strain_n = scalar(keys %strains);
    if ($strain_n < 1) {
	croak("ERROR: No strains were loaded into PhyGeCluster object.");
    }

    ## Get the distances
    
    my %dist = %{$self->get_distances()};
    my $dist_n = scalar(keys %dist);
    if ($dist_n < 1) {
	croak("ERROR: No distances were loaded into PhyGeCluster object.");
    }

    ## Now it will order the distances according each of the strains.

    my %clusters = %{$self->get_clusters()};
    foreach my $clid (keys %clusters) {
	
	## Get one new composition hash per cluster id
	my %cmp = %{$args_href->{'composition'}};

	my $seqfam = $clusters{$clid};
	
	## Define the array to select the seq_ids
	my %selected_mb = ();

	## Apply the selection if exists defined the distance

	my $distmx = $dist{$clid};
	if (defined $distmx) {

	    ## Now transform the distance matrix into a serie of
	    ## arrays for each strain pair with seqnames as elements

	    ## 1) Get the seq_ids by strains

	    my %strmemb = ();
	    my @seq_ids = @{$distmx->names()};
	    foreach my $seq_id (@seq_ids) {
		my $seqstr = $strains{$seq_id} ||
		    croak("ERROR: $seq_id has not strain defined");

		if (exists $strmemb{$seqstr}) {
		    push @{$strmemb{$seqstr}}, $seq_id;
		}
		else {
		    $strmemb{$seqstr} = [$seq_id]
		}
	    }

	    ## 2) Create the a hash with key=strain_pair_name and value
	    ##    hash reference with key=seq_pair and value=distance
	    ##    to be able to order the seqpairs by distances

	    my %pair_strains = ();
	    my %seqpair_names = ();
	    foreach my $strname1 (keys %strmemb) {
		foreach my $strname2 (keys %strmemb) {
		    
		    ## define the pair
		    my $strpair = $strname1 . ',' . $strname2;
		    my %seqpairs = ();
		    
		    ## get distances for each pair
		    foreach my $seqid1 (@{$strmemb{$strname1}}) {
			foreach my $seqid2 (@{$strmemb{$strname2}}) {
			    if ($seqid1 ne $seqid2) {
				my $dist_val = $distmx->get_entry( $seqid1, 
								   $seqid2 );

				my @seqpair = ($seqid1, $seqid2);
				my $seqpair_name = join('-', sort @seqpair);
				$seqpairs{$seqpair_name} = $dist_val;
				$seqpair_names{$seqpair_name} = \@seqpair;
			    }
			}
		    }
		    if (scalar(keys %seqpairs) > 0) {
			$pair_strains{$strpair} = \%seqpairs;
		    }
		}	    
	    }

	    ## 3) Use the defined constrains

	    foreach my $constrtype (keys %{$args_href}) {
		if ($constrtype =~ m/^m\w+_distance$/) {
		    my @constr = @{$args_href->{$constrtype}};
		    foreach my $pair_aref (@constr) {
			my $pair_name = join(',', @{$pair_aref});
			my $str1 = $pair_aref->[0];
			my $str2 = $pair_aref->[1];
			if (exists $pair_strains{$pair_name}) {
			    my %dp = %{$pair_strains{$pair_name}};

			    ## By default it will order as min, but if the
			    ## constraint is max_distance it will reverse the
			    ## list 

			    my @pairs = sort { $dp{$a} <=> $dp{$b} } keys %dp;
			    if ($constrtype =~ m/^max_distance$/) {
				@pairs = reverse(@pairs);
			    }
			    
			    ## Now it will get one pair and decrease the
			    ## composition
			
			    while($cmp{$str1} > 0 || $cmp{$str2} > 0) {
				my $pairname = shift(@pairs);
				if (defined $pairname) {
				    my @seqpair = @{$seqpair_names{$pairname}};
				    my $test = join(',', @seqpair);
				    my $new = 0;
				    my $singlenew = '';
				    foreach my $seqid (@seqpair) {
					unless (exists $selected_mb{$seqid}) {
					    $new++;
					    $singlenew = $seqid;
					}
				    }
				    if ($new == 2) {
					$selected_mb{$seqpair[0]} = 1;
					$selected_mb{$seqpair[1]} = 1;
					$cmp{$str1}--;
					$cmp{$str2}--;
				    }
				    elsif ($new == 1) {
					$selected_mb{$singlenew} = 1;
					$cmp{$strains{$singlenew}}--;
				    }
				}
				else {
				    $cmp{$str1}--;
				    $cmp{$str2}--;
				}
			    }
			}
		    }
		}
	    }

	    ## Finally it will get random sequences for each of the composition
	    ## seqids
	    
	    foreach my $cmp_strain (keys %cmp) {
		while ($cmp{$cmp_strain} > 0) {
	
		    if (defined $strmemb{$cmp_strain}) {
			foreach my $seq (@{$strmemb{$cmp_strain}}) {

			    my $seq_id = shift(@{$strmemb{$cmp_strain}});
			    if ($cmp{$cmp_strain} > 0) {
				unless (exists $selected_mb{$seq_id}) {
				    
				    $selected_mb{$seq_id} = 1;
				    $cmp{$cmp_strain}--;		
				}
			    }
			}
			if (scalar(@{$strmemb{$cmp_strain}}) == 0) {
			    $cmp{$cmp_strain} = 0;
			}
		    }
		    else {
			$cmp{$cmp_strain} = 0;
		    }		    		
		}	    
	    }
	}

	## Now with the selected_mb strain it will remove the members 
	## and strains that are not in the list
	
	## 0) Check if it has all the sequences that it should have.
	##    If it has the requested number it will remove the members
	##    not selected, if it has not, it will remove the SequenceFamily
	##    objects from PhyGeCluster
	   
	if (scalar(keys %selected_mb) == $expected_seq_n) {

	    my @rm_members = ();

	    ## 1) Remove from the alignment
	    
	    my $align = $seqfam->alignment();
	    if (defined $align) {
		foreach my $alignmember ( $align->each_seq() ) {
		    my $member_id = $alignmember->display_id();
		    unless (exists $selected_mb{$member_id}) {
			$align->remove_seq($alignmember);
		    }
		}
	    }

	    ## 2) Remove from the SequenceFamily object

	    my @fam_members = $seqfam->get_members();

	    ## SequenceFamily object has not a function to remove 
	    ## members one by one, it remove all the members, so
	    ## this code will add the selected members to the object
	    ## after the removing of all the members
	    
	    $seqfam->remove_members();

	    foreach my $fam_member (@fam_members) {
		my $fmember_id = $fam_member->display_id();
		unless (exists $selected_mb{$fmember_id}) {
		    push @rm_members, $fmember_id;
		}
		else {
		    $seqfam->add_members([$fam_member]);
		}
	    }
	    $rm_members{$clid} = \@rm_members;
	}
	else {
	    my $cluster_removed = $self->remove_cluster($clid);
	    $rm_clusters{$clid} = $cluster_removed;
	}
    }

    return (\%rm_clusters, \%rm_members);
}


####
1; #
####
