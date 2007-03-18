#!/usr/local/bin/perl
# Show installed packages, and flag those for which an update is needed

require './security-updates-lib.pl';
&ui_print_header(undef, $module_info{'desc'}, "", undef, 1, 1);
&error_setup($text{'index_err'});

# Make sure we can connect
$err = &test_connection();
if ($err) {
	print &text('index_problem', $err),"<p>\n";
	&ui_print_footer("/", $text{'index'});
	exit;
	}

@updates = &list_security_updates();
@current = &list_current(1);
@avail = &list_available();
print &ui_form_start("update.cgi");
@tds = ( "width=5" );
@links = ( &select_all_link("u"), &select_invert_link("u") );
print &ui_links_row(\@links);
print &ui_columns_start([ "", $text{'index_name'},
			  $text{'index_desc'},
			  $text{'index_status'} ], \@tds);
$sft = &foreign_available("software");
foreach $c (sort { $a->{'name'} cmp $b->{'name'} } @current) {
	# Work out the status
	($a) = grep { $_->{'name'} eq $c->{'name'} } @avail;
	($u) = grep { $_->{'name'} eq $c->{'name'} } @updates;
	if ($u && &compare_versions($u, $c) > 0) {
		# A security problem was detected
		if (&compare_versions($a, $u) >= 0) {
			# And an update is available
			$msg = "<font color=#aa0000>".
			       &text('index_bad', $u->{'version'},
				     $u->{'desc'})."</font>";
			$need = 1;
			}
		else {
			# Not available!
			$msg = "<b><font color=#aa0000>".
			       &text('index_bad2', $u->{'version'},
				     $u->{'desc'})."</font></b>";
			$need = 0;
			}
		}
	elsif (&compare_versions($a, $c) > 0) {
		# An update is available
		$msg = "<b><font color=#00aa00>".
		       &text('index_new', $a->{'version'})."</font></b>";
		$need = 1;
		}
	elsif (!$a->{'version'}) {
		# No update exists
		$msg = "<font color=#ffaa00><b>".
			&text('index_noupdate', $c->{'version'})."</b></font>";
		$need = 0;
		}
	else {
		# We have the latest
		$msg = &text('index_ok', $c->{'version'});
		$need = 0;
		}
	print &ui_checked_columns_row([
		$sft ? "<a href='../software/edit_pack.cgi?package=".
		  &urlize($c->{'name'})."'>$c->{'name'}</a>" : $c->{'name'},
		$c->{'desc'},
		$msg ],
		\@tds, "u", $c->{'name'}, $need);
	}
print &ui_columns_end();
print &ui_links_row(\@links);
print &ui_form_end([ [ "ok", $text{'index_update'} ],
		     undef,
		     [ "refresh", $text{'index_refresh'} ] ]);

# Show scheduled report form
print "<hr>\n";
print &ui_form_start("save_sched.cgi");
print &ui_table_start($text{'index_header'}, undef, 2);

$job = &find_cron_job();
if ($job) {
	$sched = $job->{'hours'} eq '*' ? 'h' :
		 $job->{'days'} eq '*' && $job->{'weekdays'} eq '*' ? 'd' :
		 $job->{'days'} eq '*' && $job->{'weekdays'} eq '0' ? 'w' :
								      undef;
	}
else {
	$sched = "d";
	}
print &ui_table_row($text{'index_sched'},
		    &ui_radio("sched_def", $job ? 0 : 1,
			      [ [ 1, $text{'index_sched1'} ],
			        [ 0, $text{'index_sched0'} ] ])."\n".
		    &ui_select("sched", $sched,
			       [ [ 'h', $text{'index_schedh'} ],
			         [ 'd', $text{'index_schedd'} ],
			         [ 'w', $text{'index_schedw'} ] ]));

print &ui_table_row($text{'index_email'},
		    &ui_textbox("email", $config{'sched_email'}, 40));

print &ui_table_row($text{'index_action'},
		    &ui_radio("action", int($config{'sched_action'}),
			       [ [ 0, $text{'index_action0'} ],
			         [ 1, $text{'index_action1'} ],
			         [ 2, $text{'index_action2'} ] ]));

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("/", $text{'index'});

