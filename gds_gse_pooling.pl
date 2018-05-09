#!/usr/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
################################################################
#
# Script Title: gds_gse_pooling.pl
# Author: Faisal Ibne Rezwan
# Description: This script generated a pool between
#              corrosponding Series(GSE) and DataSet(GDS) accession
#
# $Id: gds_gse_pooling.pl 3773 2008-01-30 08:45:54Z rayner $
#
################################################################

use strict;
use warnings;

use LWP::Simple;
use Benchmark;

use Getopt::Long;
use Log::Log4perl qw(:easy);

# Format for log statements
Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my $outfile;

GetOptions( "o|output=s" => \$outfile );

unless ($outfile) {
	print <<"USAGE";

    Usage: $0 -o <output file>

USAGE

	exit 255;
}

my $starttime = new Benchmark;

my $utils = "http://www.ncbi.nlm.nih.gov/entrez/eutils";

#Do the esearch on query string and get total number of DataSets(GDS)
my $esearch =
  "$utils/esearch.fcgi?db=gds&retmax=1&usehistory=y&term=%22gds%22[Entry%20Type]";

INFO "Running search: $esearch";
my $esearch_result = get($esearch);

$esearch_result =~ m|<Count>(\d+)</Count>|s;

my $count = $1;

INFO "Total number of GDS: $count";

#Do the esearch on query string to get all the GDS ID
$esearch =
  "$utils/esearch.fcgi?db=gds&usehistory=y&retmax=$count&term=%22gds%22[Entry%20Type]";
INFO "Running search: $esearch";
my $e_result = get($esearch);
my @line     = split( '\n', $e_result );

my @id;

foreach my $line (@line) {
	if ( $line =~ /<Id>(\d+)<\/Id>/ ) { push( @id, $1 ); }
}

my $total_gds = 0;
my $gds_gse_table;
my $table_length = 0;
my ( $i, $j, $ptr, $match );

foreach my $s_id (@id) {

	#Do the efetch to fetch data for specific GDS ID
	my $efetch =
"http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=gds&id=$s_id&mode=htmlt&report=docsum";
	my $efetch_result = get($efetch);

	#Make a GSE table with its corrosponding GDS
	if ( $efetch_result =~ /Series: GSE(.\d+)/ ) {

		$match = 0;
		for ( $i = 0 ; $i < $table_length ; $i++ ) {

			if ( $gds_gse_table->[$i]->[0] == $1 ) {
				$gds_gse_table->[$i]->[1]    = $gds_gse_table->[$i]->[1] + 1;
				$ptr                         = $gds_gse_table->[$i]->[1] + 1;
				$gds_gse_table->[$i]->[$ptr] = $s_id;
				$match                       = 1;
			}

		}
		if ( $match == 0 ) {
			$gds_gse_table->[$i]->[0] = $1;
			$gds_gse_table->[$i]->[1] = ( $gds_gse_table->[$table_length]->[1] || 0 ) + 1;
			$ptr                      = $gds_gse_table->[$i]->[1] + 1;
			$gds_gse_table->[$i]->[$ptr] = $s_id;
			$table_length = $i + 1;

		}

	}

}

INFO "Writing to the gse to gds output file";

open( my $out_fh, '>', $outfile ) or LOGDIE("Unable to open $outfile: $!");
for ( $i = 0 ; $i < $table_length ; $i++ ) {
	my $length = $gds_gse_table->[$i]->[1] + 2;

	for ( $j = 0 ; $j < $length ; $j++ ) {
		print $out_fh "$gds_gse_table->[$i]->[$j]\t";
	}
	print $out_fh "\n";
}

close($out_fh) or die($!);

my $endtime = new Benchmark;

my $timediff = timediff( $endtime, $starttime );
INFO "Total Run Time: ", timestr($timediff);

