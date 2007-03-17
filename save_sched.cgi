#!/usr/local/bin/perl
# Save scheduled checking options

require './security-updates-lib.pl';
&ReadParse();

$config{'sched_email'} = $in{'email'};
$config{'sched_action'} = $in{'action'};
&save_module_config();

$oldjob = $job = &find_cron_job();
if ($in{'sched_def'}) {
	&cron::delete_cron_job($job) if ($job);
	$msg = $text{'sched_no'};
	}
else {
	$job ||= { 'user' => 'root',
		   'active' => 1,
		   'command' => $cron_cmd };
	$job->{'mins'} = $job->{'hours'} = $job->{'days'} =
		$job->{'months'} = $job->{'weekdays'} = '*';
	if ($in{'sched'} eq 'h') {
		$job->{'mins'} = '0';
		}
	elsif ($in{'sched'} eq 'd') {
		$job->{'mins'} = '0';
		$job->{'hours'} = '0';
		}
	elsif ($in{'sched'} eq 'w') {
		$job->{'mins'} = '0';
		$job->{'hours'} = '0';
		$job->{'weekdays'} = '0';
		}
	if ($oldjob) {
		&cron::change_cron_job($job);
		}
	else {
		&cron::create_cron_job($job);
		}
	&cron::create_wrapper($cron_cmd, $module_name, "update.pl");
	$msg = $text{'sched_yes'};
	}

# Tell the user
&ui_print_header(undef, $text{'sched_title'}, "");

print "$msg<p>\n";

&ui_print_footer("", $text{'index_return'});

