package Amphora2::rapSearch;

use warnings;
use strict;
use Getopt::Long;
use Cwd;
use Bio::SearchIO;
use Bio::SeqIO;
use Bio::SeqUtils;
use Carp;
use Amphora2::Amphora2;
use File::Basename;
=head1 NAME

Amphora2::blast - Subroutines to blast search reads against marker genes

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Run blast on a list of families for a set of Reads
 
 input : Filename with marker list
         Filename for the reads file


 Output : For each marker, create a fasta file with all the reads and reference sequences.
          Storing the files in a directory called Blast_run

 Option : -clean removes the temporary files created to run the blast
          -threaded = #    Runs blast on multiple processors (I haven't see this use more than 1 processor even when specifying more)

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 RunBlast

=cut

my $clean = 0; #option set up, but not used for later
my $threadNum = 4; #default value runs on 1 processor only.
my $isolateMode=0; # set to 1 if running on an isolate assembly instead of raw reads
my $bestHitsBitScoreRange=30; # all hits with a bit score within this amount of the best will be used
my $pair=0; #used if using paired FastQ files
my @markers;
my (%hitsStart,%hitsEnd, %topscore, %hits, %markerHits,%markerNuc)=();
my $readsCore;
my $custom="";
my %duplicates=();
my %marker_lookup=();
my %frames=();
sub RunRapSearch {
    my $self = shift;
    my $custom = shift;
    my $isolateMode=shift;
    my $reverseTranslate=shift;
    my $markersRef = shift;
    @markers = @{$markersRef};
#    print "MARKER       @markers\n";
    %markerHits = ();
    my $position = rindex($self->{"readsFile"},"/");
    $self->{"readsFile"} =~ m/(\w+)\.?(\w*)$/;
    $readsCore = $1;
    $isolateMode = $self->{"isolate"};
    print "before rapPrepandclean\n";
    rapPrepAndClean($self);
    if($self->{"readsFile_2"} ne ""){
	print "before fastqtoFASTA\n";
	fastqToFasta($self);
    }
#    if(!-e $self->{"blastDir"}."/".$self->{"fileName"}."-6frame"){
#	`$Amphora2::Utilities::translateSixFrame $self->{"readsFile"} > $self->{"blastDir"}/$self->{"fileName"}-6frame`
#    }
    
#        $readsFile = "$blastDir/$fileName-6frame";
    
#    sixFrameTranslation($self);

#    executeBlast($self);
    executeRap($self);
    build_lookup_table($self);
    get_rap_hits($self,$reverseTranslate);
    return $self;
}

=head2 build_lookup_table

=cut

sub build_lookup_table{
    my $self=shift;
    print STDERR "Building the lookup table for all markers";
    foreach my $markName (@markers){
	open(markIN,$Amphora2::Utilities::marker_dir."/".$markName.".faa");
	while(<markIN>){
	    chomp($_);
	    if ($_ =~ m/^>(\S+)/){
		#print $1."\t'".$markName."'\n";
		$marker_lookup{$1}=$markName;
	    }
	}
	close(markIN);
	print STDERR ".";
    }
    print STDERR "\n";
    print STDERR "Building lookup table for hits' frames ... ";
    open(frameIN,$self->{"blastDir"}."/".$readsCore.".rapSearch.aln");
    while(<frameIN>){
	chomp($_);
	next if $_ !~ m/^>/;
	if ($_ =~ m/^>(\S+).+log\(E-value\)=(-\d+\.\d+).+frame=([+-]\d)/){
#	    print "Found a suitable alignment line\n";
	    $self->{"dna"}=1;
	    if(exists $frames{$1}){
#		print "'".@{$frames{$1}}."'\t\'@{$frames{$1}}\'\n";
#		exit;
		if(${$frames{$1}}[1] > $2){
		    $frames{$1}=[$3,$2];
		}else{
		    #do nothing
		}
	    }else{
		$frames{$1}=[$3,$2];
	    }
	    
	}elsif($_ =~ m/^>(\S+).*log\(E-value\)=(\d+\.\d+)/){
	    #no frame displayed the input was in AA format.
	}
    }
    close(frameIN);
    print STDERR "Done.\n";
#    exit;
    return $self;
}


=head2 translationFrame

=cut

sub translateFrame{
    my $id = shift;
    my $seq = shift;
    my $frame = shift;
    my $marker = shift;
    my $reverseTranslate = shift;
    my $returnSeq = "";
    my $newseq = Bio::LocatableSeq->new( -seq => $seq, -id => 'temp');
    my @prots = Bio::SeqUtils->translate_6frames($newseq);
    foreach my $prot (@prots){
	if($prot->id =~ m/-0F/ && $frame eq '+1'){
	    $returnSeq = $prot->seq;
	    last;
	}elsif($prot->id =~ m/-1F/&& $frame eq '+2'){
	    $seq =~ s/^.//; 
	    $returnSeq =  $prot->seq;
	    last;
	}elsif($prot->id =~ m/-2F/&& $frame eq '+3'){
	    $seq =~ s/^..//;
	    $returnSeq =  $prot->seq;
	    last;
        }elsif($prot->id =~ m/-0R/&& $frame eq '-1'){
	    $seq = reverse($seq);
	    $returnSeq = $prot->seq;
	    last;
        }elsif($prot->id =~ m/-1R/&& $frame eq '-2'){
	    $seq = reverse($seq);
	    $seq =~ s/^.//;
	    $returnSeq = $prot->seq;
	    last;
        }elsif($prot->id =~ m/-2R/&& $frame eq '-3'){
	    $seq = reverse($seq);
            $seq =~ s/^..//;
	    $returnSeq = $prot->seq;
	    last;
        }
    }
    if($reverseTranslate){
	if(exists  $markerNuc{$marker}){
	    $markerNuc{$marker} .= ">".$id."\n".$seq."\n";
	}else{
	    $markerNuc{$marker}= ">".$id."\n".$seq."\n";
	}
    }

    return $returnSeq;

}

=head2 executeBlast

=cut

sub executeRap{
    my $self = shift;
    if($self->{"readsFile"} !~ m/^\//){
	print STDERR "Making sure rapsearch can find the readsfile\n";
	$self->{"readsFile"}=getcwd()."/".$self->{"readsFile"};
	print "New readsFile ".$self->{"readsFile"}."\n";
    }
    if($custom ne ""){
	if(!-e $self->{"blastDir"}."/$readsCore.rapSearch.m8"){
	    print "INSIDE custom markers RAPSearch\n";
	    `cd $self->{"blastDir"} ; $Amphora2::Utilities::rapSearch -q $self->{"readsFile"} -d $self->{"blastDir"}/rep -o $readsCore.rapSearch -e -1`;
#	    `cd $self->{"blastDir"} ; $Amphora2::Utilities::rapSearch -query $self->{"blastDir"}/$readsCore-6frame -evalue 0.1 -num_descriptions 50000 -num_alignments 50000 -db $self->{"blastDir"}/rep.faa -out $self->{"blastDir"}/$readsCore.blastp -outfmt 6 -num_threads $threadNum`;
#	    `blastall -p blastp -i $self->{"blastDir"}/$readsCore-6frame -e 0.1 -d $self->{"blastDir"}/rep.faa -o $self->{"blastDir"}/$readsCore.blastp -m 8 -a $threadNum`;
	}
    }else{
	my $dbDir = "$Amphora2::Utilities::marker_dir/representatives";
	if(!-e $self->{"blastDir"}."/$readsCore.rapSearch.m8"){
            print "rapSearch default DB using $self->{\"readsFile\"} \n";
	    `cd $self->{"blastDir"} ; $Amphora2::Utilities::rapSearch -q $self->{"readsFile"} -d $dbDir/rep -o $readsCore.rapSearch -e -1`;
#            `$Amphora2::Utilities::blastp -query $self->{"blastDir"}/$readsCore-6frame -evalue 0.1 -num_descriptions 50000 -num_alignments 50000 -db $dbDir/rep.faa -out $self->{"blastDir"}/$readsCore.blastp -outfmt 6 -num_threads $threadNum`;
        }
    }
    return $self;
}

=head2 sixFrameTranslation

=cut

sub sixFrameTranslation{

    my $self = shift;
    open(readCheck,$self->{"readsFile"}) or die "Couldn't open ".$self->{"readsFile"}."\n";
    my ($totalCount,$seqCount) =0;
    while(<readCheck>){
	chomp($_);
	if($_=~m/^>/){
	    next;
	}
	$seqCount++ while ($_ =~ /[atcgATCGnNmMrRwWsSyYkKvVhHdDbB-]/g);
	$totalCount += length($_);
    }
    close(readCheck);
    print STDERR "DNA % ".$seqCount/$totalCount."\n";
    if($seqCount/$totalCount >0.98){
	print STDERR "Doing a six frame translation\n";
	#found DNA, translate in 6 frames
	`$Amphora2::Utilities::translateSixFrame $self->{"readsFile"} > $self->{"blastDir"}/$readsCore-6frame`;
    }
    return $self;
}

=head2 fastqToFasta

    Writes a fastA file from 2 fastQ files from the Amphora2 object

=cut

sub fastqToFasta{
    my $self = shift;
    if($self->{"readsFile_2"} ne ""){
	print "FILENAME ".$self->{"fileName"}."\n";

	if(!-e $self->{"blastDir"}."/$readsCore.fasta"){
	    my %fastQ = ();
	    my $curr_ID = "";
	    my $skip = 0;
	    print STDERR "Reading ".$self->{"readsFile"}."\n";
	    open(FASTQ_1, $self->{"readsFile"})or die "Couldn't open ".$self->{"readsFile"}." in run_blast.pl reading the FastQ file\n";
	    while(<FASTQ_1>){
		chomp($_);
		if($_ =~ m/^@(\S+)/){
		    $curr_ID =$1;
		    $skip =0;
		}elsif($_ =~ m/^\+$curr_ID/){
		    $skip = 1;
		}else{
		    if($skip ==0){
			$fastQ{$curr_ID}=$_;
		    }else{
			#do nothing
		    }
		}
	    }
	    close(FASTQ_1);
	    print STDERR "Reading ".$self->{"readsFile_2"}."\n";
	    open(FASTQ_2, $self->{"readsFile_2"})or die "Couldn't open ".$self->{"readsFile_2"}." in run_blast.pl reading the FastQ file\n";
	    while(<FASTQ_2>){
		chomp($_);
		if($_ =~ m/^@(\S+)/){
		    $curr_ID =$1;
		    $skip =0;
		}elsif($_ =~ m/^\+$curr_ID/){
		    $skip = 1;
		}else{
		    if($skip ==0){
			my $reverse = reverse $_;
			$fastQ{$curr_ID}.=$reverse;
		    }else{
			#do nothing
		    }
		}
	    }
	    close(FASTQ_2);
	    print STDERR "Writing ".$readsCore.".fasta\n";
	    open(FastA, ">".$self->{"blastDir"}."/$readsCore.fasta")or die "Couldn't open ".$self->{"blastDir"}."/$readsCore.fasta for writing in run_blast.pl\n";
	    foreach my $id (keys %fastQ){
		print FastA ">".$id."\n".$fastQ{$id}."\n";
	    }
	    close(FastA);
	}
    
	#pointing $readsFile to the newly created fastA file
	$self->{"readsFile"} = $self->{"blastDir"}."/$readsCore.fasta";
    }
    return $self;
}

=head2 get_blast_hits

parse the blast file

=cut


sub get_rap_hits{
    my %duplicates = ();
    my $self = shift;
    my $reverseTranslate=shift;
    #parsing the blast file
    # parse once to get the top scores for each marker
    my %markerTopScores;
    my %topFamily=();
    my %topScore=();
    my %topStart=();
    my %topEnd=();
    open(blastIN,$self->{"blastDir"}."/$readsCore.rapSearch.m8")or die "Couldn't open ".$self->{"blastDir"}."/$readsCore.rapSearch.m8\n";
    while(<blastIN>){
	chomp($_);
	next if($_ =~ /^#/);
	my @values = split(/\t/,$_);
	my $query = $values[0];
	my $subject = $values[1];
	my $query_start = $values[6];
	my $query_end = $values[7];
	my $bitScore = $values[11];
#	my @marker=split(/\_/,$subject);
	my $markerName = $marker_lookup{$subject};
#	print "BLAST ".$query."\n";
	if($query =~ m/(\S+)_([rf][012])/){
	    #print "PARSING BLAST\n";
	    if(exists $duplicates{$1}{$markerName}){
		foreach my $suff (keys (%{$duplicates{$1}{$markerName}})){
		    if($bitScore > $duplicates{$1}{$markerName}{$suff}){
			delete($duplicates{$1}{$markerName}{$suff});
			$duplicates{$1}{$markerName}{$2}=$bitScore;
		    }else{
			#do nothing;
		    }
		}
	    }else{
		$duplicates{$1}{$markerName}{$2}=$bitScore;
	    }
	}

	#parse once to get the top score for each marker (if isolate is ON, parse again to check the bitscore ranges)
	if($isolateMode==1){
	    # running on a genome assembly
	    # allow only 1 marker per sequence (TOP hit)
	    if( !defined($markerTopScores{$markerName}) || $markerTopScores{$markerName} < $bitScore ){
		$markerTopScores{$markerName} = $bitScore;
		$hitsStart{$query}{$markerName} = $query_start;
		$hitsEnd{$query}{$markerName}=$query_end;
	    }
#	}
#	if($isolateMode==1){
	    # running on a genome assembly
	    # allow more than one marker per sequence
	    # require all hits to the marker to have bit score within some range of the top hit
#	    if($markerTopScores{$markerName} < $hit->bits + $bestHitsBitScoreRange){
#		$hits{$hitName}{$markerHit}=1;
#		$hitsStart{$hitName}{$markerName} = $query_start;
#		$hitsEnd{$hitName}{$markerName} = $query_end;
#	    }
	}else{
	    # running on reads
	    # just do one marker per read
	    if(!exists $topFamily{$query}){
		$topFamily{$query}=$markerName;
		$topStart{$query}=$query_start;
		$topEnd{$query}=$query_end;
		$topScore{$query}=$bitScore;
	    }else{
		#only keep the top hit
		if($topScore{$query} <= $bitScore){
		    $topFamily{$query}= $markerName;
		    $topStart{$query}=$query_start;
		    $topEnd{$query}=$query_end;
		    $topScore{$query}=$bitScore;
		}#else do nothing
	    }#else do nothing
	}
    }
    close(blastIN);
    if($isolateMode ==1){
	# reading the output a second to check the bitscore ranges from the top score
	open(blastIN,$self->{"blastDir"}."/$readsCore.blastp")or die "Couldn't open ".$self->{"blastDir"}."/$readsCore.blastp\n";
	# running on a genome assembly
	# allow more than one marker per sequence
	# require all hits to the marker to have bit score within some range of the top hit
	while(<blastIN>){
	    chomp($_);
	    my @values = split(/\t/,$_);
	    my $query = $values[0];
	    my $subject = $values[1];
	    my $query_start = $values[6];
	    my $query_end = $values[7];
	    my $bitScore = $values[11];
	    my $markerName = $marker_lookup{$subject};
	    if($markerTopScores{$markerName} < $bitScore + $bestHitsBitScoreRange){
		$hits{$query}{$markerName}=1;
		$hitsStart{$query}{$markerName} = $query_start;
		$hitsEnd{$query}{$markerName} = $query_end;
	    }
	}
	close(blastIN);
    }else{
	foreach my $queryID (keys %topFamily){
	    $hits{$queryID}{$topFamily{$queryID}}=1;
	    $hitsStart{$queryID}{$topFamily{$queryID}}=$topStart{$queryID};
	    $hitsEnd{$queryID}{$topFamily{$queryID}}=$topEnd{$queryID};
	}
    }
    my $seqin;
    if(-e $self->{"blastDir"}."/$readsCore-6frame"){
	$seqin = new Bio::SeqIO('-file'=>$self->{"blastDir"}."/$readsCore-6frame");
    }else{
	print "ReadsFile:  $self->{\"readsFile\"}"."\n";
	$seqin = new Bio::SeqIO('-file'=>$self->{"readsFile"});
    }
    while (my $seq = $seqin->next_seq) {
	if(exists $hits{$seq->id}){
	    foreach my $markerHit(keys %{$hits{$seq->id}}){
		#print STDERR $seq->id."\t".$seq->description."\n";
		#checking if a 6frame translation was done and the suffix was appended to the description and not the sequence ID
		my $newID = $seq->id;
		my $current_suff="";
		my $current_seq="";
		if($seq->description =~ m/(_[fr][012])$/ && $seq->id !~m/(_[fr][012])$/){
		    $newID.=$1;
		}
		#create a new string or append to an existing string for each marker
		if($seq->id =~ m/(\S+)_([fr][012])/){
		    $current_suff=$2;
		    $current_seq = $1;
		}
		if(exists $duplicates{$current_seq}{$markerHit}{$current_suff}){
		    print "Skipping ".$seq->id."\t".$current_suff."\n";
		    next;
		}
		#print "not skipping\t";
		#pre-trimming for the query + 150 residues before and after (for very long queries)
		my $start = $hitsStart{$seq->id}{$markerHit}-150;
		if($start < 0){
		    $start=0;
		}
		my $end = $hitsEnd{$seq->id}{$markerHit}+150;
		my $seqLength = length($seq->seq);
		if($end >= $seqLength){
		    $end=$seqLength;
		}
		my $newSeq = substr($seq->seq,$start,$end-$start);
		#if the $newID exists in the %frames hash, then it needs to be translated to the correct frame
		if(exists $frames{$newID}){
#		    print "Translating $newID\n";
		    
                    my $translatedSeq = translateFrame($newID,$seq->seq,${$frames{$newID}}[0],$markerHit,$reverseTranslate);
#		    print "End : $end\tStart: $start\n";
#		    print "Legnth of string\t".length($translatedSeq);
		    $newSeq = substr($translatedSeq,$start/3,(($end-$start)/3));
                }
		if(exists  $markerHits{$markerHit}){
		    $markerHits{$markerHit} .= ">".$newID."\n".$newSeq."\n";
		}else{
		    $markerHits{$markerHit} = ">".$newID."\n".$newSeq."\n";
		}
#		if($reverseTranslate && $self->{"dna"}==1){
#		    if(exists  $markerNuc{$markerHit}){
#			$markerNuc{$markerHit} .= ">".$newID."\n".$seq->seq."\n";
#		    }else{
#			$markerNuc{$markerHit}= ">".$newID."\n".$seq->seq."\n";
#		    }
#		}
	    }
	}
    }
#    print "Writtenmarkers\t".keys(%markerHits)."\n";
    #write the read+ref_seqs for each markers in the list
    foreach my $marker (keys %markerHits){
	#writing the hits to the candidate file
	open(fileOUT,">".$self->{"blastDir"}."/$marker.candidate")or die " Couldn't open ".$self->{"blastDir"}."/$marker.candidate for writing\n";
	print fileOUT $markerHits{$marker};
	close(fileOUT);
	if($reverseTranslate && $self->{"dna"}==1){
	    open(fileOUT,">".$self->{"blastDir"}."/$marker.candidate.ffn")or die " Couldn't open ".$self->{"blastDir"}."/$marker.candidate.ffn for writing\n";
	    print fileOUT $markerNuc{$marker};
	    close(fileOUT);
	}
	
    }
#    exit;
    return $self;
}

=head2 blastPrepAndClean

=item *

Checks if the directories needed for the blast run and parsing exist
Removes previous blast runs data if they are still in the directories
Generates the blastable database using the marker representatives

=back

=cut

sub rapPrepAndClean {
    my $self = shift;
    print STDERR "RAPprepclean MARKERS @markers\nTESTING\n ";
    `mkdir $self->{"tempDir"}` unless (-e $self->{"tempDir"});
    #create a directory for the Reads file being processed.
    `mkdir $self->{"fileDir"}` unless (-e $self->{"fileDir"});
    `mkdir $self->{"blastDir"}` unless (-e $self->{"blastDir"});
    if($custom ne ""){
	#remove rep.faa if it already exists (starts clean is a previous job was stopped or crashed or included different markers)
	if(-e $self->{"blastDir"}."/rep.faa"){ `rm $self->{"blastDir"}/rep.faa`;}
	#also makes 1 large file with all the marker sequences
	foreach my $marker (@markers){
	    #if a marker candidate file exists remove it, it is from a previous run and could not be related
	    if(-e $self->{"blastDir"}."/$marker.candidate"){
		`rm $self->{"blastDir"}/$marker.candidate`;
	    }
	    #initiate the hash table for all markers incase 1 marker doesn't have a single hit, it'll still be in the results 
	    #and will yield an empty candidate file
	    $markerHits{$marker}="";
	    #append the rep sequences for all the markers included in the study to the rep.faa file
	    `cat $Amphora2::Utilities::marker_dir/$marker.faa >> $self->{"blastDir"}/rep.faa`
	}
	#make a blastable DB
	if(!-e $self->{"blastDir"}."/rep.des" ||  !-e $self->{"blastDir"}."/rep.fbn" || !-e $self->{"blastDir"}."/rep.inf" || !-e $self->{"blastDir"}."/rep.swt"){
	    `cd $self->{"blastDir"} ; $Amphora2::Utilities::preRapSearch -d $self->{"blastDir"}/rep.faa -n rep`;
        }
    }else{
	#when using the default marker package
	my $dbDir = "$Amphora2::Utilities::marker_dir/representatives";
	print STDERR "Using the standard marker package\n";
	print STDERR "Using $dbDir as default directory\n";
	if(!-e "$dbDir/rep.faa"){
	    print "testing_2\n";
	    foreach my $marker (@markers){
		$markerHits{$marker}="";
		`cat $Amphora2::Utilities::marker_dir/$marker.faa >> $dbDir/rep.faa`;
	    }
	}
	if(!-e "$dbDir/rep.des" ||  !-e "$dbDir/rep.fbn" || !-e "$dbDir/rep.inf" || !-e "$dbDir/rep.swt"){
		`cd $dbDir ; $Amphora2::Utilities::preRapSearch -d rep.faa -n rep`;
	}
    }
    return $self;
}

=head1 AUTHOR

Aaron Darling, C<< <aarondarling at ucdavis.edu> >>
Guillaume Jospin, C<< <gjospin at ucdavis.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-amphora2-amphora2 at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Amphora2-Amphora2>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Amphora2::blast


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Amphora2-Amphora2>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Amphora2-Amphora2>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Amphora2-Amphora2>

=item * Search CPAN

L<http://search.cpan.org/dist/Amphora2-Amphora2/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Aaron Darling and Guillaume Jospin.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Amphora2::blast.pm
