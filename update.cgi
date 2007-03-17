#!/usr/local/bin/perl
# Update selected packages

require './security-updates-lib.pl';
&ReadParse();
@pkgs = split(/\0/, $in{'u'});
@pkgs || &error($text{'update_enone'});
&ui_print_unbuffered_header(undef, $text{'update_title'}, "");

foreach my $p (@pkgs) {
	print &text('update_pkg', "<tt>$p</tt>"),"<br>\n";
	print "<ul>\n";
	push(@got, &package_install($p));
	print "</ul><br>\n";
	}
if (@got) {
	print &text('update_ok', scalar(@got)),"<p>\n";
	}
else {
	print $text{'update_failed'},"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});

