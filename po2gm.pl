#!/usr/bin/perl
#  Copyright 2012 Kevin Scannell
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Locale::PO;

if (scalar @ARGV != 2) {
	die "Usage: $0 TARGETLANG AMBIENTLANG\n";
}

sub insert_backref {
	(my $target, my $var, my $var_number) = @_;
	$target =~ s/$var/"+"\$$var_number"+"/;
	return $target;
}

# First argument is the escaped source string, e.g. %a likes %a\.
# or in case of an alternate source language, %a aime %a\.
# Second argument is the escaped target string, e.g. Plijet eo %a gant %a
# Returns the target string, double-quoted, with each % variable
# replaced by a backref $2, $3, $4, ...  ($1 reserved for left-hand boundary)
sub insert_all_backrefs {
	(my $source, my $target) = @_;
	$target = "\"$target\"";
	my $var_number = 1; # count parentheticals, left to right
	while ($source =~ m/(%[A-Za-z][1-9]?)/g) {
		$var_number++;
		$target = insert_backref($target, $1, $var_number);
	}
	$target =~ s/""\+//g;
	$target =~ s/\+""$//;
	return $target;
}

sub escape_regex {
	(my $r) = @_;
	$r =~ s/'/\\'/g;
	$r =~ s/([.])/\\$1/g;
	$r =~ s/[?]$/\\\\?/g;    # don't escape non-terminal ? (used as regex in es.po, fr.po)
	$r =~ s/([()])/\\\\$1/g; # Spanish has literal parens, like "la(s)"
	return $r;
}

# keys are regexen that match English source strings (even if ambient != 'en')
# values are refs to arrays containing "src|target" strings
# like "post|phostáil", "photo|ghrianghraf"  (src may be non-en!)
my %contexts;
my %plural_regex;
my %formats;
my @lowpriority;
my $targetlang = $ARGV[0];
my $ambient = $ARGV[1];
my %source; # maps English to whatever ambient language is (maybe en!)
$formats{'%A'} = '%A'; # simple days of the week: "Saturday"
$formats{'%B'} = '%B'; # simple month names: "February"

open(PLURALS, "<:utf8", "plurals.txt") or die "Could not open plural form file: $!";
while (<PLURALS>) {
	chomp;
	(my $code, my $num, my $regex) = m/^([A-Za-z-]+)\t([0-9])\t(.+)$/;
	$plural_regex{$num} = $regex if ($code eq $targetlang);
}
close PLURALS;

unless ($ambient eq 'en') {
	my $aref = Locale::PO->load_file_asarray("po/$ambient.po");
	shift @$aref;
	foreach my $msg (@$aref) {
		next if $msg->fuzzy();
		my $id = $msg->msgid();
		my $plural_id = $msg->msgid_plural();
		if (defined($plural_id)) {
			my $plural_hashref = $msg->msgstr_n();
			if (scalar keys %{$plural_hashref} != 2) {
				print STDERR "Warning: Alternate source language must have nplurals==2\n";
			}
			else {
				my $str = $msg->dequote($plural_hashref->{'0'}); 
				$source{$msg->dequote($id)} = $str unless ($str eq '');
				$str = $msg->dequote($plural_hashref->{'1'}); 
				$source{$msg->dequote($plural_id)} = $str unless ($str eq '');
			}
		}
		else {
			my $str = $msg->dequote($msg->msgstr());
			if (!defined($str)) {
				print STDERR "problem; str not defined for msgid = $id\n";
			}
			$source{$msg->dequote($id)} = $str unless ($str eq '');
		}
	}
}

# return undef if I don't know the string in the alternate source lang
sub get_source_string {
	(my $str) = @_;
	if ($ambient eq 'en') {
		return $str;
	}
	else {
		if (exists($source{$str})) {
			return $source{$str};
		}
		else {
			return undef;
		}
	}
}

# takes dequoted msgid, msgstr, and boolean true iff element is always a link
# result is that a line of JS is written STDOUT
sub process_generic_translation {
	(my $englishid, my $id, my $str, my $link_p, my $regex) = @_;

	$id = escape_regex($id);
	my $orig = $id;
	if ($englishid =~ /likes? this\.$/) {
		$id =~ s/^([^%]+)/<span[^>]+>$1<\/span>/;
		$id =~ s/(%a[1-9]?)([^%]+)/$1<span[^>]+>$2<\/span>/g;
		$id =~ s/%a[1-9]?/(<a [^>]+>(?:<span[^>]+>)?[^<]+(?:<\/span>)?<\/a>)/g;
	}
	else {
		$id =~ s/%T/(<a [^>]+><abbr [^>]+>[^<]+<\/abbr><\/a>)/g;
		$id =~ s/%a[1-9]?/(<a [^>]+>[^<]+<\/a>)/g;
		$id =~ s/%d/($regex)/g;
		$id =~ s/%s/([^<"]+)/g; # permit spaces for first names
	}
	$str =~ s/"/\\"/g;
	if ($id ne $str) {
		$str = insert_all_backrefs($orig, $str);
		if ($link_p) {
			$id = '(^|>)'.$id.'(?=($|<))';
		}
		else {
			$id = '(^|="|>)'.$id.'(?=($|"|<))';
		}
		my $toprint = "  d = r(d, '$id', \"\$1\"+$str);\n";
		if ($englishid =~ /^(life|link|photo|post|status)/) {
			push @lowpriority, $toprint;
		}
		else {
			print $toprint;
		}
	}
}

my $aref = Locale::PO->load_file_asarray("po/$targetlang.po");
shift @$aref;  # remove PO header
foreach my $msg (@$aref) {
	next if $msg->fuzzy();
	my $englishid = $msg->dequote($msg->msgid());
	my $id = get_source_string($englishid);
	next unless defined($id); # if we don't know translation in ambient lang
	my $plural_id = $msg->msgid_plural();
	my $str = $msg->msgstr();
	my $ctxt = $msg->msgctxt();
	my $note = $msg->automatic();
	my $link_p = (defined($note) and $note =~ /Always a link\./);
	if (defined($note) and $note =~ /Format\./) {
		$str = $msg->dequote($str);
		$formats{$id} = $str if ($str ne '');
	}
	elsif (defined($ctxt)) {
		$ctxt = $msg->dequote($ctxt);
		$str = $msg->dequote($str);
		next if ($str eq '');
		push @{$contexts{$ctxt}}, "$id|$str";
	}
	elsif (defined($note) and $note =~ /(Day of the Week|Month Name)/) {
		$str = $msg->dequote($str);
		next if ($str eq '');
		# note we're assuming these come after all format strings...
		for my $fmt (keys %formats) {
			if (($fmt =~ /%A/ and $note =~ /Day of the Week/) or
			    ($fmt =~ /%B/ and $note =~ /Month Name/)) {
				my $regex = $fmt;  # e.g. "%B %d" - might have parens if non-English ambient (e.g. es)
				$regex =~ s/%[AB]/$id/; # February %d
				$regex = escape_regex($regex); # might be needed eventually for new alternate source languages
				my $orig = $regex;
				$regex =~ s/%d/([0-9]{1,2})/;  # Now "February ([0-9]{1,2})
				$regex =~ s/%Y/([0-9]{4})/;
				$regex =~ s/%s/([0-9:.apm]+)/;
				$regex = '(^|="|>)'.$regex.'(?=($|"|<))';
				my $repl = $formats{$fmt};        # e.g. "%d %B"
				$repl =~ s/%[AB]/$str/;       # Now "%d Feabhra"
				if ($targetlang =~ m/^(an|ast)$/) {  # HACK!
					$repl =~ s/de ([aeiou])/d'$1/;
				}
				$repl = insert_all_backrefs($orig, $repl);
				print "  d = r(d, '$regex', \"\$1\"+$repl);\n";
			}
		}
	}
	elsif (defined($plural_id)) {
		$plural_id = $msg->dequote($plural_id);
		$plural_id = get_source_string($plural_id);
		next unless defined($plural_id);
		my $plural_hashref = $msg->msgstr_n();
		foreach my $k (sort { $a <=> $b } keys %{$plural_hashref}) {
			my $trans = $msg->dequote($plural_hashref->{$k});
			if ($trans ne '') {
				my $numeral_regex = $plural_regex{$k};
				my $singular = '1';
				# matches singular, but isn't the catch-all
				if ($singular =~ m/^$numeral_regex$/ and $numeral_regex ne '[0-9,]+') {
					# no %d's in (singular) msgid so no regex needed
					# But for br, gd, msgstr[0] might have %d, so subst. "1"
					my $sing_trans = $trans;
					$sing_trans =~ s/%d/1/;
					process_generic_translation($englishid, $id, $sing_trans, $link_p, '');
				}
				# as long as regex isn't '1', it matches some plurals
				process_generic_translation($englishid, $plural_id, $trans, $link_p, $numeral_regex) if ($numeral_regex ne $singular);
			}
		}
	}
	else {
		$str = $msg->dequote($str);
		for my $ctxt_regex (keys %contexts) {
			if ($englishid =~ m/$ctxt_regex/) {
				my $num_links = 0;
				$num_links++ while ($englishid =~ m/%a[1-9]/g);
				# backref for the variable replaced by "link", "post", ...
				# normally $num_links+1 (ambient en) but not for es, fr, etc.
				my $backrefindex = 1;
				while ($id =~ m/%a([1-9])/g) {
					$backrefindex++;
					last if ($1 == $num_links);
				}
				for my $pair (@{$contexts{$ctxt_regex}}) {
					(my $src, my $trg) = $pair =~ m/^([^|]+)\|(.+)$/;
					my $tempid = escape_regex($id);
					my $orig = $tempid;
					# it's (currently) always the %a with the biggest index
					# but not nec. the rightmost one if non-English ambient lang
					# e.g. "%a1 compartió e?la? %a3 de %a2."
					$tempid =~ s/%a$num_links/(<a [^>]+>)$src<\/a>/;
					$tempid =~ s/%a[1-9]?/(<a [^>]+>[^<]+<\/a>)/g;
					my $tempstr = $str;
					$tempstr =~ s/"/\\"/g;
					$tempstr = insert_all_backrefs($orig, $tempstr);
					$tempstr =~ s/("\$$backrefindex")/$1+"$trg<\/a>"/;
					$tempid = '(^|="|>)'.$tempid.'(?=($|"|<))';
					print "  d = r(d, '$tempid', \"\$1\"+$tempstr);\n";
				}
			}
		}
		process_generic_translation($englishid, $id, $str, $link_p, '[0-9,]+') unless ($str eq '');
	}
}

print for (@lowpriority);

exit 0;
