# READ INTRO SECTION BELOW FOR EXPLANATION OF PROGRAM AND MAINTENACE
# A.Pico Feb 2007

##VERSION HISTORY##########################################################
# v11 - April2007
#     - Added CS database output in addition to Std
# v12 - April2007 *branch*
#     - Early attempt to integrate Derby database output
# v13 - May2007 *extends v11*
#     - Updated Std output after testing conversion to MSAccess
# v14* - April 2008
#     - Optimization api usage
#     - Fixes for mysql 5.0 (col_name "release" changed to "released") 
# v15 - May 2008
#     - Added synonym collection for Entrez, UniProt and HUGO (now HGNC)
# _local - Oct 2008
#     - ETL Device references local version of Ensembl tables to improve performance
# v16 - Oct 2008
#     - Added dummy GeneTable for synonym collection in Ensembl_GeneTable{Synonyms}
#     - Commented out collection of Trans, Exon, and Protein for performance
#     - Added database backup and copy functions to end of program
# v17 - Oct 2008
#     - Replaced dummy synonym GeneTable for an Attribute table for collect all attribute types
#     -	Added INSERT INTO 'attr' tables for Attributes in CS databases
# v18 - Nov 2008
#     - Added new systems for plant databases from Gramene
###########################################################################

#use Devel::Size qw(total_size);
use strict;
use DBI;
use lib '/home/apico/src/ensembl/modules';
use lib '/home/apico/src/ensembl-compara/modules';
use lib '/home/apico/bioperl-live'; 
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBSQL::DBConnection;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
my $api_path = "/home/apico/src/ensembl/modules";

## Under script control
my $scriptmode = 0;
my $speciesArg = 0;
my $dateArg = 0;

if ($#ARGV == 1) { # if 2 args passed in, then use them
	$speciesArg = $ARGV[0];
	$dateArg = $ARGV[1];

	#trigger script mode
	$scriptmode = 1;
}

############################################################################
## INTRO, MENUS AND CONTROLS ##
###############################

system "clear";
print "

            ******************************************* 
          *****  WELCOME TO THE ENSEMBL ETL DEVICE  *****
            *******************************************

This program utilizes the Perl API provided by Ensembl to extract gene 
information on a per species basis. The information is then transformed 
into tables structured for use in GenMAPP and other UCSF projects. 
Finally, the table data is loaded into a MySQL database for further
optimization and stable accessibility.

>>More about this project:
  GenMAPP - http://www.genmapp.org
  Wiki - http://conklinwolf.ucsf.edu/conklinwiki/GenMAPP
  Ensembl - http://www.ensembl.org
  Perl API - http://www.ensembl.org/info/software/Pdoc/ensembl/index.html

>>Who to blame:
  Alex Pico - apico\@gladstone.ucsf.edu
  Rich Trott - richard.trott\@library.ucsf.edu
        
            *******************************************
";
print "\n\nPress RETURN to continue";
unless ($scriptmode) {
	my $pause = <STDIN>;
}

system "clear";
print "
            *******************************************

                       --- INSTRUCTIONS ---

 [1] First, you will select the species from which you would like to 
 extract gene information.

 [2] Next, you will answer a series of 'Yes' or 'No' questions to control
 the detailed behavior and output of the progrom.  These options are mostly
 used for debugging and generating reports. Simply press ENTER to run defaults.

                       --- PERFORMANCE ---
    
 At the beginning of a run the program will print out a message with basic
 information: which API is being used, which species is being queried, etc.
 Following this initial message there is a delay of ~60 seconds during which
 the remote connection is established and '\$gene_adaptor->fetch_all()' is exe-
 cuted, gathering an index for each and every gene in the specified genome.
 Next, each gene will be processed and a message will be printed indicating
 the current gene ID and progress (e.g., 1 of 28594).
 In early testing, we observed runtimes of just under 2 hours per 1000 genes
 and approximately 35 hours for an entire species with ~28,000 genes. We may
 be able to run the program for multiple species in parallel and improve the
 upon performance.
 
                       --- MAINTENANCE ---

 Keep up-to-date by installing the latest API modules via Ensembl's CVS.
 Simply copy and paste the following command line statements:

  1) cd /home/apico/src/
  2) cvs -d :pserver:cvsuser\@cvs.sanger.ac.uk:/cvsroot/ensembl  login
     password: CVSUSER  (yes, in all caps)
  3) cvs -d :pserver:cvsuser\@cvs.sanger.ac.uk:/cvsroot/ensembl  checkout -r branch-ensembl-## ensembl
      (where ## is replaced with the latest release number, e.g., 41)
  4) cvs -d :pserver:cvsuser\@cvs.sanger.ac.uk:/cvsroot/CVSmaster login
     password: CVSUSER  (yes, in all caps)
  5) cvs -d :pserver:cvsuser\@cvs.sanger.ac.uk:/cvsroot/CVSmaster co -r branch-ensembl-## ensembl-compara
      (where ## is replaced with the latest release number, e.g., 41)
  6) Increase region cache size in ensembl/modules/Bio/EnsEMBL/Utils/SeqRegionCache.pm SEQ_REGION_CACHE_SIZE from 40000 to 250000
	to allow for performance enhancement by slice_adaptor->fetch_all(toplevel)
 These steps will update the local copy of the Ensembl API by overwriting the
 folder /home/apico/src/ensembl/ and /home/apico/src/ensembl-compara.

 Update the list of species by editing the file 'SpeciesList' which is read-in
 by this program. Currenlty, the first, second and fifth columns are used.

            *******************************************
";
print "\n\nPress RETURN to continue";
unless ($scriptmode) {
	my $pause = <STDIN>;
}

system "clear";
print "
            *******************************************
";

## GET TABLE OF SUPPORTED SPECIES
# TODO: store species table in mysql database instead of flatfile
my %speciesTable = ();                # Hash of Arrays for storing species table in Perl
my @speciesList = ();                 # list of species names to display in menu
my $input = "SpeciesList";            # filename of flatfile containing table of species
my $arrayPick = 'null';		      # menu selection

unless( open( SPECIES, $input)){
    print "Could not open file $input: $!\n";
}

foreach (<SPECIES>){
    my $line = $_;
    if ($line =~ /\*/){next; } # Header line
    chomp $line;
    my @fields = split(/\t/, $line);
    $speciesTable{$fields[1]} = [$fields[0], $fields[4]]; # (KEY:common name, VALUE:[genus species, two-letter code])
    push(@speciesList, "$fields[1]\t($fields[0])");       # (VALUE:common name \t (genus species))
    if ($scriptmode) {
        if ($fields[4] =~ /($speciesArg)/){
                $arrayPick = $fields[1];
        }
    }

}

close(SPECIES);

## MENU OF SUPPORTED SPECIES
unless ($scriptmode) {
	print "\n\nSTEP 1: Please select a species.\n\n";
	$arrayPick = pickFromArray(@speciesList);             # menu selection
}
if ($arrayPick eq 'null') {
	print "\n\nSpecies $speciesArg was not found!\n\n";	
	exit;
}
my @splitPick = split(/\t/, $arrayPick);                      # split: [0]=common name, [1]=(genus species)
my $speciesPick = $splitPick[0];                              # store common name, e.g., Mouse
my $twoLetterSpecies = $speciesTable{$speciesPick}[1];	      # two-letter code, e.g., Mm
my $EnSpeciesCode = "En".$twoLetterSpecies;		      # Ensembl species-specific codes, e.g., EnMm
my $species = $speciesTable{$speciesPick}[0];                 # store genus species, e.g., Mus musculus 
my @split_species = split(/\s/, $species);   		      # split: [0]=genus, [1]=species, [2]=extra
my $genus = $split_species[0];
my $species_extra = $split_species[1];
if ($split_species[2]) {$species_extra .= "_".$split_species[2];}   # append "extra" to species (e.g., coli-K12)
my $genus_species = $genus."_".$species_extra;                      # store genus_species (with underscore)
$genus_species =~ tr/A-Z/a-z/;                                # all lowercase, e.g., mus_musculus 
my $genus_species_abv = substr($genus, 0, 1);      	      # store Ensembl-style abreviated genus species
$genus_species_abv .= $species_extra;                      	      # concatentate genus initial with species name
$genus_species_abv =~ tr/A-Z/a-z/;                            # all lowercase, e.g., mmusculus
my $mod_system = 'Ensembl';                                   # store Model Organism Database (MOD) identifier system
if ($species eq 'Wacky'){
    $mod_system = 'Something Else';                           # use this loop for custom species-MOD pairs
}

## CONTROLS FOR PROGRAM
print "\n\nSTEP 2: Please set the following options. Press Enter for default response.\n";

## COLLECT SAMPLE OF GENES FROM GENOME?
my $sample_only_default = 'No';      # default answer
my $collect_sample = 0;               # 0=collect all genes
my $start_count = 1;                  # start counting at 1

print "\n\tWould you like to collect data on only a sample of the genome? ($sample_only_default) --> ";
my $sample_only = $sample_only_default;
unless ($scriptmode) {
	$sample_only = <STDIN>;            # user answer
	chomp $sample_only;
	if ($sample_only eq '') {
    	$sample_only = $sample_only_default;  
	}
	until ( $sample_only =~ /(Y|Yes|N|No)/i ) {
    	print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    	$sample_only = <STDIN>;
    	chomp $sample_only;
	}
}

## IF YES, HOW MANY GENES TO COLLECT?
if ($sample_only =~ /(Y|Yes)/i ){
    my $collect_sample_default = 10;  # default answer

    print "\n\tHow many genes would you like to collect? ($collect_sample_default) --> ";
    $collect_sample = <STDIN>;        # user answer: size of sample collection
    chomp $collect_sample;
    if ($collect_sample eq '') {
	$collect_sample = $collect_sample_default;  
    }
    until ( $collect_sample =~ /^(1?\d?\d?\d?\d|20000)$/ ) {
	print "\n\nInvalid Entry!!!\nPlease type a number between 1 and 20000 --> ";
	$collect_sample = <STDIN>;
	chomp $collect_sample;
    }
}
  
## IF YES, WHERE DO YOU WANT TO START COUNTING?
if ($sample_only =~ /(Y|Yes)/i ){
    my $start_count_default = 1;      # default answer

    print "\n\tAt which number would you like to start collecting? ($start_count_default) --> ";
    $start_count = <STDIN>;           # user answer: begining boundary of sample collection
    chomp $start_count;
    if ($start_count eq '') {
	$start_count = $start_count_default;  
    }
    until ( $start_count =~ /^([1-3]?\d?\d?\d?\d|40000)$/ ) {
	print "\n\nInvalid Entry!!!\nPlease type a number between 1 and 40000 --> ";
	$start_count = <STDIN>;
	chomp $start_count;
    }
}

my $end_count = $start_count + $collect_sample - 1;  # store end boundary of sample collection


## INSERT DATA INTO MYSQL STD TABLES?
my $mysql_std_load_default = 'Yes';      # default answer

print "\n\n\tWould you like to load data directly into MySQL Std tables? ($mysql_std_load_default) --> ";
my $mysql_std_load = $mysql_std_load_default;
unless ($scriptmode) {
	$mysql_std_load = <STDIN>;           # user answer: Y/N flag
	chomp $mysql_std_load;
	if ($mysql_std_load eq '') {
    		$mysql_std_load = $mysql_std_load_default;  
	}
	until ( $mysql_std_load =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$mysql_std_load = <STDIN>;
    		chomp $mysql_std_load;
	}
}

## INSERT DATA INTO MYSQL CS TABLES?
my $mysql_cs_load_default = 'Yes';      # default answer

print "\n\n\tWould you like to load data directly into MySQL CS tables? ($mysql_cs_load_default) --> ";
my $mysql_cs_load = $mysql_cs_load_default;
unless ($scriptmode) {
	$mysql_cs_load = <STDIN>;           # user answer: Y/N flag
	chomp $mysql_cs_load;
	if ($mysql_cs_load eq '') {
    		$mysql_cs_load = $mysql_cs_load_default;  
	}
	until ( $mysql_cs_load =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$mysql_cs_load = <STDIN>;
    		chomp $mysql_cs_load;
	}
}

## PRINT DATA TO FLATFILE?
my $print_tables_default = 'No';      # default answer

print "\n\n\tWould you like to generate a tab-delimited file containing all table data? ($print_tables_default) --> ";
my $print_tables = $print_tables_default;
unless ($scriptmode) {
	$print_tables = <STDIN>;           # user answer: Y/N flag
	chomp $print_tables;
	if ($print_tables eq '') {
    		$print_tables = $print_tables_default;  
	}
	until ( $print_tables =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$print_tables = <STDIN>;
    		chomp $print_tables;
	}
}

# Warn user about potential file size and cpu time
if ($print_tables =~ /(Y|Yes)/i && ($collect_sample > 100 || $collect_sample == 0)){
    print "\n\tWARNING! Generating a tab file with data for over 100 genes will produce a file > 10MB and add significant time to the run. 
\tPrinting these data tables is not recommended for samples > 100, and should be avoided at all costs for samples > 10,000.\n";

    print "\n\tContinue to print file? ($print_tables_default) --> ";
    $print_tables = <STDIN>;
    chomp $print_tables;
    if ($print_tables eq '') {
	$print_tables = $print_tables_default;  
    }
    until ( $print_tables =~ /(Y|Yes|N|No)/i ) {
	print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
	$print_tables = <STDIN>;
	chomp $print_tables;
    }
}

## ARE YOU READY TO RUN?
my $run_now_default = 'Yes';      # default answer

print "\n\n\tAre you ready to run? ($run_now_default) --> ";
my $run_now = $run_now_default;
unless ($scriptmode) {
	$run_now = <STDIN>;            # user answer: Y/N flag
	chomp $run_now;
	if ($run_now eq '') {
    		$run_now = $run_now_default;  
	}
	until ( $run_now =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$run_now = <STDIN>;
    		chomp $run_now;
	}
}

if ($run_now =~ /(N|No)/i){
    exit;
}

system "clear";
print "
        *******************************************
";

############################################################################
## ACCESS ENSEMBL DATABASE USING API ##
#######################################

## START TIME
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $zero = '0';
$year += 1900;
$mon += 1;
$mon = $zero.$mon unless $mon >= 10;
$mday = $zero.$mday unless $mday >= 10;
$hour = $zero.$hour unless $hour >= 10;
$min = $zero.$min unless $min >= 10;
$sec = $zero.$sec unless $sec >= 10;

## API: REGISTRY
# Use Registry to Access Latest Species Database (matching the API branch version) 
my $registry = 'Bio::EnsEMBL::Registry';

$registry->load_registry_from_db(
        -host => 'localhost',
        -user => 'genmapp',
	-pass => 'fun4genmapp',
        -verbose => "0");

## DEBUG: List all databases installed on a given host
my @db_adaptors = @{ $registry->get_all_DBAdaptors() };

foreach my $db_adaptor (@db_adaptors) {
    my $db_connection = $db_adaptor->dbc();

    printf(
        "species/group\t%s/%s\ndatabase\t%s\nhost:port\t%s:%s\n\n",
        $db_adaptor->species(),   $db_adaptor->group(),
        $db_connection->dbname(), $db_connection->host(),
        $db_connection->port()
    );
}


## API: GET ADAPTORS 
# get gene adaptor to query gene information
# get slice adaptor to load 'top-level' regions into SeqRegionCache
# get database adaptors to identify the name of latest species database
my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species, "core", "gene");
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor($species, "core", "slice");
my @dbas = @{Bio::EnsEMBL::Registry->get_all_DBAdaptors(-species => $species)};
my $dbname = $dbas[0]->dbc->dbname();        # e.g., core_mus_musculus_42_36c
my @split_dbname = split(/_/, $dbname);
if ($split_dbname[1] == "collection"){	     # shift array elements for "collections"
	splice(@split_dbname,1,1);
}
my $build = $split_dbname[3];                # e.g., 42
my $build_nums = $build.$split_dbname[4];    # e.g., 42_36c

############################################################################
## DECLARE/INITIALIZE DATA TABLES ##
######################################

## GENE TABLES 
# Hash of Hashes of Arrays
my %GeneTables = ();             # ID systems
my %Ensembl_GeneTables = ();     # links between Ensembl and other ID systems
my %Attributes = ();             # Attributes per gene ID 

## ENSEMBL GENE STRUCTURE TABLES
# Hash of Arrays
my %Ensembl = ();                # Ensembl gene IDs and annotations
my %Ensembl_Trans = ();          # links between gene and transcript IDs
my %Ensembl_Exon = ();           # links between gene, transcript and exon IDs
my %Ensembl_Protein = ();        # links between gene, transcript and protein IDs
my %Trans = ();                  # Ensembl transcript IDs and annotations
my %Exon = ();                   # Ensembl exon IDs and annotations
my %Protein = ();                # Ensembl protein IDs and annotations, including ProteinFeature IDs
my %ProteinFeatures = ();        # Ensembl protein feature IDs and annotations
my %Homologs = ();               # Orthologs and Paralogs from Ensembl Compara database
my %Ensembl_Homologs = ();       # links between gene and homologs

## SYSTEMS TABLE
# Hash of Arrays
# ID system annotations per species database, used by GenMAPP
my %Systems = ('NAME' => ['Systems'],
	       'HEADER' => ['System VARCHAR(128)  NOT NULL DEFAULT \'\'',
			    'SystemCode VARCHAR(3)  NOT NULL DEFAULT \'\'',
			    'SystemName VARCHAR(128)  NOT NULL DEFAULT \'\'',
			    'Date INT(10) UNSIGNED NOT NULL DEFAULT \'0\'',
			    'Systems.Columns VARCHAR(255)  NOT NULL DEFAULT \'\'',
			    'Species VARCHAR(255)  NOT NULL DEFAULT \'\'',
			    'Systems.MOD VARCHAR(128)  NOT NULL DEFAULT \'\'',
			    'Link VARCHAR(255)  NOT NULL DEFAULT \'\'',
			    'Misc VARCHAR(255)  NOT NULL DEFAULT \'\'',
			    'Source VARCHAR(255)  NOT NULL DEFAULT \'\'']);

## OTHER TABLE
# Hash of Arrays
# Table for user ID systems, used by GenMAPP
my %Other = ('NAME' => ['Other', 'O'], 
	    'SYSTEM' => ["\'Other\'", "\'$year$mon$mday\'", 
			 "\'ID|SystemCode\\\\BF|Name\\\\BF|Annotations\\\\BF\|\'", "\'\|\|\'", "\'\'",
			 "\'\'", "\'\|E\|\'", 
			 "\'\'"],
	    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
			 'SystemCode VARCHAR(3) NOT NULL DEFAULT \'\'',
			 'Name VARCHAR(128) NOT NULL DEFAULT \'\'', 
			 'Annotations VARCHAR(255) DEFAULT NULL', 
			 'PRIMARY KEY (ID)'
			 ]);
	

## ADMINISTRATIVE TABLES
# Hash of Arrays 
# Collects a sample of every xref (or ID system) available from Ensembl per species database
# Use this table to monitor new ID systems and fields, or changes to existing systems and fields 
my %ADMIN_Xrefs = ('NAME' => ['ADMIN_Xrefs'], 
	     'HEADER' => ['xref_dbname  VARCHAR(128) NOT NULL DEFAULT \'\'',
			  'display_id VARCHAR(128) NOT NULL DEFAULT \'\'', 
			  'primary_id VARCHAR(128) NOT NULL DEFAULT \'\'', 
			  'description VARCHAR(255) DEFAULT NULL', 
			  'synonyms VARCHAR(255) DEFAULT NULL', 
			  'released VARCHAR(10) NOT NULL DEFAULT \'0\'', 
			  'status ENUM(\'KNOWNXREF\', \'KNOWN\', \'XREF\', \'PRED\', \'ORTH\', \'PSEUDO\') NOT NULL DEFAULT \'KNOWNXREF\'', 
			  'version VARCHAR(10) NOT NULL DEFAULT \'0\'', 
			  'info_text VARCHAR(255) DEFAULT NULL', 
			  'info_type ENUM(\'PROJECTION\',\'MISC\',\'DEPENDENT\',\'DIRECT\',\'SEQUENCE_MATCH\',\'INFERRED_PAIR\') DEFAULT NULL', 
			  'Collected ENUM(\'Y\', \'N\') DEFAULT NULL']);  

## INFO TABLE
# Hash of Arrays
# Basic information for each species database, used by GenMAPP
my %Info = ('NAME' => ['Info'], 
	    'HEADER' => ['Owner VARCHAR(128) DEFAULT NULL', 
			 'Version INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			 'MODSystem VARCHAR(128)  NOT NULL DEFAULT \'\'', 
			 'Species VARCHAR(255)  NOT NULL DEFAULT \'\'', 
			 'Modify INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			 'DisplayOrder VARCHAR(255)  NOT NULL DEFAULT \'\'', 
			 'Notes VARCHAR(255)  NOT NULL DEFAULT \'\'']);

# Populate Info Table
$Info{1} = ["\'GenMAPP\.org\'", "\'$year$mon$mday\'", "\'$mod_system\'", "\'\|$species\|\'", "\'$year$mon$mday\'", "\'\'", "\'$dbname\'"];

############################################################################
## ALL SYSTEMS GO! ##
#####################

## PRINT RUN INFO
my @Runtime = ();  #Simple statement of data source, extraction date and runtime   
push(@Runtime,  "Data for $speciesPick ($species) extracted from Ensembl database ($dbname) using API ($api_path) on $mon-$mday-$year\n");
push(@Runtime, "Start $hour:$min:$sec");
$" = "\n"; #use return to delimit array elements;
print "\n@Runtime\n\n";


## FIRST-ORDER VARIABLES
my $gene_stable_id = "NULL";        # ensembl gene id
my $gene_symbol = "NULL";	    # ensembl gene symbol
my $dot = ".";                      # used as decimal point in hash keys
my @systemTables = ();              # collects all data tables with a 'SYSTEMS' key
my $displayOrder = "NULL";          # stores system codes in the order shown on "Backpages"
my %seenSystemTables = ();          # used to collect unique list of @systemTables 
my $dbh = "NULL";                   # mysql database variable
my $sth = "NULL";                   # mysql statement variable
my $first_collection = 1;           # flag for first pass through periodic collection (TRUE = 1, FALSE = 0)	
my $initializeTables = 1;           # flag for initializing data tables (DO = 1, DON'T = 0)
my $count = 1;                      # keeps count of each gene
my $purge_frequency = 1000;         # indicates frequency of mysql loading, print out, and reinitialization of data tables 


## CHECK TOTAL NUMBER OF GENES IN GENOME 
my $total = $#{$gene_adaptor->list_dbIDs()} + 1;    # total number of genes in genome

# Set $collect_sample to $total if collecting all genes
if ($collect_sample == 0){
    $collect_sample = $total;
}

# Filename for print_Tables subroutine
my $output = $twoLetterSpecies."_Std_".$year.$mon.$mday."_All_".$collect_sample.".tab";



## CHECK INPUT PARAMETERS AGAINST TOTAL GENE COUNT
# check to see if user-defined start and sample size are within the size of the genome
if ($collect_sample > $total || $start_count > $total){
    print "INVALID USER PARAMETERS!!!\n\nSample size = $collect_sample\nStart = $start_count\nGenome = $total genes\n\n";
    exit;
}


## LOOP THROUGH EACH GENE IN GENOME
######################################################################################
# The performance of $gene_adaptor->fetch_all() is dependent on a number of factors. #
# The main factor is the level of organization of the genes for a given species. For #
# example, well studied genomes are assembled and organized into chromosomes (e.g.,  #
# Fruitfly = 12, Rat = 22). This difference in the number of organized units, or seq #
# regions, translates into a difference of ~2 minutes for the $gene_adaptor->fetch_  #
# all() method (Fruitfly = 0:27, Rat = 2:34). Less well studied species have their   #
# genes mapped to much larger numbers of seq regions: Frog=2694, Cow=4927, Elephant= #
# 13351. For species with genes on >10000 seq regions, the $gene_adaptor->fetch_all()#
# method can take >45 minutes.                                                       #
# The performance for species with large numbers of seq regions can be significantly #
# improved by pre-loading the SeqRegionCache with the $slice_adaptor->fetch_all()    #
# method, fetching all 'toplevel' seq regions. However, $SEQ_REGION_CACHE_SIZE (in   #
# Bio::EnsEMBL::Utils::SeqRegionCache) must be increased from 40000 to accomodate    #
# species with a greater number of seq regions. Use with care.                       #
######################################################################################

# This fetch_all() method fills the SeqRegionCache to speed up performance for species
$slice_adaptor->fetch_all('toplevel'); 

# This fetch_all() method can take a while (up to an hour) for species not yet organized into chromosomes
# Using a while-pop loop instead of foreach, removes the need to reset $gene=0 in order to keep memory clear
#foreach my $gene (@{$gene_adaptor->fetch_all()})
my $genes = $gene_adaptor->fetch_all();

while (my $gene = pop(@$genes)) 
{

    # Compare collect_sample variable against gene count
    if ($count >= ($collect_sample + $start_count)){
	next;
    }

    # Check start_count variable to skip records for collecting in stages
    if ($count <  $start_count){
	$count++;
	next;
    }

    ## (RE)INITIALIZE ALL DATA TABLES
    # Performed once during the first pass of the parent FOREACH loop, and again after every mysql load and/or print out
    if ($initializeTables){

	## GENE TABLES 
	# Hash of Hashes of Arrays
	###################################################################################
	# These tables will contain the bulk of the data being extracted from Ensembl.    #
	# The top-level Hash is keyed by the name of the ID system, e.g., EntrezGene.     #
	# The mid-level Hashes are keyed by key words and numeric counts:                 #
	#  ->'NAME' = the table name to be used in mysql CREATE TABLE                     #
	#  ->'SYSTEM' = basic information about the ID system, including linkout and      #
	#               ftp source URLs, and ultimately loaded into the Systems Table     #
	#  ->'HEADER' = the table fields to be used in mysql CREATE TABLE                 #
	#  -> Numeric keys correspond to the unique gene count plus subcounts for 1:n     # 
	#      relationships.  For example, the key {1.3} in %{$GeneTables{EntrezGene}}   #
	#      would correspond to the third EntrezGene entry for the first Ensembl gene. #
	# The bottom-level Arrays contain the data bounded by escaped single quotes for   #
	# compatibility with mysql import.                                                #
	#                                                                                 #
	# Add to or Edit these tables to include new ID systems or to make modifications. #
	###################################################################################
	%{$GeneTables{EntrezGene}} = ('NAME' => ['EntrezGene', 'L'], 
				      'SYSTEM' => ["\'Entrez Gene (NCBI)\'", "\'$year$mon$mday\'", 
						   "\'ID\|Symbol\\\\sBF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						   "\'http://www.ncbi.nlm.nih.gov/sites/entrez?Db=gene&TermToSearch=~\'", "\'\'", 
						   "\'ftp.ncbi.nlm.nih.gov/gene/DATA/\'"],
				      'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
						   'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
						   'Synonyms VARCHAR(255) DEFAULT NULL',
                                                   'PRIMARY KEY (ID)'                                                 
					           ]);
	%{$GeneTables{UniProt}} = ('NAME' => ['UniProt', 'S'], 
				   'SYSTEM' => ["\'The Universal Protein Resource (EBI, SIB, PIR)\'", "\'$year$mon$mday\'", 
						"\'ID|Symbol\\\\sBF|Type\\\\BF|Description\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						"\'http://www.uniprot.org/entry/~\'", "\'\'", 
						"\'http://www.pir.uniprot.org/database/download.shtml\'"],
				   'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Type VARCHAR(128) NOT NULL DEFAULT \'\'',
						'Description VARCHAR(255) DEFAULT NULL',
						'Synonyms VARCHAR(255) DEFAULT NULL',
						'PRIMARY KEY (ID)',
						'INDEX (Symbol)']);
	%{$GeneTables{RefSeq}} = ('NAME' => ['RefSeq', 'Q'], 
				  'SYSTEM' => ["\'RefSeq (NCBI)\'", "\'$year$mon$mday\'", 
					       "\'ID|Symbol\\\\sBF|Type\\\\BF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					       "\'http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?val=~\'", "\'\'", 
					       "\'ftp://ftp.ncbi.nih.gov/refseq/release/\'"],
				  'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					       'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
					       'Type VARCHAR(128) NOT NULL DEFAULT \'\'',
					       'Description VARCHAR(255) DEFAULT NULL',
					       'PRIMARY KEY (ID)',
                                               'INDEX (Symbol)'
					       ]);
	%{$GeneTables{GeneOntology}} = ('NAME' => ['GeneOntology', 'T'], 
					'SYSTEM' => ["\'The Gene Ontology\'", "\'$year$mon$mday\'", 
						     "\'ID\|\'", "\'\|$species\|\'", "\'\'",
						     "\'http://amigo.geneontology.org/cgi-bin/amigo/term-details.cgi?term=~\'", "\'\|I\|\'", 
						     "\'ftp://ftp.geneontology.org/pub/go/ontology/\'"],
					'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
						     'PRIMARY KEY (ID)'
						     ]);
	%{$GeneTables{Affy}} = ('NAME' => ['Affy', 'X'], 
				'SYSTEM' => ["\'Affymetrix\'", "\'$year$mon$mday\'", 
					     "\'ID|Chip\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.ensembl.org/".$genus_species."/Search/Summary?q=~\'", "\'\'", 
					     "\'https://www.affymetrix.com/analysis/downloads/\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Chip VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'PRIMARY KEY (ID)'
					     ]);
	%{$GeneTables{Agilent}} = ('NAME' => ['Agilent', 'Ag'], 
				   'SYSTEM' => ["\'Agilent Technologies\'", "\'$year$mon$mday\'", 
						"\'ID|Chip\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						"\'\'", "\'\'", 
						"\'http://www.agilent.com/\'"],
				   'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Chip VARCHAR(128) NOT NULL DEFAULT \'\'',
						'PRIMARY KEY (ID)'
						]);
	%{$GeneTables{Illumina}} = ('NAME' => ['Illumina', 'Il'], 
				    'SYSTEM' => ["\'Illumina\'", "\'$year$mon$mday\'", 
						 "\'ID|Chip\\\\BF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						 "\'\'", "\'\'", 
						 "\'http://www.illumina.com/products/arraysreagents/overview.ilmn\'"],
				    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						 'Chip VARCHAR(128) NOT NULL DEFAULT \'\'', 
						 'Description VARCHAR(255) DEFAULT NULL',
						 'PRIMARY KEY (ID)'
						 ]);
	%{$GeneTables{Cint}} = ('NAME' => ['Cint', 'C'], 
				    'SYSTEM' => ["\'Custom Microarrays for Ciona\'", "\'$year$mon$mday\'", 
						 "\'ID|Chip\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						 "\'\'", "\'\'", 
						 "\'\'"],
				    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						 'Chip VARCHAR(128) NOT NULL DEFAULT \'\'', 
						 'PRIMARY KEY (ID)'
						 ]);
	%{$GeneTables{Codelink}} = ('NAME' => ['Codelink', 'Ge'], 
				    'SYSTEM' => ["\'GE Healthcare Codelink Bioarrays\'", "\'$year$mon$mday\'", 
						 "\'ID\|\'", "\'\|$species\|\'", "\'\'",
						 "\'\'", "\'\'", 
						 "\'http://www4.amershambiosciences.com/APTRIX/upp01077.nsf/content/codelink_bioarray_system\'"],
				    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
						 'PRIMARY KEY (ID)'
						 ]);
	%{$GeneTables{CCDS}} = ('NAME' => ['CCDS', 'Cc'], 
				'SYSTEM' => ["\'Consensus CDS Protein Set (NCBI)\'", "\'$year$mon$mday\'", 
					     "\'ID\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.ncbi.nlm.nih.gov/CCDS/CcdsBrowse.cgi?REQUEST=ALLFIELDS&DATA=~&ORGANISM=".$genus_species."\'", "\'\'", 
					     "\'ftp://ftp.ncbi.nlm.nih.gov/pub/CCDS/\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'PRIMARY KEY (ID)'
					     ]);
	%{$GeneTables{IPI}} = ('NAME' => ['IPI', 'Ip'], 
			       'SYSTEM' => ["\'International Protein Index (EBI)\'", "\'$year$mon$mday\'", 
					    "\'ID|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					    "\'http://srs.ebi.ac.uk/srsbin/cgi-bin/wgetz?-newId+\[IPI-AllText:~\]+-lv+30+-view+SeqSimpleView+-page+qResult\'", "\'\'", 
					    "\'ftp://ftp.ebi.ac.uk/pub/databases/IPI/current/\'"],
			       'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Description VARCHAR(255) DEFAULT NULL',
					    'PRIMARY KEY (ID)'
					    ]);
	%{$GeneTables{EMBL}} = ('NAME' => ['EMBL', 'Em'], 
				'SYSTEM' => ["\'EMBL-Bank (EBI)\'", "\'$year$mon$mday\'", 
					     "\'ID\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.ebi.ac.uk/cgi-bin/emblfetch?style=html&id=~\'", "\'\'", 
					     "\'http://www.ebi.ac.uk/embl/Access/index.html#ftp\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'PRIMARY KEY (ID)'
					     ]);
	%{$GeneTables{UniGene}} = ('NAME' => ['UniGene', 'U'], 
				   'SYSTEM' => ["\'UniGene (NCBI)\'", "\'$year$mon$mday\'", 
						"\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						"\'http://www.ncbi.nlm.nih.gov/sites/entrez?db=unigene&cmd=search&term=~\'", "\'\'", 
						"\'ftp://ftp.ncbi.nih.gov/repository/UniGene/\'"],
				   'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
						'Description VARCHAR(255) DEFAULT NULL',
						'PRIMARY KEY (ID)',
						'INDEX (Symbol)'
						]);
	%{$GeneTables{RFAM}} = ('NAME' => ['RFAM', 'Rf'], 
				'SYSTEM' => ["\'RNA Families Database\'", "\'$year$mon$mday\'", 
					     "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.sanger.ac.uk/cgi-bin/Rfam/getacc?~\'", "\'\|I\|\'", 
					     "\'http://www.sanger.ac.uk/Software/Rfam/\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Description VARCHAR(255) DEFAULT NULL',
					     'PRIMARY KEY (ID)',
					     'INDEX (Symbol)']);
	%{$GeneTables{GenPept}} = ('NAME' => ['GenPept', 'Gp'], 
				   'SYSTEM' => ["\'GenBank Peptide Sequences (NCBI)\'", "\'$year$mon$mday\'", 
						"\'ID\|\'", "\'\|$species\|\'", "\'\'",
						"\'\'", "\'\'", 
						"\'\'"],
				   'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
						'PRIMARY KEY (ID)'
						]);
	%{$GeneTables{PDB}} = ('NAME' => ['PDB', 'Pd'], 
			       'SYSTEM' => ["\'Protein Data Bank\'", "\'$year$mon$mday\'", 
					    "\'ID\|\'", "\'\|$species\|\'", "\'\'",
					    "\'http://www.rcsb.org/pdb/explore/explore.do?structureId=~\'", "\'\'", 
					    "\'http://www.rcsb.org/pdb/static.do?p=download/ftp/index.html\'"],
			       'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
					    'PRIMARY KEY (ID)'
					    ]);
        %{$GeneTables{BioGrid}} = ('NAME' => ['BioGrid', 'Bg'], 
                               'SYSTEM' => ["\'The Biological General Repository for Interaction Datasets\'", "\'$year$mon$mday\'",
                                            "\'ID\|\'", "\'\|$species\|\'", "\'\'",
                                            "\'http://www.thebiogrid.org/SearchResults/summary/~\'", "\'\'",
                                            "\'http://www.thebiogrid.org\'"],
                               'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                            'PRIMARY KEY (ID)'
                                            ]);
	%{$GeneTables{OMIM}} = ('NAME' => ['OMIM', 'Om'], 
				'SYSTEM' => ["\'Online Mendelian Inheritance in Man (NCBI)\'", "\'$year$mon$mday\'", 
					     "\'ID|Type\\\\BF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.ncbi.nlm.nih.gov/entrez/dispomim.cgi?id=~\'", "\'\|I\|\'", 
					     "\'http://www.ncbi.nlm.nih.gov/Omim/omimfaq.html#download\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Type VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Description VARCHAR(255) DEFAULT NULL',
					     'PRIMARY KEY (ID)'
					     ]);
	%{$GeneTables{miRBase}} = ('NAME' => ['miRBase', 'Mb'], 
				'SYSTEM' => ["\'miRBase: the home of miRNA data\'", "\'$year$mon$mday\'", 
					     "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://microrna.sanger.ac.uk/cgi-bin/sequences/mirna_entry.pl?acc=~\'", "\'\'", 
					     "\'http://microrna.sanger.ac.uk/sequences\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Description VARCHAR(255) DEFAULT NULL',
					     'PRIMARY KEY (ID)',
					     'INDEX (Symbol)']);
	%{$GeneTables{HUGO}} = ('NAME' => ['HUGO','H'], 
				'SYSTEM' => ["\'The Human Genome Organisation\'", "\'$year$mon$mday\'", 
					     "\'ID|Symbol\\\\sBF|Description\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://www.genenames.org/data/hgnc_data.php?hgnc_id=~\'", "\'\'", 
					     "\'http://www.genenames.org\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Description VARCHAR(255) DEFAULT NULL',
					     'Synonyms VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
					     'INDEX (Symbol)']);
	%{$GeneTables{MGI}} = ('NAME' => ['MGI', 'M'], 
			       'SYSTEM' => ["\'Mouse Genome Informatics\'", "\'$year$mon$mday\'", 
					    "\'ID|Symbol\\\\sBF|Description\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					    "\'http://www.informatics.jax.org/searches/accession_report.cgi?id=~\'", "\'\'", 
					    "\'ftp://ftp.informatics.jax.org/pub\'"],
			       'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Description VARCHAR(255) DEFAULT NULL', 
					    'Synonyms VARCHAR(255) DEFAULT NULL',
					    'PRIMARY KEY (ID)',
					    'INDEX (Symbol)']);
	%{$GeneTables{RGD}} = ('NAME' => ['RGD', 'R'], 
			       'SYSTEM' => ["\'Rat Genome Database\'", "\'$year$mon$mday\'", 
					    "\'ID|Symbol\\\\sBF|Description\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					    "\'http://rgd.mcw.edu/query/query.cgi?id=~\'", "\'\'", 
					    "\'ftp://rgd.mcw.edu/pub/\'"],
			       'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Description VARCHAR(255) DEFAULT NULL',
					    'Synonyms VARCHAR(255) DEFAULT NULL',
					    'PRIMARY KEY (ID)',
					    'INDEX (Symbol)']);
	%{$GeneTables{SGD}} = ('NAME' => ['SGD', 'D'], 
			       'SYSTEM' => ["\'Saccharomyces Genome Database\'", "\'$year$mon$mday\'", 
					    "\'ID|Symbol\\\\sBF|Description\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					    "\'http://db.yeastgenome.org/cgi-bin/locus.pl?sgdid=~\'", "\'\'", 
					    "\'ftp://genome-ftp.stanford.edu/pub/yeast/\'"],
			       'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
					    'Description VARCHAR(255) DEFAULT NULL',
					    'Synonyms VARCHAR(255) DEFAULT NULL',
					    'PRIMARY KEY (ID)',
					    'INDEX (Symbol)']);
	%{$GeneTables{ZFIN}} = ('NAME' => ['ZFIN', 'Z'], 
				'SYSTEM' => ["\'Zebrafish Information Network\'", "\'$year$mon$mday\'", 
					     "\'ID|Symbol\\\\sBF|Type\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
					     "\'http://zfin.org/cgi-bin/webdriver?MIval=aa-markerview.apg&OID=~\'", "\'\'", 
					     "\'http://zfin.org/zf_info/downloads.html\'"],
				'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'Type VARCHAR(128) NOT NULL DEFAULT \'\'', 
					     'PRIMARY KEY (ID)',
					     'INDEX (Symbol)']);
	%{$GeneTables{FlyBase}} = ('NAME' => ['FlyBase', 'F'], 
				   'SYSTEM' => ["\'FlyBase\'", "\'$year$mon$mday\'", 
						"\'ID|Symbol\\\\sBF|Type\\\\BF|Synonyms\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						"\'http://flybase.bio.indiana.edu/.bin/fbidq.html?~\'", "\'\'", 
						"\'http://flybase.bio.indiana.edu/static_pages/downloads/bulkdata7.html\'"],
				   'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Type VARCHAR(128) NOT NULL DEFAULT \'\'', 
						'Synonyms VARCHAR(255) DEFAULT NULL',
						'PRIMARY KEY (ID)',
						'INDEX (Symbol)']);
	%{$GeneTables{WormBase}} = ('NAME' => ['WormBase', 'W'], 
				    'SYSTEM' => ["\'WormBase\'", "\'$year$mon$mday\'", 
						 "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
						 "\'http://www.wormbase.org/db/seq/protein?name=~;class=Protein\'", "\'\'", 
						 "\'http://www.wormbase.org/wiki/index.php/Downloads\'"],
				    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
						 'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                                 'Description VARCHAR(255) DEFAULT NULL',
						 'PRIMARY KEY (ID)',
						 'INDEX (Symbol)']);
        %{$GeneTables{GrameneGenes}} = ('NAME' => ['GrameneGenes', 'Gg'],
                                'SYSTEM' => ["\'Gramene Genes Database\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://www.gramene.org/db/genes/search_gene?acc=~\'", "\'\'",
                                             "\'http://www.gramene.org\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{GramenePathway}} = ('NAME' => ['GramenePathway', 'Gm'],
                                'SYSTEM' => ["\'Gramene Pathway\'", "\'$year$mon$mday\'",
                                             "\'ID|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://www.gramene.org/pathway\'", "\'\'",
                                             "\'http://www.gramene.org/pathway\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)'
                                             ]);
        %{$GeneTables{TAIR}} = ('NAME' => ['TAIR', 'A'],
                                'SYSTEM' => ["\'The Arabidopsis Information Resource\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://arabidopsis.org/servlets/Search?type=general&search_action=detail&method=1&show_obsolete=F&sub_type=gene&name=~\'", "\'\'",
                                             "\'http://www.arabidopsis.org\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{TIGR}} = ('NAME' => ['TIGR', 'Ti'],
                                'SYSTEM' => ["\'J. Craig Venter Institute (formerly, The Institute for Genomic Research)\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://www.jcvi.org\'", "\'\'",
                                             "\'http://www.jcvi.org\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{IRGSP}} = ('NAME' => ['IRGSP', 'Ir'],
                                'SYSTEM' => ["\'The International Rice Genome Sequencing Project\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://rgp.dna.affrc.go.jp/IRGSP/\'", "\'\'",
                                             "\'http://rgp.dna.affrc.go.jp/IRGSP/\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{PlantGDB}} = ('NAME' => ['PlantGDB', 'Pl'],
                                'SYSTEM' => ["\'Plant Genome Database\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://www.plantgdb.org\'", "\'\'",
                                             "\'http://www.plantgdb.org\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{NASC}} = ('NAME' => ['NASC', 'N'],
                                'SYSTEM' => ["\'European Arabidopsis Stock Centre\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://arabidopsis.info\'", "\'\'",
                                             "\'http://arabidopsis.info\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);
        %{$GeneTables{UCSC}} = ('NAME' => ['UCSC', 'Uc'],
                                'SYSTEM' => ["\'UCSC Genome Browser\'", "\'$year$mon$mday\'",
                                             "\'ID|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://genome.ucsc.edu/cgi-bin/hgTracks?position=~\'", "\'\'",
                                             "\'http://genome.ucsc.edu\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
					     'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)'
                                             ]);
        %{$GeneTables{EcoGene}} = ('NAME' => ['EcoGene', 'Ec'],
                               'SYSTEM' => ["\'EcoGene\'", "\'$year$mon$mday\'",
                                            "\'ID\|\'", "\'\|$species\|\'", "\'\'",
                                            "\'http://ecogene.org/geneInfo.php?eg_id=~\'", "\'\'",
                                            "\'http://ecogene.org\'"],
                               'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                            'PRIMARY KEY (ID)'
                                            ]);
        %{$GeneTables{WikiGene}} = ('NAME' => ['WikiGene', 'Wg'],
                                'SYSTEM' => ["\'WikiGenes\'", "\'$year$mon$mday\'",
                                             "\'ID|Symbol\\\\sBF|Description\\\\BF\|\'", "\'\|$species\|\'", "\'\'",
                                             "\'http://www.wikigenes.org/e/gene/e/~.html\'", "\'\'",
                                             "\'http://www.wikigenes.org\'"],
                                'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
                                             'Description VARCHAR(255) DEFAULT NULL',
                                             'PRIMARY KEY (ID)',
                                             'INDEX (Symbol)']);


	## ENSEMBL LINK TABLES
	# Hash of Hashes of Arrays
	#####################################################################################
	# Same data structure as with the Gene Tables above, except the top-level keys and  # 
	# certain values have been abstracted and are here automatically defined by the     # 
	# keys manually entered above.  In other words, after adding a new gene table above #
	# the corresponding link table will be automatically generated here.                #
	#####################################################################################
	foreach my $key ( keys %GeneTables){
	    %{$Ensembl_GeneTables{$key}} = ('NAME' => ["Ensembl_${$GeneTables{$key}}{NAME}[0]", "$EnSpeciesCode", "${$GeneTables{$key}}{NAME}[1]"], 
					    'HEADER' => ["\`Primary\` VARCHAR(128) NOT NULL DEFAULT \'\'", 
							 "\`Related\` VARCHAR(128) NOT NULL DEFAULT \'\'", 
							 "INDEX (\`Primary\`)"]);

	    #Table for collecting Attributes for CS table
	    %{$Attributes{$key}} = ('NAME' => ['Attributes']);

	}
	
	#And initialize the Attribute table for Ensembl; not included in foreach loop above
	%{$Attributes{Ensembl}} = ('NAME' => ['Attributes']);
 	
	## ENSEMBL GENE STRUCTURE TABLES
	# Hash of Arrays
	###################################################################################
	# Same data structure as Gene Tables above, except without the top-level hash.    #
	# This set of tables is not likely to change since it is not dependent on         #
	# external ID systems, but rather on the basic dogma of genes, transcripts, exons #
	# and proteins. Modifications to the 'HEADER' fields may be required over time,   #
	# but there is no need to use these Hash names as variables as with Gene Tables.  #
	###################################################################################
	%Ensembl = ('NAME' => ['Ensembl', "$EnSpeciesCode"], 
		    'SYSTEM' => ["\'Ensembl (EBI, Sanger)\'", "\'$year$mon$mday\'", 
				 "\'ID|Symbol\\\\sBF|Description\\\\BF|Chromosome\\\\BF\|\'", "\'\|$species\|\'", "\'$species\'", 
				 "\'http://www.ensembl.org/".$genus_species."/Gene/Summary?g==~\'", "\'\|M\|\'", 
				 "\'ftp.ensembl.org/pub/current_mart/data/mysql/ensembl_mart_".$build."/".$genus_species_abv."_gene_ensembl__gene__main.txt.table.gz\'"],
		    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
				 'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'',
				 'Description VARCHAR(255) DEFAULT NULL', 
				 'Chromosome VARCHAR(15) NOT NULL DEFAULT \'\'',
				 'PRIMARY KEY (ID)',
				 'INDEX (ID, Symbol)']);
	%Ensembl_Exon = ('NAME' => ['Ensembl_Exon'], 
			 'HEADER' => ['Gene VARCHAR(128) NOT NULL DEFAULT \'\'', 
				      'Trans VARCHAR(128) NOT NULL DEFAULT \'\'', 
				      'Exon VARCHAR(128) NOT NULL DEFAULT \'\'',
				      'INDEX (Gene)']);
	%Ensembl_Trans = ('NAME' => ['Ensembl_Trans'], 
			  'HEADER' => ['Gene VARCHAR(128) NOT NULL DEFAULT \'\'', 
				       'Trans VARCHAR(128) NOT NULL DEFAULT \'\'', 
				       'Description VARCHAR(255) DEFAULT NULL',
				       'INDEX (Gene)']);
	%Ensembl_Protein = ('NAME' => ['Ensembl_Protein'], 
			    'HEADER' => ['Gene VARCHAR(128) NOT NULL DEFAULT \'\'', 
					 'Trans VARCHAR(128) NOT NULL DEFAULT \'\'', 
					 'Protein VARCHAR(128) NOT NULL DEFAULT \'\'',
					 'INDEX (Gene)']);
	%Exon = ('NAME' => ['Exon'], 
		 'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
			      'Chr VARCHAR(15) NOT NULL DEFAULT \'\'', 
			      'Start INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			      'Stop INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			      'Strand TINYINT(4) NOT NULL DEFAULT \'0\'',
			      'PRIMARY KEY (ID)',
			      'INDEX (ID)']);
	%Trans = ('NAME' => ['Trans'], 
		  'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
			       'Chr VARCHAR(15) NOT NULL DEFAULT \'\'', 
			       'Start INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			       'Stop INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
			       'Strand TINYINT(4) NOT NULL DEFAULT \'0\'',
			       'PRIMARY KEY (ID)',
			       'INDEX (ID)']);
	%Protein = ('NAME' => ['Protein'], 
		    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
				 'cDNA_Start INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
				 'cDNA_Stop INT(10) UNSIGNED NOT NULL DEFAULT \'0\'',
				 'PRIMARY KEY (ID)',
				 'INDEX (ID)']);
	%ProteinFeatures = ('NAME' => ['ProteinFeatures'], 
			    'HEADER' => ['ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
					 'AA_Start INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
					 'AA_Stop INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
					 'Start INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
					 'Stop INT(10) UNSIGNED NOT NULL DEFAULT \'0\'', 
					 'Name VARCHAR(128) NOT NULL DEFAULT \'\'', 
					 'Interpro VARCHAR(128) NOT NULL DEFAULT \'\'', 
					 'Description VARCHAR(255) DEFAULT NULL',
					 'INDEX (ID)']);
	%Homologs = ('NAME' => ['Homologs'], 
		    'HEADER' => ['Species VARCHAR(128) NOT NULL DEFAULT \'\'',
				 'ID VARCHAR(128) NOT NULL DEFAULT \'\'', 
				 'Symbol VARCHAR(128) NOT NULL DEFAULT \'\'', 
				 'Description VARCHAR(255) DEFAULT NULL',
				 'PRIMARY KEY (ID)',
				 'INDEX (ID, Symbol)']);
	%Ensembl_Homologs = ('NAME' => ['Ensembl_Homologs'], 
			  'HEADER' => ['Gene VARCHAR(128) NOT NULL DEFAULT \'\'', 
				       'Homolog VARCHAR(128) NOT NULL DEFAULT \'\'', 
				       'INDEX (Gene)']);
 
	## TURN OFF INITIALIZATION FLAG
	$initializeTables = 0;        # (DO = 1, DON'T = 0)
    
    } # END: (re)initialize all data tables
    

    ## API: COLLECT GENE INFORMATION
    $gene_stable_id = mysql_quotes($gene->stable_id());
    $gene_symbol = mysql_quotes($gene->external_name()); 
    $Ensembl{$count} = [$gene_stable_id, $gene_symbol, mysql_quotes($gene->description()), mysql_quotes($gene->slice->seq_region_name())];
    my $subcount = 1; #dummy count to support HoHoA sorting and parsing
    $Attributes{Ensembl}{$count.$dot.$subcount} = [$gene_stable_id, mysql_quotes($EnSpeciesCode), mysql_quotes('Symbol'), $gene_symbol];
 
    ## PRINT PROGRESS MESSAGE
    print "Processing $gene_stable_id: $count of $total ";
    if ($collect_sample < $total) {
	print "(sampling $start_count to $end_count)\n";
    }
    else { 
	print "\n";
    }

    ## TEST: EXTRACT ORTHOLOGS
#    parse_Homologs($gene->get_all_homologous_Genes(),
#		   \%Homologs,
#		   \%Ensembl_Homologs);

    ## EXTRACT EXTERNAL ID SYSTEM INFORMATION AND LINKS
    parse_DBEntries($gene->get_all_DBLinks(), 
		    \%GeneTables, 
		    \%Ensembl_GeneTables,
		    \%Attributes);  
    
    ## EXTRACT GENE STRUCTURE INFORMATINO
#    parse_AllTranscripts($gene->get_all_Transcripts(), 
#			 \%Trans, \%Ensembl_Trans, 
#			 \%Exon, \%Ensembl_Exon,
#			 \%Protein, \%Ensembl_Protein, 
#			 \%ProteinFeatures);  


    ## PERIODIC MYSQL LOAD, PRINT OUT AND REINITIALIZATION OF DATA TABLES
    #####################################################################################
    # Occurs with a frequency equal to $purge_frequency (e.g., every 1000 genes) and at # 
    # the end of either sample collection or total genome collection.                   #
    # The main purpose of the periodic purge of data is to clear memory during runtime  #
    # TODO: Identify other potential memory hogs and/or leaks!                          #
    #####################################################################################
    if ($count % $purge_frequency == 0 || $count == ($collect_sample + $start_count - 1)){
	print "\n";

	## LOAD DATA INTO MYSQL TABLES?
	if ($mysql_std_load =~ /(Y|Yes)/i || $mysql_cs_load =~ /(Y|Yes)/i){

            ## CONNECT TO MYSQL (ADMIN=genmapp:fun4gemapp, USER=genmappdb:l3tm31n!)
	    # NOTE: Admin priviledges required to create database
	    my $sqlUser = "genmapp";                    # username
	    my $sqlPass = "fun4genmapp";                # password
	    my $sqlDBLog = "ensembl_etl_device_log";    # permanent log table
	    my $sqlDB = "current_".$genus_species;      # name of species database, based on user-selected species
	    my $sqlCSDB = "current_CS_".$genus_species; # name of species database, based on user-selected species
	    my $sqlConnection ="dbi:mysql:$sqlDBLog";   # connection statement used in DBI->connect()

	    $dbh = DBI->connect($sqlConnection, $sqlUser, $sqlPass)
		or die "Connection Error: $DBI::errstr\n"; 

	    ## IF PURGING FIRST COLLECTION FROM A FRESH START, THEN DROP/CREATE SPECIES DATABASE
	    #####################################################################################
	    # These flags allow you to collect a genome in stages: first collecting say 2000    #
	    # genes, at which point the database is drop/created, then later collecting another #
	    # 8000 genes, at which point the database is NOT drop/created, but simply appended, #
	    # and then finally collecting the remainder of the genes, again without dropping or #
	    # overwriting data from prior runs.                                                 #
	    # In this way, you can work around dropped network connections to Ensembl or other  #
	    # program crashes, etc, and pick up from the last successful mysql load.            # 
	    #####################################################################################
	    if ($mysql_std_load =~ /(Y|Yes)/i){

		if ($first_collection && $start_count == 1){
		    my $sql_db_drop = "DROP DATABASE IF EXISTS $sqlDB";
		    $sth = $dbh->prepare($sql_db_drop);
		    $sth->execute() or die "\nCould not execute $sql_db_drop: $!\n";
		    
		    my $sql_db_create = "CREATE DATABASE $sqlDB";
		    $sth = $dbh->prepare($sql_db_create);
		    $sth->execute() or die "\nCould not execute $sql_db_create: $!\n";
		}

		## CONNECT TO SPECIES DATABASE
		my $sql_db_use = "use $sqlDB";
		$sth = $dbh->prepare($sql_db_use);
		$sth->execute() or die "\nCould not execute $sql_db_use: $!\n";
		
		print "Loading tables into MySQL database $sqlDB:\n";

		## LOAD TABLES INTO MYSQL
		# HoHoA need to be reduced to HoA before loading
		foreach my $key ( keys %GeneTables){
		    mysql_Std_Table(%{$GeneTables{$key}});
		    mysql_Std_Table(%{$Ensembl_GeneTables{$key}});
		}
		# HoA can be directly loaded
		mysql_Std_Table(%Ensembl);
		mysql_Std_Table(%Other);
#		mysql_Std_Table(%Ensembl_Exon);
#		mysql_Std_Table(%Exon);
#		mysql_Std_Table(%Ensembl_Trans);
#		mysql_Std_Table(%Trans);
#		mysql_Std_Table(%Ensembl_Protein);
#		mysql_Std_Table(%Protein);
#		mysql_Std_Table(%ProteinFeatures);
#		mysql_Std_Table(%Homologs);
#		mysql_Std_Table(%Ensembl_Homologs);

		# ENTER DISPLAY ORDER INTO INFO TABLE
		$displayOrder = join("|", @systemTables);
		$Info{1}[5] = "\'\|$displayOrder\|\'";

		## OVERWRITE SUMMARY TABLES EACH COLLECTION
		mysql_Drop(%Info);
		mysql_Std_Table(%Info);
		
		mysql_Drop(%ADMIN_Xrefs);
		mysql_Std_Table(%ADMIN_Xrefs);
		
		mysql_Drop(%Systems);
		mysql_Std_Table(%Systems);
	    }

	    ## LOAD MYSQL CS TABLES
	    if ($mysql_cs_load =~ /(Y|Yes)/i){
		
		if ($first_collection && $start_count == 1){
		    my $sql_db_drop = "DROP DATABASE IF EXISTS $sqlCSDB";
		    $sth = $dbh->prepare($sql_db_drop);
		    $sth->execute() or die "\nCould not execute $sql_db_drop: $!\n";
		    
		    my $sql_db_create = "CREATE DATABASE $sqlCSDB";
		    $sth = $dbh->prepare($sql_db_create);
		    $sth->execute() or die "\nCould not execute $sql_db_create: $!\n";

		    my $sql_gene_create = "CREATE TABLE $sqlCSDB.gene (
					   Code VARCHAR(63) NOT NULL, 
                                           ID VARCHAR(63) NOT NULL, 
					   Symbol VARCHAR(127) NOT NULL, 
					   Name VARCHAR(127) NOT NULL, 
					   Type VARCHAR(127) NOT NULL,
					   Description VARCHAR(254) NOT NULL,
				           Chromosome VARCHAR(15) NOT NULL,
					   Synonyms VARCHAR(254) NOT NULL,
					   Chip VARCHAR(127) NOT NULL, 
					   PRIMARY KEY (ID, Code)
                                           )"; # Primary Key prevents loading of duplicates
		    $sth = $dbh->prepare($sql_gene_create);
		    $sth->execute() or die "\nCould not execute $sql_gene_create: $!\n";

		    my $sql_link_create = "CREATE TABLE $sqlCSDB.link (
                                           ID_Left VARCHAR(63) NOT NULL,
                                           Code_Left VARCHAR(63) NOT NULL,
                                           ID_Right VARCHAR(63) NOT NULL,
                                           Code_Right VARCHAR(63) NOT NULL
                                           )"; # Primary Key not necessary for this table: no duplicates generated
		    $sth = $dbh->prepare($sql_link_create);
		    $sth->execute() or die "\nCould not execute $sql_link_create: $!\n";

                    my $sql_attr_create = "CREATE TABLE $sqlCSDB.attr (
                                           ID VARCHAR(63) NOT NULL,
                                           Code VARCHAR(63) NOT NULL,
                                           Name VARCHAR(63) NOT NULL,
                                           Value VARCHAR(127) NOT NULL,
					   PRIMARY KEY (ID, Code, Name, Value)
                                           )"; # Primary Key prevents loading of duplicates
                    $sth = $dbh->prepare($sql_attr_create);
                    $sth->execute() or die "\nCould not execute $sql_attr_create: $!\n";
		}

		## CONNECT TO SPECIES DATABASE
		my $sql_db_use = "use $sqlCSDB";
		$sth = $dbh->prepare($sql_db_use);
		$sth->execute() or die "\nCould not execute $sql_db_use: $!\n";
    
		print "Loading tables into MySQL database $sqlCSDB:\n";
		
		## LOAD TABLES INTO MYSQL
		# HoHoA need to be reduced to HoA before loading
		foreach my $key ( keys %GeneTables){
		    mysql_CS_Table(%{$GeneTables{$key}});
		    mysql_CS_Table(%{$Ensembl_GeneTables{$key}});
		    mysql_CS_Table(%{$Attributes{$key}});
		}
		# HoA can be directly loaded
		mysql_CS_Table(%Ensembl);
		mysql_CS_Table(%{$Attributes{Ensembl}}); #not included in foreach loop above
#		mysql_Std_Table(%Ensembl_Exon);
#		mysql_Std_Table(%Exon);
#		mysql_Std_Table(%Ensembl_Trans);
#		mysql_Std_Table(%Trans);
#		mysql_Std_Table(%Ensembl_Protein);
#		mysql_Std_Table(%Protein);
#		mysql_Std_Table(%ProteinFeatures);
#		mysql_Std_Table(%Homologs);
#		mysql_Std_Table(%Ensembl_Homologs);

		# ENTER DISPLAY ORDER INTO INFO TABLE
		$displayOrder = join("|", @systemTables);
		$Info{1}[5] = "\'\|$displayOrder\|\'";

		## OVERWRITE SUMMARY TABLES EACH COLLECTION
		mysql_Drop(%Info);
		mysql_Std_Table(%Info);
		
		mysql_Drop(%ADMIN_Xrefs);
		mysql_Std_Table(%ADMIN_Xrefs);
		
		mysql_Drop(%Systems);
		mysql_Std_Table(%Systems);
	    }
	    
	    ## AT THE END OF SAMPLE COLLECTION OR TOTAL GENOME COLLECTION
	    if ($count == ($collect_sample + $start_count - 1)){

		## REGISTER RUN IN LOG TABLE
		my $sql_db_log = "use $sqlDBLog";
		$sth = $dbh->prepare($sql_db_log);
		$sth->execute() or die "\nCould not execute $sql_db_log: $!\n";

		my $sql_insert_log = "INSERT IGNORE INTO log VALUES (\'$year$mon$mday\', \'$hour:$min:$sec\', \'$build_nums\', \'$speciesPick\', \'$genus_species\', \'$total\', \'$collect_sample\', \'$start_count\', \'$displayOrder\')";
		$sth = $dbh->prepare($sql_insert_log);
		$sth->execute() or die "\nCould not execute $sql_insert_log: $!\n";

		print "\nEnsembl_ETL_Device Log --> updated\n";
	    }

	    ## DISCONNECT FROM MYSQL 
	    $dbh -> disconnect;

	} # END: load data into mysql tables
	

	## PRINT DATA TO FLATFILE?
	if ($print_tables =~ /(Y|Yes)/i){

	    ## OPEN OUTPUT FILE 
	    my $mode = '>>';          # append current output file
	    if ($first_collection){
		$mode = '>';          # if first collection, 
	    }
	    unless( open( OUT, "$mode$output")){
		print "Could not open file $output: $!\n";
	    }

            ## PRINT TABLES
	    # HoHoA need to be reduced to HoA before printing
	    foreach my $key ( keys %GeneTables){
		print_Table(%{$GeneTables{$key}});
		print_Table(%{$Ensembl_GeneTables{$key}});
	    }
	    # HoA can be printed directly
	    print_Table(%Ensembl);
#	    print_Table(%Ensembl_Exon);
#	    print_Table(%Exon);
#	    print_Table(%Ensembl_Trans);
#	    print_Table(%Trans);
#	    print_Table(%Ensembl_Protein);
#	    print_Table(%Protein);
#	    print_Table(%ProteinFeatures);
#	    print_Table(%Homologs);
#	    print_Table(%Ensembl_Homologs);
	    
	    ## AT THE END OF SAMPLE COLLECTION OR TOTAL GENOME COLLECTION
	    if ($count == ($collect_sample + $start_count - 1)){
		
		## PRINT SUMMARY TABLES
		print_Table(%Info);
		print_Table(%ADMIN_Xrefs);

		## ONLY PRINT SYSTEMS TABLE IF POPULATED DURING MYSQL LOADING
		if ($mysql_std_load =~ /(Y|Yes)/i){
		    print_Table(%Systems); 
		}    
	    }
	    
	    ## CLOSE OUTPUT FILE
	    close(OUT);
	    print "\nTables printed to $output\n\n";

	} # END: print data to flatfile
	
	## COLLECTION PURGED!
	## SET FIRST_COLLECTION TO FALSE
	$first_collection = 0;                # (TRUE = 1, FALSE = 0)

	## FLAG TO REINITIALIZE DATA TABLES
	$initializeTables = 1;                # (DO = 1, DON'T = 0)                
	
    } # END: periodic mysql load, print out and reinitialization of data tables


    ## INCREMENT GENE COUNTER
    $count++;
	
    ## RESET VALUE TO REDUCE MEMORY LEAK THINGY
    # Not needed if employing while-pop loop in place of foreach
#    $gene = 0;

} # END: loop through each gene in genome


print "\nDONE\n";

## FINISH TIME
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon += 1;
$mon = $zero.$mon unless $mon >= 10;
$mday = $zero.$mday unless $mday >= 10;
$hour = $zero.$hour unless $hour >= 10;
$min = $zero.$min unless $min >= 10;
$sec = $zero.$sec unless $sec >= 10;

push(@Runtime, "End $hour:$min:$sec");
$" = "\n"; #use return to delimit array elements;
print "\n@Runtime\n";

## BACKUP AND COPY OPTIONS
#Variables
if ($dateArg == 0){
	$dateArg = $year.$mon.$mday;
}
my $current_std = "current_".$genus_species;
my $new_std = $twoLetterSpecies."_Std_".$dateArg;
my $current_cs = "current_CS_".$genus_species;
my $new_cs = $twoLetterSpecies."_CS_".$dateArg;
my $sqlPass = "fun4genmapp";
my $bkupDir = "/home/apico/EnsemblAPI/DB_Copies/";
my $mysqldump_cmd = "mysqldump -u genmapp --password=".$sqlPass;
my $mysql_cmd = "mysql -u genmapp --password=".$sqlPass;

## BACKUP and COPY STD TABLES?
if ( $mysql_std_load  =~ /(Y|Yes)/i){
my $bkup_std_default = 'Yes';      # default answer

print "\n\n\tWould you like to backup and copy the Std tables? ($bkup_std_default) --> ";
my $bkup_std = $bkup_std_default;
unless ($scriptmode) {
	$bkup_std = <STDIN>;           # user answer: Y/N flag
	chomp $bkup_std;
	if ($bkup_std eq '') {
    		$bkup_std = $bkup_std_default;  
	}
	until ( $bkup_std =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$bkup_std = <STDIN>;
    		chomp $bkup_std;
	}
}

#If STD
if ($bkup_std  =~ /(Y|Yes)/i){
	my $bkup_std_cmd = $mysqldump_cmd." ".$current_std." > ".$bkupDir.$new_std.".sql";
	system ($bkup_std_cmd);
	print "\n\nSTD tables dumped to ".$bkupDir.$new_std.".sql";
	$bkup_std_cmd = $mysql_cmd." -e \'CREATE DATABASE ".$new_std."\;\'";
	system ($bkup_std_cmd);
	print "\nNew database created: ".$new_std."   loading... ";
        $bkup_std_cmd = $mysql_cmd." ".$new_std." < ".$bkupDir.$new_std.".sql";
        system ($bkup_std_cmd);
	print "\nDatabase loaded: ".$new_std."\n\n";
}
}

## BACKUP and COPY CS TABLES?
if ( $mysql_cs_load  =~ /(Y|Yes)/i){
my $bkup_cs_default = 'Yes';      # default answer

print "\n\n\tWould you like to backup and copy the CS tables? ($bkup_cs_default) --> ";
my $bkup_cs = $bkup_cs_default;
unless ($scriptmode) {
	$bkup_cs = <STDIN>;           # user answer: Y/N flag
	chomp $bkup_cs;
	if ($bkup_cs eq '') {
    		$bkup_cs = $bkup_cs_default;
	}
	until ( $bkup_cs =~ /(Y|Yes|N|No)/i ) {
    		print "\n\nInvalid Entry!!!\nPlease type \"Y\" or \"N\" --> ";
    		$bkup_cs = <STDIN>;
    		chomp $bkup_cs;
	}
}

#If CS
if ($bkup_cs  =~ /(Y|Yes)/i){ 
        my $bkup_cs_cmd = $mysqldump_cmd." ".$current_cs." > ".$bkupDir.$new_cs.".sql";
        system ($bkup_cs_cmd);
        print "\n\nCS tables dumped to ".$bkupDir.$new_cs.".sql";
        $bkup_cs_cmd = $mysql_cmd." -e \'CREATE DATABASE ".$new_cs."\;\'";
        system ($bkup_cs_cmd);
        print "\nNew database created: ".$new_cs."   loading... ";
        $bkup_cs_cmd = $mysql_cmd." ".$new_cs." < ".$bkupDir.$new_cs.".sql";
        system ($bkup_cs_cmd);
        print "\nDatabase loaded: ".$new_cs."\n\n";
}
}

#################################################################################################
## SUBROUTINES ##
#################

## PARSE HOMOLOGS ###############################################################################
# IN: API call for homologous gene keys, plus references to each gene structure data table
# OUT: Data tables are modified directly through references, no variables returned
# Function: To set the values of gene homolog data tables with identifiers and annotations
#  extracted with API calls
#################################################################################################
sub parse_Homologs {
    my ($homologous_genes, $Homologs, $Ensembl_Homologs) = @_;

    my $subcount = 1;
    foreach my $homo (@$homologous_genes){
	my $homo_species = $$homo[2];
	my $homo_stable_id = $$homo[0]->stable_id();
	my $homo_external_name = $$homo[0]->external_name();
	my $homo_description = $$homo[0]->description();
	$$Homologs{$count.$dot.$subcount} = [mysql_quotes($homo_species), mysql_quotes($homo_stable_id), mysql_quotes($homo_external_name), mysql_quotes($homo_description)];
	$$Ensembl_Homologs{$count.$dot.$subcount} = [$gene_stable_id, mysql_quotes($homo_stable_id)];

	++$subcount;
    }
}

## PARSE ALL TRANSCRIPTS ########################################################################
# IN: API call for all transcipt keys, plus references to each gene structure data table
# OUT: Data tables are modified directly through references, no variables returned
# Function: To set the values of gene structure data tables with identifiers and annotations
#  extracted with API calls
#################################################################################################
sub parse_AllTranscripts {
    my ($all_Transcripts, $Trans, $Ensembl_Trans, $Exon, $Ensembl_Exon, $Protein, $Ensembl_Protein, $ProteinFeatures) = @_;

    my $subcount = 1;
    foreach my $trans (@$all_Transcripts) {
	my $trans_stable_id = mysql_quotes($trans->stable_id());

	#TRANSCRIPTS
	if ($trans->translateable_seq()){
	    $$Trans{$count.$dot.$subcount} = feature2array($trans);
	    $$Ensembl_Trans{$count.$dot.$subcount} = [$gene_stable_id, $trans_stable_id, mysql_quotes($trans->description())];
	    #grab seq with: $trans->translateable_seq();

	    #EXONS
	    my $subsubcountExon = 1;
	    foreach my $exon (@{$trans->get_all_Exons()}) {
		$$Exon{$count.$dot.$subcount.$dot.$subsubcountExon} = feature2array($exon);
		$$Ensembl_Exon{$count.$dot.$subcount.$dot.$subsubcountExon} = [$gene_stable_id, $trans_stable_id, mysql_quotes($exon->stable_id())];
		++$subsubcountExon;
	    }

	    #PROTEINS
	    if($trans->translation()) {
		my $transln = $trans->translation();
		my $transln_stable_id = mysql_quotes($transln->stable_id());
		$$Protein{$count.$dot.$subcount} = feature2array_peptide($transln);
		$$Ensembl_Protein{$count.$dot.$subcount} = [$gene_stable_id, $trans_stable_id, $transln_stable_id];
		#grab sequence with: $trans->translate()->seq();

		#PROTEIN FEATURES
		my $protein_feats = $transln->get_all_ProteinFeatures();  # DomainFeatures or ProteinFeatures allowed
		my $subsubcountPF = 1;
		foreach my $pf (@$protein_feats) {
		    my @genomic = $trans->pep2genomic($pf->start(), $pf->end());
		    $$ProteinFeatures{$count.$dot.$subcount.$dot.$subsubcountPF} = [$transln_stable_id, 
										   mysql_quotes($pf->start()), 
										   mysql_quotes($pf->end()), 
										   mysql_quotes($genomic[0]->start()), 
										   mysql_quotes($genomic[-1]->end()),  
										   mysql_quotes($pf->analysis()->logic_name()), 
										   mysql_quotes($pf->interpro_ac()), 
										   mysql_quotes($pf->idesc())];

		    ++$subsubcountPF;
		}
	    }

	    ++$subcount;
	}
    }
}

## PARSE DB ENTRIES #############################################################################
# IN: API call for keys to all database entries, plus references to the main HoHoA data tables
# OUT: Data tables are modified directly through references, no variables returned
# Function: To set the values of gene and link tables with identifiers and annotations extracted
#  with API calls. Also to populate ADMIN_Xrefs with sample of every available DB Entry.
#################################################################################################
sub parse_DBEntries {
  my ($db_entries, $GeneTables, $Ensembl_GeneTables, $Attributes) = @_;
  my %subcount = ();
  my %subsubcount = ();
  my %seen = ();

  foreach my $key ( keys %$GeneTables) {
      $subcount{$key} = 1;
      %{$seen{$key}} = ();
  }

  foreach my $dbe (@$db_entries) {
      my $dbe_dbname = mysql_quotes($dbe->dbname());
      my $dbe_display_id = mysql_quotes($dbe->display_id());
      my $dbe_primary_id = mysql_quotes($dbe->primary_id());
      my $dbe_description = mysql_quotes($dbe->description());
      my $dbe_release = mysql_quotes($dbe->release());
      my $dbe_status = mysql_quotes($dbe->status());
      my $dbe_version = mysql_quotes($dbe->version());
      my $dbe_info_text = mysql_quotes($dbe->info_text());
      my $dbe_info_type = mysql_quotes($dbe->info_type());
      my @dbe_synonyms = $dbe->get_all_synonyms();
      my $dbe_syns = "";
      my @syns = ();
      if (defined(@{$dbe_synonyms[0]})){
	  $dbe_syns = join("|", @{$dbe_synonyms[0]});
      	  foreach my $syn (@{$dbe_synonyms[0]}){
		@syns = (@syns, mysql_quotes($syn));
	  }
      }
      $dbe_syns = mysql_quotes($dbe_syns);


      $ADMIN_Xrefs{$dbe_dbname} = [$dbe_dbname, $dbe_display_id, $dbe_primary_id, $dbe_description, $dbe_syns, 
			     $dbe_release, $dbe_status, $dbe_version, $dbe_info_text, $dbe_info_type];

        ###################################################################################
        # The following IF loop checks for DB Entries that match expected external ID     #
	# system names. Inspect these regular expressions carefully, especially when      #
        # dealing with variable names like 'RefSeq_dna' and 'RefSeq_peptide'. Otherwise   #
	# be as specific as possible, using ^ and $ to restrict the begining and end of   #
        # each match. Also be careful to match the Array of data types and values with    #
        # those indicated in the 'HEADER' Array during initialization.                    #
        #                                                                                 #
	# Add to or Edit these loops to include new ID systems or to make modifications.  #
	###################################################################################
  	if ($dbe_dbname =~ /^\'EntrezGene\'$/){ 
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{EntrezGene}{$dbe_primary_id}}++){
		$$GeneTables{EntrezGene}{$count.$dot.$subcount{EntrezGene}} = [$dbe_primary_id, $dbe_display_id, $dbe_syns];
		$$Ensembl_GeneTables{EntrezGene}{$count.$dot.$subcount{EntrezGene}} = [$gene_stable_id, $dbe_primary_id];
		##copy EntrezGene synonyms and Ensembl gene symbol to Ensembl attributes; NOTE: uses EntrezGene counter
		## SKIP THIS NEXT STEP: too much redundancy and not accurate to link Entrez synonyms to Ensembl IDs
		#$$Attributes{Ensembl}{$count.$dot.$subcount{EntrezGene}} = [$gene_stable_id, mysql_quotes('En'), mysql_quotes('Symbol'), @syns, $gene_symbol]; 
		##process Attributes
		@syns = (@syns, $dbe_display_id);
		$$Attributes{EntrezGene}{$count.$dot.$subcount{EntrezGene}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{EntrezGene}{'NAME'}[1]), mysql_quotes('Symbol'), @syns];
		++$subcount{EntrezGene};
	    }
	}
  	elsif ($dbe_dbname =~ /^\'Uniprot/i){ #catch all types
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{UniProt}{$dbe_primary_id}}++){
		$$GeneTables{UniProt}{$count.$dot.$subcount{UniProt}} = [$dbe_primary_id, $dbe_display_id, $dbe_dbname, $dbe_description, $dbe_syns];
		$$Ensembl_GeneTables{UniProt}{$count.$dot.$subcount{UniProt}} = [$gene_stable_id, $dbe_primary_id];
                ##process Attributes
                ## SKIP THIS STEP: too much information
		#@syns = (@syns, $dbe_display_id);
                #$$Attributes{UniProt}{$count.$dot.$subcount{UniProt}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{UniProt}{'NAME'}[1]), mysql_quotes('Symbol'), @syns];
		++$subcount{UniProt};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'RefSeq/i){ #catch all types: peptide, dna, peptide_predicted, dna_predicted  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{RefSeq}{$dbe_primary_id}}++){
		$$GeneTables{RefSeq}{$count.$dot.$subcount{RefSeq}} = [$dbe_primary_id, $dbe_display_id, $dbe_dbname, $dbe_description];
		$$Ensembl_GeneTables{RefSeq}{$count.$dot.$subcount{RefSeq}} = [$gene_stable_id, $dbe_primary_id];
                ##process Attributes
                ## SKIP THIS STEP: too much information
		++$subcount{RefSeq};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'GO\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{GeneOntology}{$dbe_primary_id}}++){
		$$GeneTables{GeneOntology}{$count.$dot.$subcount{GeneOntology}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{GeneOntology}{$count.$dot.$subcount{GeneOntology}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{GeneOntology};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'AFFY/i){  #catch all types
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{Affy}{$dbe_primary_id}}++){
		$$GeneTables{Affy}{$count.$dot.$subcount{Affy}} = [$dbe_primary_id, $dbe_dbname];
		$$Ensembl_GeneTables{Affy}{$count.$dot.$subcount{Affy}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{Affy};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'Agilent/i){  #catch all types
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{Agilent}{$dbe_primary_id}}++){
		$$GeneTables{Agilent}{$count.$dot.$subcount{Agilent}} = [$dbe_primary_id, $dbe_dbname];
		$$Ensembl_GeneTables{Agilent}{$count.$dot.$subcount{Agilent}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{Agilent};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'Illumina/i){ #catch all types  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{Illumina}{$dbe_primary_id}}++){
		$$GeneTables{Illumina}{$count.$dot.$subcount{Illumina}} = [$dbe_primary_id, $dbe_dbname, $dbe_description];
		$$Ensembl_GeneTables{Illumina}{$count.$dot.$subcount{Illumina}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{Illumina};
	    }
  	}
        elsif ($dbe_dbname =~ /^\'cint\'$/i){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{Cint}{$dbe_primary_id}}++){
		$$GeneTables{Cint}{$count.$dot.$subcount{Cint}} = [$dbe_primary_id, $dbe_dbname];
		$$Ensembl_GeneTables{Cint}{$count.$dot.$subcount{Cint}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{Cint};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'Codelink\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{Codelink}{$dbe_primary_id}}++){
		$$GeneTables{Codelink}{$count.$dot.$subcount{Codelink}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{Codelink}{$count.$dot.$subcount{Codelink}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{Codelink};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'CCDS\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{CCDS}{$dbe_primary_id}}++){
		$$GeneTables{CCDS}{$count.$dot.$subcount{CCDS}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{CCDS}{$count.$dot.$subcount{CCDS}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{CCDS};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'IPI\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{IPI}{$dbe_primary_id}}++){
		$$GeneTables{IPI}{$count.$dot.$subcount{IPI}} = [$dbe_primary_id, $dbe_description];
		$$Ensembl_GeneTables{IPI}{$count.$dot.$subcount{IPI}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{IPI};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'EMBL\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{EMBL}{$dbe_primary_id}}++){
		$$GeneTables{EMBL}{$count.$dot.$subcount{EMBL}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{EMBL}{$count.$dot.$subcount{EMBL}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{EMBL};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'UniGene\'$/i){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{UniGene}{$dbe_primary_id}}++){
		$$GeneTables{UniGene}{$count.$dot.$subcount{UniGene}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
		$$Ensembl_GeneTables{UniGene}{$count.$dot.$subcount{UniGene}} = [$gene_stable_id, $dbe_primary_id];
                ##process Attributes
                ## SKIP THIS STEP: too much information
		++$subcount{UniGene};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'RFAM\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{RFAM}{$dbe_primary_id}}++){
		$$GeneTables{RFAM}{$count.$dot.$subcount{RFAM}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
		$$Ensembl_GeneTables{RFAM}{$count.$dot.$subcount{RFAM}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{RFAM};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'protein_id\'$/){ #Looks like GenPept (transln of GenBank)  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{GenPept}{$dbe_primary_id}}++){
		$$GeneTables{GenPept}{$count.$dot.$subcount{GenPept}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{GenPept}{$count.$dot.$subcount{GenPept}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{GenPept};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'PDB\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{PDB}{$dbe_primary_id}}++){
		$$GeneTables{PDB}{$count.$dot.$subcount{PDB}} = [$dbe_primary_id];
		$$Ensembl_GeneTables{PDB}{$count.$dot.$subcount{PDB}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{PDB};
	    }
  	}
        elsif ($dbe_dbname =~ /^\'.*Grid\'$/){ #ends with 'Grid', e.g. FlyGrid. Anticipate others in the future.
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{BioGrid}{$dbe_primary_id}}++){
                $$GeneTables{BioGrid}{$count.$dot.$subcount{BioGrid}} = [$dbe_primary_id];
                $$Ensembl_GeneTables{BioGrid}{$count.$dot.$subcount{BioGrid}} = [$gene_stable_id, $dbe_primary_id];
                ++$subcount{BioGrid};
            }
        }
    	elsif ($dbe_dbname =~ /^\'MIM/){ #catch all MIM types  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{OMIM}{$dbe_primary_id}}++){
		$$GeneTables{OMIM}{$count.$dot.$subcount{OMIM}} = [$dbe_primary_id, $dbe_dbname, $dbe_description];
		$$Ensembl_GeneTables{OMIM}{$count.$dot.$subcount{OMIM}} = [$gene_stable_id, $dbe_primary_id];
		++$subcount{OMIM};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'miRBase\'$/i){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{miRBase}{$dbe_primary_id}}++){
		$$GeneTables{miRBase}{$count.$dot.$subcount{miRBase}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
		$$Ensembl_GeneTables{miRBase}{$count.$dot.$subcount{miRBase}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ##DISPLAY ID ONLY
		#unless ($dbe_primary_id eq $dbe_display_id){
		#	$Attributes{miRBase}{$count.$dot.$subcount{miRBase}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{miRBase}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		#}
		++$subcount{miRBase};
	    }
  	}
    	elsif ($dbe_dbname =~ /^\'HGNC\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{HUGO}{$dbe_primary_id}}++){ 
		$$GeneTables{HUGO}{$count.$dot.$subcount{HUGO}} = [$dbe_primary_id, $dbe_display_id, $dbe_description, $dbe_syns];
		$$Ensembl_GeneTables{HUGO}{$count.$dot.$subcount{HUGO}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
		##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{HUGO}{$count.$dot.$subcount{HUGO}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{HUGO}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}
		++$subcount{HUGO};
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'MGI\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{MGI}{$dbe_primary_id}}++){
		$$GeneTables{MGI}{$count.$dot.$subcount{MGI}} = [$dbe_primary_id, $dbe_display_id, $dbe_description, $dbe_syns]; 
		$$Ensembl_GeneTables{MGI}{$count.$dot.$subcount{MGI}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{MGI}{$count.$dot.$subcount{MGI}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{MGI}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}	
		++$subcount{MGI}; 
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'RGD\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{RGD}{$dbe_primary_id}}++){
		$$GeneTables{RGD}{$count.$dot.$subcount{RGD}} = [$dbe_primary_id, $dbe_display_id, $dbe_description, $dbe_syns]; 
		$$Ensembl_GeneTables{RGD}{$count.$dot.$subcount{RGD}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                $$Attributes{RGD}{$count.$dot.$subcount{RGD}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{RGD}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		++$subcount{RGD}; 
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'SGD\'$/){  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{SGD}{$dbe_primary_id}}++){
		$$GeneTables{SGD}{$count.$dot.$subcount{SGD}} = [$dbe_primary_id, $dbe_display_id, $dbe_description, $dbe_syns]; 
		$$Ensembl_GeneTables{SGD}{$count.$dot.$subcount{SGD}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                #unless ($dbe_primary_id eq $dbe_display_id){ 
		#go ahead and collect all symnbols since primary ID will be overwritten with proper SGD IDs in post-processing
                $$Attributes{SGD}{$count.$dot.$subcount{SGD}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{SGD}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		#}
		++$subcount{SGD}; 
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'ZFIN/){ #collect both  ID and xpat types  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{ZFIN}{$dbe_primary_id}}++){
		$$GeneTables{ZFIN}{$count.$dot.$subcount{ZFIN}} = [$dbe_primary_id, $dbe_display_id, $dbe_dbname]; 
		$$Ensembl_GeneTables{ZFIN}{$count.$dot.$subcount{ZFIN}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{ZFIN}{$count.$dot.$subcount{ZFIN}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{ZFIN}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}
		++$subcount{ZFIN}; 
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'FlyBase.*gene/i){  #catch all types of gene IDs
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{FlyBase}{$dbe_primary_id}}++){
		$$GeneTables{FlyBase}{$count.$dot.$subcount{FlyBase}} = [$dbe_primary_id, $dbe_display_id, $dbe_dbname, $dbe_syns]; 
		$$Ensembl_GeneTables{FlyBase}{$count.$dot.$subcount{FlyBase}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{FlyBase}{ $count.$dot.$subcount{FlyBase}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{FlyBase}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}
		++$subcount{FlyBase}; 
	    }
  	}
  	elsif ($dbe_dbname =~ /^\'wormbase_gene\'$/i){ #catch only gene IDs  
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
	    if (!${$seen{WormBase}{$dbe_primary_id}}++){
		$$GeneTables{WormBase}{$count.$dot.$subcount{WormBase}} = [$dbe_primary_id, $dbe_display_id, $dbe_description]; 
		$$Ensembl_GeneTables{WormBase}{$count.$dot.$subcount{WormBase}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{WormBase}{ $count.$dot.$subcount{WormBase}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{WormBase}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}
		++$subcount{WormBase}; 
	    }
  	}
        elsif ($dbe_dbname =~ /^\'Gramene_GenesDB\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{GrameneGenes}{$dbe_primary_id}}++){
                $$GeneTables{GrameneGenes}{$count.$dot.$subcount{GrameneGenes}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
                $$Ensembl_GeneTables{GrameneGenes}{$count.$dot.$subcount{GrameneGenes}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ++$subcount{GrameneGenes};
            }
        }
        elsif ($dbe_dbname =~ /^\'Gramene_Pathway\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{GramenePathway}{$dbe_primary_id}}++){
                $$GeneTables{GramenePathway}{$count.$dot.$subcount{GramenePathway}} = [$dbe_primary_id, $dbe_description];
                $$Ensembl_GeneTables{GramenePathway}{$count.$dot.$subcount{GramenePathway}} = [$gene_stable_id, $dbe_primary_id];
                ++$subcount{GramenePathway};
            }
        }
        elsif ($dbe_dbname =~ /^\'IRGSP_Gene\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{IRGSP}{$dbe_primary_id}}++){
                $$GeneTables{IRGSP}{$count.$dot.$subcount{IRGSP}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
                $$Ensembl_GeneTables{IRGSP}{$count.$dot.$subcount{IRGSP}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ++$subcount{IRGSP};
            }
        }
        elsif ($dbe_dbname =~ /^\'TIGR_LOCUS\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{TIGR}{$dbe_primary_id}}++){
                $$GeneTables{TIGR}{$count.$dot.$subcount{TIGR}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
                $$Ensembl_GeneTables{TIGR}{$count.$dot.$subcount{TIGR}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ++$subcount{TIGR};
            }
        }
        elsif ($dbe_dbname =~ /^\'TAIR_LOCUS\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{TAIR}{$dbe_primary_id}}++){
                $$GeneTables{TAIR}{$count.$dot.$subcount{TAIR}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
                $$Ensembl_GeneTables{TAIR}{$count.$dot.$subcount{TAIR}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ##DISPLAY ID ONLY
                unless ($dbe_primary_id eq $dbe_display_id){
                	$$Attributes{TAIR}{ $count.$dot.$subcount{TAIR}} = [$dbe_primary_id, mysql_quotes( $$GeneTables{TAIR}{'NAME'}[1]), mysql_quotes('Symbol'), $dbe_display_id];
		}
                ++$subcount{TAIR};
            }
        }
        elsif ($dbe_dbname =~ /^\'PlantGDB_PUT\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{PlantGDB}{$dbe_primary_id}}++){
                $$GeneTables{PlantGDB}{$count.$dot.$subcount{PlantGDB}} = [$dbe_primary_id, $dbe_primary_id];
                $$Ensembl_GeneTables{PlantGDB}{$count.$dot.$subcount{PlantGDB}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ++$subcount{PlantGDB};
            }
        }
        elsif ($dbe_dbname =~ /^\'NASC_GENE_ID\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{NASC}{$dbe_primary_id}}++){
                $$GeneTables{NASC}{$count.$dot.$subcount{NASC}} = [$dbe_primary_id, $dbe_primary_id, $dbe_description];
                $$Ensembl_GeneTables{NASC}{$count.$dot.$subcount{NASC}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
		## SKIP THIS STEP: too much information
                ++$subcount{NASC};
            }
        }
        elsif ($dbe_dbname =~ /^\'UCSC\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{UCSC}{$dbe_primary_id}}++){
                $$GeneTables{UCSC}{$count.$dot.$subcount{UCSC}} = [$dbe_primary_id, $dbe_description];
                $$Ensembl_GeneTables{UCSC}{$count.$dot.$subcount{UCSC}} = [$gene_stable_id, $dbe_primary_id];
                ++$subcount{UCSC};
            }
        }
        elsif ($dbe_dbname =~ /^\'EcoGene\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{EcoGene}{$dbe_primary_id}}++){
                $$GeneTables{EcoGene}{$count.$dot.$subcount{EcoGene}} = [$dbe_primary_id];
                $$Ensembl_GeneTables{EcoGene}{$count.$dot.$subcount{EcoGene}} = [$gene_stable_id, $dbe_primary_id];
                ++$subcount{EcoGene};
            }
        }   
        elsif ($dbe_dbname =~ /^\'WikiGene\'$/){
            $ADMIN_Xrefs{$dbe_dbname}[10] = "\'Y\'"; # collected
            if (!${$seen{WikiGene}{$dbe_primary_id}}++){
                $$GeneTables{WikiGene}{$count.$dot.$subcount{WikiGene}} = [$dbe_primary_id, $dbe_display_id, $dbe_description];
                $$Ensembl_GeneTables{WikiGene}{$count.$dot.$subcount{WikiGene}} = [$gene_stable_id, $dbe_primary_id];
                #process Attributes
                ## SKIP THIS STEP: too much information
                ++$subcount{WikiGene};
            }
        }
	else {
	    $ADMIN_Xrefs{$dbe_dbname}[10] = "\'N\'"; # not collected!
	}

  } 
} 

## FEATURE TO ARRAY #############################################################################
# IN: An API key to a gene structure feature
# OUT: An Array with standard set of feature attributes
# Function: To extract the standard set of attributes from any given feature key.
#################################################################################################
sub feature2array {
    my $f = shift;

    return [mysql_quotes($f->stable_id()), mysql_quotes($f->slice->seq_region_name()), mysql_quotes($f->start()), mysql_quotes($f->end()), mysql_quotes($f->strand())];
}

## PEPTIDE FEATURE TO ARRAY #####################################################################
# IN: An API key to a peptide feature
# OUT: An Array with standard set of peptide feature attributes
# Function: To extract the standard set of attributes from any given peptide feature key.
#################################################################################################
sub feature2array_peptide {
    my $f = shift;

    return [mysql_quotes($f->stable_id()), mysql_quotes($f->start()), mysql_quotes($f->end())];
}

## DROP TABLE ###################################################################################
# IN: HoA data tables, including those reduced from HoHoA structures
# OUT: No variables returned
# Function: To drop table prior to new data entry where overwriting is desired
#################################################################################################
sub mysql_Drop {
    my (%mysqlHash) = @_;
    my $mysqlName = "${$mysqlHash{'NAME'}}[0]";

    my $sql_create = "DROP TABLE IF EXISTS $mysqlName";
    $sth = $dbh->prepare($sql_create);
    $sth->execute() or die "\nCould not execute $sql_create: $!\n";
}

## MYSQL STD TABLE ##############################################################################
# IN: HoA data tables, including those reduced from HoHoA structures
# OUT: No variables returned
# Function: To create and populate tables in the mysql species database using the information
#  and data values contained in the HoA data tables. In the style of "Std" MSAccess databases.
#################################################################################################
sub mysql_Std_Table {
    my (%mysqlHash) = @_;
    my $mysqlName = "${$mysqlHash{'NAME'}}[0]";
    my $mysqlCode = "${$mysqlHash{'NAME'}}[1]";
    if ($mysqlCode =~ /^En/) { $mysqlCode = 'En';} # replace all species-specific Enmsebl codes with just 'En' for STD databases
    local $" = ", "; #use comma to delimit array elements

    #if hash contains records in addition to NAME, HEADER and SYSTEM, or is the 'Other' table
    if ((scalar keys %mysqlHash > 2 && !$mysqlHash{'SYSTEM'}) || (scalar keys %mysqlHash > 3 && $mysqlHash{'SYSTEM'}) || ($mysqlName eq 'Other')){ 

	my $sql_create = "CREATE TABLE IF NOT EXISTS  $mysqlName (@{$mysqlHash{'HEADER'}})";
	$sth = $dbh->prepare($sql_create);
	$sth->execute() or die "\nCould not execute $sql_create: $!\n";
	
        #Insert data into corresponding mysql table
	foreach my $key (sort by_decimal keys %mysqlHash){
	    unless ($key =~ /^(NAME|HEADER|SYSTEM)$/) {  #skip special 'NAME', 'HEADER' and 'SYSTEM' keys		
		my $sql_insert = "INSERT IGNORE INTO $mysqlName VALUES (@{$mysqlHash{$key}})";
		$sth = $dbh->prepare($sql_insert);
		$sth->execute() or die "\nCould not execute $sql_insert: $!\n";
	    }
	}
	if ($mysqlHash{'SYSTEM'}){
	    
	    unless ($seenSystemTables{$mysqlName}++) {

		#Store codes of system tables only
		push(@systemTables, $mysqlCode);
		
		#Insert system data into Systems Table
		$Systems{$#systemTables} = [mysql_quotes($mysqlName), mysql_quotes($mysqlCode), @{$mysqlHash{'SYSTEM'}}];
	    }
	}
	print "$mysqlName --> loaded\n";	

    } #end if hash contains records
}

## MYSQL CS TABLE ###############################################################################
# IN: HoA data tables, including those reduced from HoHoA structures
# OUT: No variables returned
# Function: To create and populate tables in the mysql species database using the information
#  and data values contained in the HoA data tables. In the style of a "CS" relational database.
#################################################################################################
sub mysql_CS_Table {
    my (%mysqlHash) = @_;
    my $mysqlName = "${$mysqlHash{'NAME'}}[0]";
    my $mysqlCode = "${$mysqlHash{'NAME'}}[1]";
    local $" = ", "; #use comma to delimit array elements
    
    my @tableHeaders = ();
    foreach my $head (@{$mysqlHash{'HEADER'}}){
	$head =~ /^(\w+)\b/;
	push(@tableHeaders, $1) unless $1 =~ /PRIMARY|INDEX/;
    }

    #if 'link' or 'attr' table hash contains records in addition to NAME, HEADER
    if (scalar keys %mysqlHash > 2 && !$mysqlHash{'SYSTEM'}){ 
	#if 'attr' table
	if ($mysqlName eq 'Attributes') {
  	  foreach my $key (sort by_decimal keys %mysqlHash){
            unless ($key =~ /^(NAME|HEADER|SYSTEM)$/) {  #skip special 'NAME', 'HEADER' and 'SYSTEM' keys               
		foreach my $i (3 .. $#{$mysqlHash{$key}}){  #cycle through synonyms stored in hash_of_array[3 .. n]
		    if (!(${$mysqlHash{$key}}[$i] eq "")){
                	my $sql_insert = "INSERT IGNORE INTO attr VALUES (${$mysqlHash{$key}}[0], ${$mysqlHash{$key}}[1], ${$mysqlHash{$key}}[2], ${$mysqlHash{$key}}[$i])";
                	$sth = $dbh->prepare($sql_insert);
                	$sth->execute() or die "\nCould not execute $sql_insert: $!\n";
		    }
		}
	    }
	  }
	}
	#else normal 'link' table
	else {
	  my $mysqlLinkCode = "${$mysqlHash{'NAME'}}[2]";
	  foreach my $key (sort by_decimal keys %mysqlHash){
	    unless ($key =~ /^(NAME|HEADER|SYSTEM)$/) {  #skip special 'NAME', 'HEADER' and 'SYSTEM' keys		
		my $sql_insert = "INSERT IGNORE INTO link VALUES (${$mysqlHash{$key}}[0], \'$mysqlCode\', ${$mysqlHash{$key}}[1], \'$mysqlLinkCode\')";
		$sth = $dbh->prepare($sql_insert);
		$sth->execute() or die "\nCould not execute $sql_insert: $!\n";
	    }
       	  }
	}
	
	print "$mysqlName --> loaded\n";	
    }

    #or, if a 'gene' table hash contains records in addition to NAME, HEADER, and SYSTEM
    elsif (scalar keys %mysqlHash > 3 && $mysqlHash{'SYSTEM'}){
	
	foreach my $key (sort by_decimal keys %mysqlHash){
	    unless ($key =~ /^(NAME|HEADER|SYSTEM)$/) {  #skip special 'NAME', 'HEADER' and 'SYSTEM' keys		
		my $sql_insert = "INSERT IGNORE INTO gene (Code, @tableHeaders) VALUES (\'$mysqlCode\', @{$mysqlHash{$key}})";
		$sth = $dbh->prepare($sql_insert);
		$sth->execute() or die "\nCould not execute $sql_insert: $!\n";
	    }
	
	    unless ($seenSystemTables{$mysqlName}++) {
	    
		#Store codes of system tables only
		push(@systemTables, $mysqlCode);
		
		#Insert system data into Systems Table
		$Systems{$#systemTables} = [mysql_quotes($mysqlName), mysql_quotes($mysqlCode), @{$mysqlHash{'SYSTEM'}}];
	    }
	}

	print "$mysqlName --> loaded\n";	
    }
}

## PRINT TABLE ##################################################################################
# IN: HoA data tables, including those reduced from HoHoA structures
# OUT: No variables returned
# Function: To print out the data contained in the HoA data tables in a tab-delimited format.
#################################################################################################
sub print_Table {
    my (%tableHash) = @_;
    my $tableName = "${$tableHash{'NAME'}}[0]";
    local $" = "\t"; #use tabs to delimit array elements

    #Print Header
    print OUT "$tableName:[HEADER]: \t @{$tableHash{'HEADER'}}\n";
    #Print Data
    foreach my $key (sort by_decimal keys %tableHash){
	unless ($key =~ /^(NAME|HEADER|SYSTEM)$/) {  #skip special 'NAME', 'HEADER' and 'SYSTEM' keys		
	    print OUT "$tableName:[$key]: \t @{$tableHash{$key}}\n";
	}
    }
}


sub by_decimal {
my @levelA = split(/\./, $a);
my @levelB = split(/\./, $b);

if ($levelA[0] > $levelB[0]){
    return 1;
    }
elsif ($levelA[0] < $levelB[0]){
    return -1;
    }
elsif ($levelA[0] == $levelB[0]){
    if ($levelA[1] > $levelB[1]){
	return 1;
	}
    elsif ($levelA[1] < $levelB[1]){
	return -1;
	}
    elsif ($levelA[1] == $levelB[1]){
	if ($levelA[2] > $levelB[2]){
	    return 1;
	    }
	elsif ($levelA[2] < $levelB[2]){
	    return -1;
	    }
	}
    }
}

## PICK FROM ARRAY ##############################################################################
# IN: An Array
# OUT: A string selected from the Array
# FUNCTION: To display a list of options from the Array passed into the routine and allow the
#  user to select from the list.  The selection is returned.
#################################################################################################
sub pickFromArray {
    my @List = @_;

    my $f = 1;
    foreach my $name (@List) {
	print "$f\. $name\n";
	$f++;
    }
    my $max = $f - 1;
    print "\nChoose a number: ";
    my $Number = <STDIN>;
    chomp $Number;

    until ( $Number >= 1 && $Number <= $max ) {
	print "\n\nInvalid Entry!!!\nPlease Pick a number between 1 and $max: ";
	$Number = <STDIN>;
	chomp $Number;
    }

    my $Pick = $List[ $Number - 1 ];
    return $Pick;
}

## MYSQL QUOTES #################################################################################
# IN: A string
# OUT: A string bounded by single quotes with all internal single quotes escaped
# FUNCTION: To prepare strings for mysql statements which are sensitive to single quotes
#################################################################################################
sub mysql_quotes {
    my $string = shift;

    # Escape single quotes for mysql compatibility
    $string =~ s/\'/\\\'/g;

    # Return string with surrounding single quotes
    return "\'$string\'";
} 

# END: subroutines