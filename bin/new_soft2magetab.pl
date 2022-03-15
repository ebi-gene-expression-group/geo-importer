#!/usr/bin/env perl

################################################################
#
#
# $Id: new_soft2magetab.pl 19502 2012-03-29 08:36:28Z emma $
#
################################################################

use strict;
use warnings;

# Next line is a placeholder. Uncomment and edit as necessary, or set PERL5LIB environmental variable
# use lib /path/to/directory/containing/Curator/modules;

use EBI::FGPT::Converter::GEO::SOFTtoMAGETAB;
use EBI::FGPT::Config qw($CONFIG);
use Getopt::Long;
use File::Spec;
use Bio::MAGETAB::TermSource;
use Log::Log4perl;
use Data::Dumper;
use File::Spec;
use File::Basename;

# Absolute directory path to the file storage
my $abs_path = dirname(File::Spec->rel2abs(__FILE__));

my ( $soft, $target, $data, $skip_data, $gse_acc, $efo_mapping, $help );

GetOptions(
	"s|soft=s"    => \$soft,
	"a|gse_acc=s" => \$gse_acc,
	"t|target=s"  => \$target,
	"d|data=s"    => \$data,
	"x|skip_data" => \$skip_data,
	"e|efo_mapping" => \$efo_mapping,
	"h|help"      => \$help,
);
my $usage = <<END;

    Usage: new_soft2magetab.pl -s GSE1234.soft.txt -t target_dir -d data_dir
    
    or:    new_soft2magetab.pl -a GSE1234 -t target_dir -d data_dir
    
    Use -x to skip download of supplementary data files (filename will still be included in SDRF)

    Use -e for mapping factor values with EFO terms (EFO terms be included in SDRF)
    
    If -a (accession) is used the SOFT file for this GSE accession will be downloaded from NCBI to the
    target directory.
    
    The MAGETAB idf file named GSExxxx.idf.txt is written to the target directory
    
    The sdrfs and data files are written to the data directory
    
    All hybridizations are written to GSExxxx.hyb.sdrf.txt
    
    All assays (GEO samples linked to 'virtual' platforms, e.g. UHTS) are written to GSExxxx.assay.sdrf.txt
    
END

if ($help) {
	print $usage;
	exit;
}

# Initialize Logger
my $log_conf = q(
	log4perl.category.SOFT              = INFO, LOG1
	log4perl.appender.LOG1           = Log::Log4perl::Appender::File
	log4perl.appender.LOG1.filename  = sub { return get_log_fn(); }
	log4perl.appender.LOG1.mode      = clobber
	log4perl.appender.LOG1.layout    = Log::Log4perl::Layout::PatternLayout
	log4perl.appender.LOG1.layout.ConversionPattern = %d %p %m %n
);
Log::Log4perl::init( \$log_conf );

my $logger = Log::Log4perl::get_logger("SOFT");

if ($skip_data) {
	$logger->warn("Skipping download of data files");
}


my $converter;

if ( $efo_mapping ) {

	require EBI::FGPT::FuzzyRecogniser;

    my ( $term_mapper, $term_source );
	my $efo = $CONFIG->get_EFO_OWL_FILE;

	# Make the term mapper and term source objet
    $term_mapper = EBI::FGPT::FuzzyRecogniser->new( owlfile => $efo );
	$term_source = Bio::MAGETAB::TermSource->new(
		{
			name => "EFO",
			uri  => $CONFIG->get_EFO_LOCATION,
		}
	);

	$converter = EBI::FGPT::Converter::GEO::SOFTtoMAGETAB->new(
		{
			soft_path     => $soft,
			acc           => $gse_acc,
			target_dir    => $target,
			data_dir      => $data,
			gse_gds_file  => $CONFIG->get_GSE_GDS_MAP,
			gpl_acc_file  => $CONFIG->get_GEO_PLATFORM_MAP,
			skip_download => $skip_data,
			ena_acc_file  => $CONFIG->get_ENA_ACC_MAP,
			term_mapper   => $term_mapper,
			term_source   => $term_source
		}
	);
}

else {
	$converter = EBI::FGPT::Converter::GEO::SOFTtoMAGETAB->new(
		{
			soft_path     => $soft,
			acc           => $gse_acc,
			target_dir    => $target,
			data_dir      => $data,
			gse_gds_file  => $CONFIG->get_GSE_GDS_MAP,
			gpl_acc_file  => $CONFIG->get_GEO_PLATFORM_MAP,
			skip_download => $skip_data,
			ena_acc_file  => $CONFIG->get_ENA_ACC_MAP
		}
	);
}

$converter->parse_soft;

# Calls method to prevent duplicate Characteristic[] cols
$converter->normalize_chars;

$logger->info("Writing MAGE-TAB");
$converter->write_magetab("merged");

# Nasty hack to change date formats for release date
my $idf_path = File::Spec->catfile( $target, $converter->get_acc . ".merged.idf.txt" );
my @args = ( 'perl', '-i', '-pe', 's/([\d]{4}-[\d]{2}-[\d]{2})T.*/$1/g', $idf_path );
$logger->info("Fixing date format in IDF: @args");
system(@args) == 0
	or $logger->error("Could not fix date formats in IDF");

# This is required to remove any quotes around values in IDF-
# no idea where these quotes come from
# suspect its a windows thing
system( 'perl', '-i', '-pe', 's/"//g', $idf_path ) == 0
	or $logger->warn("Could not remove quotes within IDF");

## Tidy up SDRF
my @sdrf_type = ( ".hyb.sdrf.txt", ".assay.sdrf.txt", ".seq.sdrf.txt" );
foreach my $sdrf_type (@sdrf_type) {

	my $sdrf_path = File::Spec->catfile( $data, $converter->get_acc . $sdrf_type );

	#Checks file exists
	if ( -e $sdrf_path ) {

		#This is required to remove any quotes around values
		system( 'perl', '-i', '-pe', 's/"//g', $sdrf_path ) == 0
			or $logger->warn("Could not remove quotes within sdrf");

		system( 'perl', '-i', '-pe', 's/file://g', $sdrf_path ) == 0
			or $logger->warn("Could not remove file: prefix from file names in SDRF");

		my @sdrf_args = (
			"$abs_path/sdrf_protocol_correct.pl",
				, '-i', $idf_path, '-s', $sdrf_path
		);
		$logger->info("Running sdrf_protocol_correct over SDRF: @sdrf_args");

		system(@sdrf_args) == 0
			or $logger->logwarn("Running sdrf_col_correct.pl");

		#Remove consecutive 'Term Source REF' columns
		@sdrf_args = (
			"$abs_path/sdrf_termsource_correct.pl",
				'-s', $sdrf_path
		);
		$logger->info("Running sdrf_termsource_correct over SDRF: @sdrf_args");

		system(@sdrf_args) == 0
			or $logger->logwarn("Running sdrf_termsource_correct.pl");

	}

}

=head2 get_log_fn

Return Logfilename for this script. It is the  path to the target dir 
plus the accession with a ".txt" ending.

=cut

sub get_log_fn {
	my $log;

	if ($gse_acc) {
		$log = File::Spec->catfile( $target, $gse_acc . "_import.log" );
	}

	else {
		$log = File::Spec->catfile( $target, "import.log" );
	}

	return $log;
}


