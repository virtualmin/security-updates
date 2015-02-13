#!/usr/local/bin/perl
# Update selected packages

require './security-updates-lib.pl';
&ReadParse();
$redir = "index.cgi?mode=".&urlize($in{'mode'})."&all=".&urlize($in{'all'});

if ($in{'refresh'}) {
	&ui_print_unbuffered_header(undef, $text{'refresh_title'}, "");

	# Clear all caches
	print $text{'refresh_clearing'},"<br>\n";
	&flush_package_caches();
	&clear_repository_cache();
	print $text{'refresh_done'},"<p>\n";

	# Force re-fetch
	print $text{'refresh_available'},"<br>\n";
	@avail = &list_possible_updates(0, 0);
	@allavail = &list_possible_updates(0, 1);
	if (@allavail) {
		print &text('refresh_done5', scalar(@avail),
					     scalar(@allavail)),"<p>\n";
		}
	else {
		print &text('refresh_done4', scalar(@avail)),"<p>\n";
		}

	&webmin_log("refresh");
	&ui_print_footer($redir, $text{'index_return'});
	}
else {
	# Upgrade some packages
	my @pkgs = split(/\0/, $in{'u'});
	@pkgs || &error($text{'update_enone'});
	&ui_print_unbuffered_header(undef, $text{'update_title'}, "");

	# Check if a reboot was required before
	$reboot_before = &check_reboot_required(0);

	foreach my $ps (@pkgs) {
		($p, $s) = split(/\//, $ps);
		next if ($donedep{$p});
		print &text('update_pkg', "<tt>$p</tt>"),"<br>\n";
		print "<ul>\n";
		@pgot = &package_install($p, $s, $in{'all'});
		foreach $g (@pgot) {
			$donedep{$g}++;
			}
		push(@got, @pgot);
		print "</ul><br>\n";
		}
	if (@got) {
		print &text('update_ok', scalar(@got)),"<p>\n";
		}
	else {
		print $text{'update_failed'},"<p>\n";
		}

	# Refresh collected package info
	if (&foreign_check("system-status")) {
		&foreign_require("system-status");
		&system_status::refresh_possible_packages(\@got);
		}

	# Refresh collected package info
	if (&foreign_check("virtual-server") && @got) {
		&foreign_require("virtual-server");
		&virtual_server::refresh_possible_packages(\@got);
		}

	# Check if a reboot is required now
	if (!$reboot_before && &check_reboot_required(1) &&
	    &foreign_check("init")) {
		print &ui_form_start("$gconfig{'webprefix'}/init/reboot.cgi");
		print &ui_hidden("confirm", 1);
		print "<b>",$text{'update_rebootdesc'},"</b><p>\n";
		print &ui_form_end([ [ undef, $text{'update_reboot'} ] ]);
		}

	&webmin_log("update", "packages", scalar(@got),
		    { 'got' => \@got });
	&ui_print_footer($redir, $text{'index_return'});
	}
