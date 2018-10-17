#!/usr/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell

=head1 NAME

sdrf_termsource_correct.pl
 
=head1 DESCRIPTION

This script is meant to be run over a MAGE-TAB SDRF. The script was created 
so it could be called after the import and conversion of a GEO soft file 
to MAGE-TAB. The aim of this script is to find duplicate Term Source REF 
columns and merge them.

=head1 SYNOPSIS
	
 perl sdrf_protocol_correct.pl -s GSE7060.hyb.sdrf.txt

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

use Getopt::Long;
use Log::Log4perl qw(:easy);
use File::Copy;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use File::Temp qw/ tempfile tempdir /;

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my $sdrf = "";
my @col;
my @row;
my $cell = "";
my $help = 0;

GetOptions(
	"s=s" => \$sdrf,
	"h"   => \$help
);

if ($help) {
	print "Input= sdrf Options:   -s  sdrf  file \n";
	exit;
}

if ( $sdrf eq "" ) {
	LOGDIE " You must provide an sdrf file using the -s option\n";
	exit;
}

open my $sdrf_fh, "<", "$sdrf";
if ( !open $sdrf_fh, $sdrf ) {
	LOGDIE "cannot access file:$!";
}

#File to write out corrected SDRF to
my $template = "sdrf_file.txtXXXX";
my ( $tmp_sdrf_fh, $tmp_filename ) = tempfile( $template, UNLINK => 1 );

open $tmp_sdrf_fh, ">", "$tmp_filename";
if ( !open $tmp_sdrf_fh, ">$tmp_filename" ) {
	LOGDIE "cannot access file:$!";
}

#Read in SDRF file and split based on tabs
INFO "Reading SDRF";

my $no_duplicate = 0;
while (<$sdrf_fh>) {

	if ( $_ =~ /Protocol REF\tTerm Source REF\tTerm Source REF/i ) {
		INFO "Consecutive Term Source REF columns found";
		$no_duplicate = 1;
	}

	chomp;
	@col = split("\t");
	push @row, [@col];

}

# If there are no consecutive Term Source REF columns then do not carry on
# running the script
if ( $no_duplicate != 1 ) {
	INFO "No consecutive Term Source REF columns found";
	exit 0;
}

#Records size of SDRF and stores first line of SDRF
my $number_of_rows    = @row;
my @header            = @{ $row[0] };
my $number_of_columns = @header;

my %hash_of_headers_colnum = create_hash_of_headers_colnum(@header);

#Need to create a new header for our SDRF.
my @new_header = create_new_header(@header);

#Prints out first row of SDRF
INFO "Creating SDRF header";
my $new_header = join( "\t", @new_header );
print $tmp_sdrf_fh $new_header;
print $tmp_sdrf_fh "\n";

#Prints out rest of SDRF
INFO "Populating SDRF columns";
my $row_number = 1;
my $col_number = 0;

# To print the SDRF we need to walk through each row
# and print values according to the layout of the new header
while ( $row_number < $number_of_rows ) {

	my @line               = @{ $row[$row_number] };
	my %temp_hash          = %hash_of_headers_colnum;
	my $protocol_index     = 0;
	my $final_column_index = $number_of_columns - 1;
	my $have_seen_prot     = "";

	foreach my $new_header (@new_header) {

		# This array will store the column position and allows
		# us to print column values in the right position
		my @colpos_array = @{ $temp_hash{$new_header} };

		# If we have a Term Source REF following a Protocol REF column add
		# the value 'ArrayExpress'
		if ( $new_header =~ /Term Source REF/ && $have_seen_prot =~ /Protocol REF/ ) {
			print $tmp_sdrf_fh "ArrayExpress" . "\t";
		}

		# Print rest of SDRF
		else {
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

		$have_seen_prot = $new_header;
	}
	$row_number++;
	print $tmp_sdrf_fh "\n";
}

rename( $tmp_filename, $sdrf );
close $sdrf_fh;
close $tmp_sdrf_fh;

########################### SUBS ##################################
sub create_hash_of_headers_colnum {

	#Creates a hash of arrays where each key is a column header
	#and each value is an array containing the column number where
	#it has seen that header. Will use this when printing back out
	#the corrected SDRF

	my $col_number = 0;
	my $row_number = 1;
	my @header     = @_;
	my $have_seen  = " ";

	foreach my $x (@header) {

		if ( $x !~ /^Term Source REF/ ) {
			if ( exists $hash_of_headers_colnum{$x} ) {
				push @{ $hash_of_headers_colnum{$x} }, $col_number;
			}

			else {
				my @col_pos;
				push @col_pos, $col_number;
				$hash_of_headers_colnum{$x} = [@col_pos];

			}
		}

# Only store column position of Term Source REF columns not linked to a Protocol REF column
		if ( $x =~ /^Term Source REF/ ) {
			if ( $have_seen !~ /^Term Source REF/ && $have_seen !~ /^Protocol REF/ ) {

				if ( exists $hash_of_headers_colnum{$x} ) {
					push @{ $hash_of_headers_colnum{$x} }, $col_number;
				}

				else {
					my @col_pos;
					push @col_pos, $col_number;
					$hash_of_headers_colnum{$x} = [@col_pos];

				}
			}

		}

		$col_number++;
		$have_seen = $x;
	}
	return %hash_of_headers_colnum;
}

sub create_new_header {
	my @header    = @_;
	my $have_seen = " ";
	foreach my $cell (@header) {

		if ( $cell !~ /^Term Source REF/ ) {
			push @new_header, $cell;
		}

		else {
			if ( $have_seen !~ /^Term Source REF/ && $cell =~ /^Term Source REF/ ) {
				push @new_header, $cell;
			}

		}
		$have_seen = $cell;
		$col_number++;

	}

	return @new_header;
}
