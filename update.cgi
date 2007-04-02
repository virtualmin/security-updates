#!/usr/local/bin/perl
# Update selected packages

require './security-updates-lib.pl';
&ReadParse();

if ($in{'refresh'}) {
	# Clear all caches
	unlink($current_cache_file);
	unlink($updates_cache_file);
	unlink($available_cache_file);
	&redirect("");
	}
else {
	# Upgrade some packages
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

	# Refresh collected package info
	if (&foreign_check("virtual-server")) {
		&foreign_require("virtual-server", "virtual-server-lib.pl");
		if (defined(&virtual_server::refresh_possible_packages)) {
			&virtual_server::refresh_possible_packages(\@got);
			}
		}

	&webmin_log("update", "packages", scalar(@got),
		    { 'got' => \@got });
	&ui_print_footer("", $text{'index_return'});
	}
