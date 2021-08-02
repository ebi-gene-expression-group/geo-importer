#!/usr/bin/env perl
#
# Modified Suhaib Mohammed to import GEO expeiments and not submit in submission tracking database.

# Script to use Faisal Ibne Rezwan's GEOImport code to insert new GEO
# experiments into the submissions tracking system.
#
# $Id: import_geo_subs.pl 2350 2010-10-11 10:49:30Z farne $

# Next line is a placeholder. Uncomment and edit as necessary, or set PERL5LIB environmental variable
# use lib /path/to/directory/containing/Curator/modules;

$| = 1;

use strict;
use warnings;

use Archive::Extract;
use File::Spec;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use Getopt::Long;
use LWP::Simple qw($ua getstore is_success is_error);
use IO::CaptureOutput qw(capture);

use EBI::FGPT::Resource::Database;
use EBI::FGPT::Config qw($CONFIG);
use ArrayExpress::AutoSubmission::DB::Experiment;
use ArrayExpress::AutoSubmission::Creator;
use EBI::FGPT::Common qw(date_now);

# Absolute directory path to the file storage 
my $abs_path = dirname(File::Spec->rel2abs(__FILE__));

# Set up log4perl
use Log::Log4perl;

my $conf = q(
log4perl.rootLogger              = INFO, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d %p %m %n
  );

Log::Log4perl::init( \$conf );
my $logger = Log::Log4perl->get_logger();

if ( my $proxy = $CONFIG->get_HTTP_PROXY )
{
	$ua->proxy( ['http'], $proxy );
}

sub check_env_var {
  my $var = shift;
  my $suggestion = shift;

  unless(defined $ENV{$var}) {
    $logger->error( "Please define $var env var" );
    $logger->info( "Usually for $var: $suggestion" ) if(defined $suggestion);
    exit 1;
  }
}

check_env_var('FASTQ_FILE_REPORT');


########
# MAIN #
########

my ( $listfile, $set_curator, $skip_download, $validate, $efo_mapping, $ena_mapping, $output_dir );

GetOptions(
			"f|file=s"       => \$listfile,
			"c|curator:s"     => \$set_curator,
			"x|skip_download" => \$skip_download,
			"v|validate"      => \$validate,
			"e|efo_mapping"   => \$efo_mapping,
			"n|ena_mapping"   => \$ena_mapping,
			"o|output_dir=s"  => \$output_dir,
);

unless ($listfile && $output_dir)
{
	print(<<"USAGE");

    Usage: $0 -f <file listing GEO subs> -o <absolute path to output directory>

  The file should contain five columns, in tab-delimited text format:

 1. GSE accession (including GSE prefix),
 2. Species, separated by semicolons in multi-species experiments (optional),
 3. Number of hybridizations (optional).
 4. Release date (optional)
 5. Has GDS flag: 1=has accociated GDS, 0 or null=does not have GDS
 6. Use native datafiles flags: 1 = data files should be kept in their native format during processing
                                0 or null = data files will be parsed during processing

     Lines beginning with # are treated as comments. Processing of
     the list will finish on the first empty line.

   Optional arguments:

     -c :   Set the curator field for the imported experiments. Using the
              -c argument alone will set the experiment's curator to your
              current unix login; override this by supplying the desired
              curator name, e.g. "-c my_curator_name". Most of the time
              this option is superfluous. It is only useful if the downstream
              processing of the experiment depends on the curator value
              (usually this is not the case).
              
     -x :   skip download of supplementary data files (filename will still be included in SDRF)

     -n :   use this flag to download fastq file report from ena
     
     -v :  Use this flag if you just want to validate files after importing
              and do not want to run the usual checking and export,
              e.g. if rerunning import to add ENA accessions, or for AE2 loading.

     -e : Use this flag if the the factor values needs mapping with EFO terms and populate in SDRF column.                

USAGE

	exit 255;
}

open( my $list_fh, '<', $listfile )
  or $logger->logdie("Unable to open file $listfile: $!");


# Import the ontology file for annotation step, 
if ($efo_mapping)
{

	my $EFO_LOCATION = $CONFIG->get_EFO_LOCATION;

	$logger->info("Downloading ontology file from $EFO_LOCATION");
	my $ontology_file = $CONFIG->get_EFO_OWL_FILE;
	my $return_code = getstore( $EFO_LOCATION, $ontology_file );
	unless ( is_success($return_code) )
	{
		$logger->logdie("Error getting EFO from $EFO_LOCATION: $return_code ($!)");
	}
	$logger->info("Done");
}

# Download latest version of ENA accession map file
if ($ena_mapping)
{
	my $map_path = $CONFIG->get_ENA_ACC_MAP;
	my $download_from = $ENV{'FASTQ_FILE_REPORT'};
	$logger->info("Downloading $download_from");
	my $rc = getstore( $download_from, "$map_path.gz" );
	if ( is_error($rc) )
	{
		$logger->logdie("Could not download $download_from: $rc");
	}
	$logger->info("Done");

	$logger->info("Extracting $map_path.gz");
	my $archive = Archive::Extract->new( archive => "$map_path.gz" );
	$archive->extract( to => $map_path );
	$logger->info("Done");

}

my @failed_lines;
LINE:
while ( my $line = <$list_fh> )
{

	chomp $line;

	# Skip commented-out lines.
	next LINE if ( $line =~ /^\#/ );

	# End on a blank line.
	last LINE if ( $line =~ /^\s*$/ );

	my ( $accn, $species, $hybs, $date, $has_gds, $use_native_files ) = split /\t/, $line;

	$logger->info("Processing $accn");

	my @species_list;

	if ($species)
	{
		@species_list = split / *; */, $species;
	}

	my $target_dir =
	  File::Spec->catdir( $output_dir, "${accn}_output" );
	unless ( -e $target_dir )
	{
		mkpath($target_dir)
		  or $logger->logdie("Could not make directory $target_dir - $!");
	}

	my $data_dir = File::Spec->catdir( $target_dir, "supplementary_files" );
	unless ( -e $data_dir )
	{
		mkpath($data_dir)
		  or $logger->logdie("Could not make data directory $data_dir- $!");
	}

	my $command =
	  ( "$abs_path/new_soft2magetab.pl"
		. " -a $accn" . " -t "
		. $target_dir . " -d "
		. $data_dir );

	if ($skip_download)
	{
		$command =
		  ( "$abs_path/new_soft2magetab.pl"
			. " -a $accn" . " -t "
			. $target_dir . " -d "
			. $data_dir . " -x " );
	}

	if ($efo_mapping)
	{
		$command =
		  ( "$abs_path/new_soft2magetab.pl"
			. " -a $accn" . " -t "
			. $target_dir . " -d "
			. $data_dir . " -x " . " -e " );
	}

	my ( $stdout, $stderr, $rc );
	capture sub {
		$rc = system($command );
	  } => \$stdout,
	  \$stderr;

	# Make AE accession string
	my $ae_acc = $accn;
	$ae_acc =~ s/GSE/E-GEOD-/g;
	my ( $FAIL, $spreadsheet, @filelist );

	my $is_merged;

	if ( $rc != 0 )
	{
		$logger->error("Error downloading $accn: $stderr");

		# Set fail flag
		$FAIL        = 1;
		$spreadsheet = "$accn.idf.txt";

		# Store it for writing to list of fails for rerun
		push @failed_lines, $line;
	}
	else
	{

		$spreadsheet = File::Spec->catfile( $target_dir, "$accn.merged.idf.txt" );

		# Copy contents of IDF and SDRF into single file for easier curation
		# (unless there are multiple sdrfs)
		my $merged = $spreadsheet . ".merged";
		open( my $target_fh, ">", $merged )      or die $!;
		open( my $idf_fh,    "<", $spreadsheet ) or die $!;
		my @sdrfs;
		my @sdrf_cells;

		print $target_fh "[IDF]\n";
		while ( my $line = <$idf_fh> )
		{
			if ( $line =~ /^\"?SDRF\s*File\"?\t(.*)/gixms )
			{
				my $sdrf_string = $1;
				chomp $sdrf_string;
				@sdrf_cells = split /\t/, $sdrf_string;
			}
			else
			{
				print $target_fh $line;
			}
		}
		close $idf_fh;

		# Remove empty cells
		@sdrfs = grep { $_ ne "" } @sdrf_cells;

		# If skipping supplementary file download the remove .gz manually
		if ($skip_download)
		{
			foreach my $file (@sdrfs)
			{
				$file =~ s/file://g;
				my $sdrf_path = File::Spec->catfile( $data_dir, $file );
				my $command =
				  ( "perl -i -pe " . " 's/(?<!fastq)\.gz//g' " . $sdrf_path );
				system($command);
			}
		}

		if ( @sdrfs > 1 )
		{
			$logger->warn("More than 1 SDRF listed in $spreadsheet, not merging");
			close $target_fh;
			unlink $merged;
			$is_merged = 0;
		}
		else
		{
			my $sdrf_path = $sdrfs[0];
			$sdrf_path =~ s/file://g;
			$sdrf_path = File::Spec->catfile( $data_dir, $sdrf_path );

			$logger->info("Merging $spreadsheet and $sdrf_path into single file");
			open( my $sdrf_fh, "<", $sdrf_path ) or die $!;
			print $target_fh "\n[SDRF]\n";
			while ( my $line = <$sdrf_fh> )
			{
				print $target_fh $line;
			}
			close $target_fh;
			close $sdrf_fh;
			move( $merged, $spreadsheet ) or die $!;
			unlink($sdrf_path);
			$is_merged = 1;
		}

		# Make list of data files to include
		opendir( my $dir, $data_dir ) or $logger->logdie("Error opening $data_dir: $!");
		@filelist = map { File::Spec->catfile( $data_dir, $_ ) }
		  grep { $_ !~ /^\./ } readdir($dir);
		closedir $dir;
	}

	# Remove all the 'soft' files when everything is done
	find({ wanted => \&rm_soft, no_chdir=>1}, $target_dir);
}

close($list_fh);

# Add failed lines to file for rerunning
if (@failed_lines)
{
	my $fail_file = $listfile . ".fails";
	$logger->error("Some imports failed. See $fail_file for the list of failed imports");
	open( my $fh, ">", $fail_file )
	  or $logger->logdie("Error: could not open $fail_file for writing - $!");
	print $fh join "\n", @failed_lines;
	close $fh;
}

sub rm_soft
{
	my $F = $File::Find::name;

	if ($F =~ /soft$/ )
	{
		print "$F will be removed\n";
		unlink $F;
	}
}
