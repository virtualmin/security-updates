#!/usr/local/bin/perl
# Show details of one package and available updates

require './security-updates-lib.pl';
&ui_print_header(undef, $text{'view_title'}, "");
&ReadParse();

# Get the package
@avail = &list_available(0, $in{'all'});
($a) = grep { $_->{'name'} eq $in{'name'} &&
	      $_->{'system'} eq $in{'system'} } @avail;
@current = $in{'all'} ? &list_all_current(0) : &list_current(0);
($c) = grep { $_->{'name'} eq $in{'name'} &&
              $_->{'system'} eq $in{'system'} } @current;
$p = $a || $c;

print &ui_table_start($text{'view_header'}, undef, 2);

# Package name and type
print &ui_table_row($text{'view_name'}, $p->{'name'});
print &ui_table_row($text{'view_system'}, $text{'system_'.$p->{'system'}} ||
					  uc($p->{'system'}));
print &ui_table_row($text{'view_desc'}, $p->{'desc'});

# Current state
print &ui_table_row($text{'view_state'},
	$a && !$c ? "<font color=#00aa00>$text{'index_caninstall'}</font>" :
	!$a && $c ? "<font color=#ffaa00>".
                     &text('index_noupdate', $c->{'version'})."</font>" :
	&compare_versions($a, $c) > 0 ?
		    "<font color=#00aa00>".
		     &text('index_new', $a->{'version'})."</font>" :
		    &text('index_ok', $c->{'version'}));

# Version(s) available
if ($c) {
	print &ui_table_row($text{'view_cversion'}, $c->{'version'});
	}
if ($a) {
	print &ui_table_row($text{'view_aversion'}, $a->{'version'});
	}

# Source, if available
print &ui_table_row($text{'view_source'},
	$a->{'source'} =~ /^virtualmin/ ? "Virtualmin" : $a->{'source'});

# Change log, if possible
if ($a) {
	$cl = &get_changelog($a);
	if ($cl) {
		print &ui_table_row($text{'view_changelog'},
			"<pre>".&html_escape($cl)."</pre>");
		}
	}

print &ui_table_end();

&ui_print_footer("", $text{'index_return'});

