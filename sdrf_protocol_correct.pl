#!/usr/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

=head1 NAME

sdrf_protocol_correct.pl
 
=head1 DESCRIPTION

This script is meant to be run over a MAGE-TAB SDRF. The script was created 
so it could be called after the import and conversion of a GEO soft file 
to MAGE-TAB. The aim of this script is to find duplicate Protocol REF 
columns and merge them.

=head1 SYNOPSIS
	
 perl sdrf_protocol_correct.pl -i GSE7060.idf.txt -s GSE7060.hyb.sdrf.txt

=head1 AUTHOR

Emma Hastings , <emma@ebi.ac.uk>

Created MAR 2012
 
=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010 European Bioinformatics Institute. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it 
under GPLv3.

This software is provided "as is" without warranty of any kind.

=cut

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Log::Log4perl qw(:easy);
use File::Copy;
use EBI::FGPT::Common qw(date_now);
use Data::Dumper;
use List::MoreUtils qw(uniq);
use File::Temp qw/ tempfile tempdir /;

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my $current_date_time = date_now();
my $idf               = "";
my $sdrf              = "";
my @col;
my @row;
my $cell = "";
my $help = 0;

GetOptions(
	"i=s" => \$idf,
	"s=s" => \$sdrf,
	"h"   => \$help
);

if ($help) {
	print "Input= idf Options:   -i  idf  file \n";
	print "Input= sdrf Options:   -s  sdrf  file \n";
	exit;
}

if ( ( $idf eq "" ) && ( $sdrf eq "" ) ) {
	LOGDIE " You must provide a idf and sdrf file using the -i and -s option\n";
	exit;
}

open my $idf_fh, "<", "$idf";
if ( !open $idf_fh, $idf ) {
	LOGDIE "cannot access file:$!";
}

#Read in IDF file
INFO "Reading IDF file to check protocol types";

my @prot_name;
my @prot_type;
my %protocol_hash;
while (<$idf_fh>) {
	chomp;

	if ( $_ =~ /^Protocol Name/ ) {
		@prot_name = split("\t");
	}

	if ( $_ =~ /^Protocol Type/ ) {

		@prot_type = split("\t");
	}

}

# Creates hash where accession is the key and type is the value
my $i;
for ( $i = 1 ; $i < @prot_type ; $i++ ) {
	$protocol_hash{ $prot_name[$i] } = $prot_type[$i];
}

my $no_duplicate = 0;
my ( %reverse, $key, $value );
while ( ( $key, $value ) = each %protocol_hash ) {
	push @{ $reverse{$value} }, $key;
}

while ( ( $key, $value ) = each %reverse ) {

	if ( @$value > 1 ) {
		INFO "More than 1 protocol of the same type found- attempting to merge";
		$no_duplicate = 1;
		last;
	}
}

if ( $no_duplicate != 1 ) {
	INFO "No consecutive Protocol REF columns found- script not required";
	exit 0;
}

# Read in SDRF file and split based on tabs
open my $sdrf_fh, "<", "$sdrf";
if ( !open $sdrf_fh, $sdrf ) {
	LOGDIE "cannot access file:$!";
}

# Creates date stamped copy of SDRF
copy( $sdrf, "$sdrf" . "_" . $current_date_time );
if ( !copy( $sdrf, "$sdrf" . "_" . $current_date_time ) ) {
	print "File " . $sdrf . " cannot be copied: $!";
}

# File to write out corrected SDRF to
my $template = "sdrf_file.txtXXXX";
my ( $tmp_sdrf_fh, $tmp_filename ) = tempfile( $template, UNLINK => 1 );

open $tmp_sdrf_fh, ">", "$tmp_filename";
if ( !open $tmp_sdrf_fh, ">$tmp_filename" ) {
	LOGDIE "cannot access file:$!";
}

INFO "Reading SDRF";

while (<$sdrf_fh>) {
	chomp;
	@col = split("\t");
	push @row, [@col];
}

# Records size of SDRF and stores first line of SDRF

my $number_of_rows    = @row;
my @header            = @{ $row[0] };
my $number_of_columns = @header;

my $row_number = 1;
my %hash_of_headers_colnum;
my $col_number = 0;

# Creates a hash of arrays where each key is a column header
# and each value is an array containing the column number where
# it has seen that header. Will use this when printing back out
# the corrected SDRF

foreach my $x (@header) {

	if ( exists $hash_of_headers_colnum{$x} ) {
		push @{ $hash_of_headers_colnum{$x} }, $col_number;
	}

	else {
		my @col_pos;
		push @col_pos, $col_number;
		$hash_of_headers_colnum{$x} = [@col_pos];

	}

	$col_number++;
}

# Creates a hash of hashes that contains our source
# and all associated protocols and types

$row_number = 1;
$col_number = 0;
my %source_protocol;

while ( $row_number < $number_of_rows ) {

	my @line = @{ $row[$row_number] };

	my $sample_value = $row[$row_number][$col_number];

	foreach $cell (@line) {
		if ( $cell =~ /^P-/ ) {
			my $type = $protocol_hash{$cell};
			$source_protocol{$sample_value}{$type} = $cell;
		}
	}

	$row_number++;
}

# Need to create a new header for our SDRF.
# This method reads through file and if it sees a
# Protocol REF column that has a blank in the first line
# it does not place it in the new header as it is most
# likely an unnecessary column.

$row_number = 0;
$col_number = 0;
my @new_header;
my @protocol_check;

my @line = @{ $row[$row_number] };

foreach my $cell (@line) {
	my $value = $row[ $row_number + 1 ][$col_number];
	if ( $cell !~ /^Protocol REF/ ) {
		push @new_header, $cell;
	}

	else {
		if ( $value ne "" ) {
			push @new_header,     $cell;
			push @protocol_check, $cell;
		}

	}
	$col_number++;

}

# Added this check so we can ensure we have the right amount of Protocol Ref
# columns. If we do we proceed otherwise something has gone wrong and we leave well alone.

my @type_array;
for my $key ( keys %protocol_hash ) {
	my $type_value = $protocol_hash{$key};
	push @type_array, $type_value;
	@type_array = uniq(@type_array);
}

if ( @type_array == @protocol_check ) {
	INFO "Creating new Protocol REF column layout";
}

else {
	close $tmp_sdrf_fh;
	LOGDIE "Attempt to merge protocol columns had failed";
	exit 0;
}

#Prints out first row of SDRF
INFO "Creating SDRF header";
my $new_header = join( "\t", @new_header );
print $tmp_sdrf_fh $new_header;
print $tmp_sdrf_fh "\n";

#Prints out rest of SDRF
INFO "Populating SDRF columns";
$row_number = 1;
$col_number = 0;
my $sample_value;
my $protocol_accession;

#This ensures we print the protocols in the right order
my @protocol_order = (
	"growth protocol",
	"sample treatment protocol",
	"nucleic acid extraction protocol",
	"nucleic acid library construction protocol",
	"labelling protocol",
	"hybridization protocol",
	"array scanning protocol",
	"normalization data transformation protocol"
);

my @new_order;
foreach my $order (@protocol_order) {
	foreach my $prot_type (@prot_type) {
		if ( ( $prot_type ne "Protocol Type" ) && ( $prot_type eq $order ) ) {
			push @new_order, $prot_type;

		}
	}
}

#This will act as a guide for printing the protocols
@new_order = uniq(@new_order);

while ( $row_number < $number_of_rows ) {

	my @line               = @{ $row[$row_number] };
	my %temp_hash          = %hash_of_headers_colnum;
	my $protocol_index     = 0;
	my $final_column_index = $number_of_columns - 1;

	foreach my $new_header (@new_header) {

		#This array will store the column position
		my @colpos_array = @{ $temp_hash{$new_header} };

		#Get source value so we can find all associated protocols
		if ( $new_header =~ /^Source Name/ ) {
			$sample_value = $row[$row_number][$col_number];
		}

		if ( $new_header =~ /^Protocol REF/ && $protocol_index < @new_order ) {

			my $type = $new_order[$protocol_index];

			if ( exists $source_protocol{$sample_value}{$type} ) {

				$protocol_accession = $source_protocol{$sample_value}{$type};
				print $tmp_sdrf_fh $protocol_accession . "\t";

			}

			else {
				print $tmp_sdrf_fh "\t";
			}
			$protocol_index++;

		}

		#Print out rest of SDRF and avoid adding a tab to the last value in a row
		if ( $new_header !~ /^Protocol REF/ ) {

			if ( @colpos_array >= 1 ) {

				if (   ( $colpos_array[0] == $final_column_index )
					&& ( defined $line[ $colpos_array[0] ] ) )
				{
					print $tmp_sdrf_fh $line[ $colpos_array[0] ];
				}

				elsif ( defined $line[ $colpos_array[0] ] ) {
					print $tmp_sdrf_fh $line[ $colpos_array[0] ] . "\t";
				}

				else {

					# Case where we have a blank final value
					# and its not in the last column of the SDRF
					if ( !$line[ $colpos_array[0] ]
						and $colpos_array[0] != $final_column_index )
					{
						print $tmp_sdrf_fh "\t";
					}
				}

				shift(@colpos_array);
				$temp_hash{$new_header} = [@colpos_array];

			}
		}

	}
	$row_number++;
	print $tmp_sdrf_fh "\n";
}

rename( $tmp_filename, $sdrf );
close $idf_fh;
close $sdrf_fh;
close $tmp_sdrf_fh;

