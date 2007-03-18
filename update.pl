#!/usr/local/bin/perl
# Check for and install updates

$no_acl_check++;
require './security-updates-lib.pl';

# See what needs doing
@updates = &list_updates(1);
@current = &list_current(1);
@avail = &list_available(1);
foreach $c (sort { $a->{'name'} cmp $b->{'name'} } @current) {
	($a) = grep { $_->{'name'} eq $c->{'name'} } @avail;
	($u) = grep { $_->{'name'} eq $c->{'name'} } @updates;
	if ($u && &compare_versions($u, $c) > 0) {
		# A security problem was detected
		if (&compare_versions($a, $u) >= 0) {
			# And an update is available
			push(@todo, { 'name' => $c->{'name'},
				      'version' => $a->{'version'},
				      'desc' => $u->{'desc'},
				      'level' => 1 });
			}
		else {
			# Not available
			push(@todo, { 'name' => $c->{'name'},
				      'version' => $a->{'version'},
				      'desc' => $u->{'desc'},
				      'level' => 0 });
			}
		}
	elsif (&compare_versions($a, $c) > 0) {
		# An update is available
		push(@todo, { 'name' => $c->{'name'},
				 'version' => $a->{'version'},
				 'desc' => "New version released",
				 'level' => 2 });
		}
	}

# Install packages that are needed
foreach $t (@todo) {
	if ($t->{'level'} <= $config{'sched_action'}) {
		# Can install
		$body .= "An update to $t->{'name'} $t->{'version'} is needed : $t->{'desc'}\n";
		($out, $done) = &capture_function_output(
				  \&package_install, $t->{'name'});
		if (@$done) {
			$body .= "This update has been successfully installed.\n\n";
			}
		else {
			$body .= "However, this update could not be installed! Try the update manually\nusing the Security Updates module.\n\n";
			}
		}
	else {
		# Just tell the user about it
		$body .= "An update to $t->{'name'} $t->{'version'} is available : $t->{'desc'}\n\n";
		}
	}

# Email the admin
if ($config{'sched_email'} && $body) {
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	local $from = &mailboxes::get_from_address();
	local $mail = { 'headers' =>
			[ [ 'From', $from ],
			  [ 'To', $config{'sched_email'} ],
			  [ 'Subject', "Security updates" ] ],
			'attach' =>
			[ { 'headers' => [ [ 'Content-type', 'text/plain' ] ],
			    'data' => $body } ] };
	&mailboxes::send_mail($mail, undef, 1, 0);
	}

