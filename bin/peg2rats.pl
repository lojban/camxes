#!/usr/bin/perl

use File::Basename qw{dirname};
use File::Path qw{make_path};
use Data::Dumper;

my $nomorerats=0;
my $allmorph=0;
my $morphfile=0;
my $allspace=0;

my $destination_path = shift @ARGV;
my $destination_dir = dirname($destination_path);
-d $destination_dir
  or make_path($destination_dir)
  or die "Couldn't make path '$destination_dir'";
open OUT, '>', $destination_path
  or die "Couldn't open '$destination_path' for writing";
my $SELECTED = select OUT;

while(<>)
{

    if ($ARGV =~ /\.rats/) {
      print $_;
      next;
    }

    my $norats=0;
    my $transient=0;
    my $type="normal";

    if( /^; --- NORATS ---$/ )
    {
	$nomorerats=1;
    }

    if( /^; --- MORPHOLOGY FILE ---$/ )
    {
	$morphfile=1;
    }

    if( /^; --- MORPHOLOGY ---$/ )
    {
	$allmorph=1;
	$allspace=0;
    }

    if( /^; --- SPACE ---$/ )
    {
	$allspace=1;
	$allmorph=0;
    }

    if( /^; --- SELMAHO ---$/ )
    {
	$allspace=0;
	$allmorph=0;
    }

    if( $allmorph )
    {
	$type="morphology";
    }

    if( $allspace )
    {
	$type="whitespace";
    }

    if( /NORATS/ )
    {
	s/NORATS //;
	$norats=1;
    }

    if( /TRANSIENT/ )
    {
	s/TRANSIENT //;
	$transient=1;
    }

    if( /MORPHOLOGY/ )
    {
	s/^MORPHOLOGY //;
	$type="morphology";
    }

    if( /SPACE/ )
    {
	s/^SPACE //;
	$type="whitespace";
    }

    if( /PUBLIC/ )
    {
	s/^PUBLIC //;
	$type="public";
    }

    if( /^;/ ) # If comment
    {
	s!^;!//!;
	print;
	next;
    }

    if( /^\s*$/ )
    {
	print;
	next;
    }

    # Add type and change <- to =
    if( $morphfile == 1 )
    {
	s/^(\S+) <- /String \1-morph = /;
    } else {
	if( $type eq "public" )
	{
	    s/^(\S+) <- /public String \1 = /;
	} else {
	    s/^(\S+) <- /String \1 = /;
	}
    }

    # Fix - and _
    s/[-_](.)/\u$1/g;

    # Add trailing ;
    s/(\S+.*)$/\1;/g;

    if( $morphfile == 1 )
    {
	# Seperate into two halves before and after =
	$start = $_;
	$start =~ s/Morph = .*/Morph = /;
	chomp( $start );
	$end = $_;
	$end =~ s/.*Morph = (.*)/\1/;

	# Add Morph to the second half.
	$end =~ s/(?<![\[\]\\])\b(\w+)\b(?![\[\]\\])/\1Morph/g;

	$_ = $start . $end;
    }

    # Turn . to _ (*sigh*)
    if( ! /[[]/ )
    {
	s/(\W)\.(\W)/${1}_${2}/g;
    }

    ######
    # This part is where we add in the Rats! specific code to
    #  generate a parse tree (and maybe other things down the line).
    #
    # This is very complicated!
    ######
    
    if( ! $norats && ! $nomorerats )
    {
	$pre = $_;
	$pre =~ s/([^=]*)=.*/$1/;
	$post = $_;
	$post =~ s/[^=]*=(.*)/$1/;
	$post =~ s/;\s*$//s;
	chomp $pre;

	$post = realWork($post, 1, $type);
	$post =~ s/NULL/( { yyValue = "" ; } )/;

	$_ = $pre . " = " . $post . ";\n";
    }

    s/OPENSQUARE/[/g;
    s/CLOSESQUARE/]/g;

    if( $transient == 1 || $norats == 1 )
    {
	s/^/transient /;
    }

    print;
}

select $SELECTED;
close OUT;
exit;

sub realWork
{
    my (@names, $i, @stuff, $j, $parens, $semi, $top, $type);
    $i=0; $j=0; $parens=0, $semi=0;

    $_ = $_[0];
    $top = $_[1];  # Marks if this is the top-most recursion.
    $type = $_[2];   # Marks the type of string processing to do.
    $countref = $_[3];  # Used to have seperator numbers increment
			# across / seperated sections of a line.

    if( $countref )
    {
	$i = $$countref;
	## print "countref gives: $i.\n";
    }

    s/[[]/OPENSQUARE/g;
    s/[]]/CLOSESQUARE/g;

    # Match balanced parens
    $reparen = qr{
	\(
	    (?:
	     (?> [^()]+ )    # Non-parens without backtracking
	     |
	     (??{ $reparen })     # Group with matching parens
	    )*
	\)
    }x;

    #print "realwork_pre: :$_:\n";

    # If we have *nothing* but &FOO:
    if( /^\s*(([&!][a-zA-Z]+\s*)+)\s*$/ )
    {
	return " $1 { yyValue = \"\"; } ";
    }

    # Recursion back-out.
    if( ! /[a-zA-Z]/ )
    {
	return;
    }

    # Catch bare () productions
    if( /^\s*\(\s*\)\s*$/ || /^\s*\( \{ yyValue = \"\"; \} \)\s*$/ )
    {
	return "NULL";
    }

    # Strip outermost parens if this production consists of only a paren statement
    if( /^\(.*\)$/ )
    {
	s/\((.*)\)/$1/g;
	$parens=1;
    }
    ## print "realwork: $_.\n";

    # This section deals with semantic (curly-brace) expressions by
    # replacing the text of the semantic expression with "PARSERstuff<num>"
    s/([&!^]?\{[^}]*\})/
	my $first=$1;
	$j++;
	@stuff[$j] = $first;
	"SPECIALPARSERstuff$j";
    /exg;

    # This section deals with parenthetical expressions within the current production
    # by seperating them out and calling realWork on them recursively.  It also
    # replaces the text of the parenthetical expression with "PARSERstuff<num>"
    # so that things don't get acted on too many times.
    s/([^(]*[^(-:]?)($reparen)(\S*)/
	## print "rw1: $1--rw2: $2--$3.\n";
	my $first=$1;
	my $second=$2;
	my $third=$3;
	$j++;
	my $result=$first . "PARSERstuff$j" . $third;

	# If the paren production is empty.
	if( $second =~ m{^\s*\(\s*\)\s*$} ) {
	    $j--;
	    $result=$first . NULL . $third;
	# Else If the paren production is preceded by ! or &, do nothing.
	} elsif( $first =~ m{[!&]\s*$} ) {
	    @stuff[$j] = $second;
	# Else If the paren prod is a repeater, special handling due to Rats! bug.
	} elsif( $third =~ m{^\s*[*+]} ) {
	    @stuff[$j] = realWork($second, 0, $type);
	# Default case.
	} else {
	    ## print "Before work: $result.\n";
	    @stuff[$j] = realWork($second, 0, $type );
	    ## print "PARSERstuff$j: @stuff[$j]\n";
	    ## print "After work: $result.\n";
	}
	$result;
    /exg;
    ## print "After reparen1: $_.\n";

    # Here we test for disjunctions (/) and pass each setion back to realWork.
    my $slashed=0;
    if( 
	# Make sure there's something next to the slash, otherwise we're at the wrong level.
	( m/^.*[a-zA-Z].*\/[^()]*[a-zA-Z][^()]*$/ ) ||
	( m/^[^()]*[a-zA-Z][^()]*\/.*[a-zA-Z].*$/ ) ||
	( m/^.*[a-zA-Z].*\/[^()]*$reparen[^()]*$/x ) ||
	( m/^[^()]*$reparen[^()]*\/.*[a-zA-Z].*$/x )
    )
    {
	$slashed=1;
	my $count=0;

	## print "Doing slash on $_.\n";
	# Handle all but the last section.
	s{([^/]+)/}{
	    ## print "slash: $1.\n";
	    realWork($1, 0, $type, \$count) . "/ $2";
	}eg;

	## print "After slash: $_.\n";
	# Handle the last section.
	s{^(.*)/([^/]+)$}{
	    ## print "slash2: $2.\n";
	    "$1/ " . realWork($2, 0, $type, \$count);
	}eg;
	## print "After slash2: $_.\n";
    }

    ###
    # Naming (i.e. turning A <- B C into A <- b:B c:C)
    ###

#     # We don't want to name a sole element; that should just recurse normally.
#     my (@counter, $count);
#     $count = 0;
#     if( m/\b(?<![!&:])([a-zA-Z][^:\s]*)(?!:)\b/ )
#     {
# 	# However, A !B !C doesn't count as a sole element for these purposes,
# 	# so the regex below is not what you'd normally expect.
# 	@counter = m/([a-zA-Z][^:\s]*)(?!:)\b/g;
# 	$count = $#counter + 1;
#     }
# 
#     ## print "count: $count \n";

    # We don't want to name elements seperated by /
    if( ! $slashed )
    {
	s/\b(?<![!&:])([a-zA-Z][^:\s]*)(?!:)\b/
	    ## print "Naming $1.\n";
	    if( $1 =~ m{(^PARSERstuff.*)} )
	    {
		## print "paren $1.\n";
		$i++; @names[$i] = "PARSERparen$i"; "PARSERparen$i:$1";
	    } elsif( $1 =~ m{^\s*NULL\s*$} ) {
		"NULL"; 
	    } elsif( $1 =~ m{^(SPECIALPARSERstuff.*)} ) {
		$1
	    } else {
		## print "no paren $1.\n";
		$before = $1;
		$after = $1;
		$before =~ s;OPENSQUARE.*CLOSESQUARE;SQUARE;g;
		$i++; @names[$i] = "${before}SEP$i";
		"${before}SEP$i:$after";
	    }
	/eg;
	## print "Names: " . Dumper(\@names) . ".\n"; 
    }
    ## print "After names: $_.\n";

    # Turn PARSERstuff back into its actual value
    if( $j > 0 ) { 
	## print "Stuff: " . Dumper(\@stuff) . ".\n"; 
	s{\bPARSERstuff(\d+)}{$stuff[$1];}exg;
	s{\bSPECIALPARSERstuff(\d+)}{$stuff[$1];}exg;
    }
    ## print "After stuff: $_.\n";

    # Build the yyValue construction at the end.
    if( @names )
    {
	$_ .= " { yyValue = ";
	for my $elem (@names)
	{
	    if( $elem && m/$elem/ )
	    {
		my $elem2;
		$elem2 = $elem;
		$elem2 =~ s/SEP\d+//;

		if( $elem =~ m/PARSERparen/ || $elem =~ m/SQUARE/ )
		{
		    $local_type = "parserParen";
		} else {
		    $local_type = $type;
		}

		#print "mscall: makeString( \" $elem2=(\", $elem, \") \", \"$local_type\" ) + \n";
		$_ .= " makeString( \"$elem2\", $elem, \"$local_type\", false ) + ";
	    }
	}
	s/\s*\+\s*$//;
	$_ .= " ; } ";
    }

    # Put parens back on.
    if( $parens )
    {    
	$_ = "($_)";
    }

    s/!\./!\. { yyValue = "EOF"; }/;

    ## print "Setting countref to $i.\n";
    $$countref = $i;

    ## print "Returning $_\n";
    return $_;
}
