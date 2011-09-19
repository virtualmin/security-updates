# Functions for checking for updates to core Virtualmin packages

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require("software", "software-lib.pl");
&foreign_require("cron", "cron-lib.pl");
&foreign_require("webmin", "webmin-lib.pl");
use Data::Dumper;

@update_packages = ( "apache", "postfix", "sendmail", "bind", "procmail",
		     "spamassassin", "logrotate", "webalizer", "mysql",
		     "postgresql", "proftpd", "clamav", "php4", "mailman",
		     "subversion", "python", "ruby", "irb", "rdoc", "rubygems",
		     "openssl", "perl", "php5", "webmin", "usermin",
		     "fcgid", "awstats", "dovecot", "postgrey",
		     "virtualmin-modules", "kvm", "xen",
		   ); 

$available_cache_file = "$module_config_directory/available.cache";
$current_cache_file = "$module_config_directory/current.cache";
$current_all_cache_file = "$module_config_directory/current-all.cache";
$updates_cache_file = "$module_config_directory/updates.cache";
$cron_cmd = "$module_config_directory/update.pl";

$virtualmin_host = $config{'host'} || "software.virtualmin.com";
$virtualmin_port = 80;
$server_manager_host = "vm2.virtualmin.com";
$virtualmin_licence = "/etc/virtualmin-license";
$server_manager_licence = "/etc/server-manager-license";
$webmin_version_path = "$config{'suffix'}/wbm/webmin-version";
$free_webmin_version_path = "$config{'suffix'}/gpl/wbm/webmin-version";
$usermin_version_path = "$config{'suffix'}/wbm/usermin-version";
$free_usermin_version_path = "$config{'suffix'}/gpl/wbm/usermin-version";
$webmin_download_path = "$config{'suffix'}/wbm/webmin-current.tar.gz";
$usermin_download_path = "$config{'suffix'}/wbm/usermin-current.tar.gz";
$free_webmin_download_path = "$config{'suffix'}/gpl/wbm/webmin-current.tar.gz";
$free_usermin_download_path = "$config{'suffix'}/gpl/wbm/usermin-current.tar.gz";

$yum_cache_file = "$module_config_directory/yumcache";
$apt_cache_file = "$module_config_directory/aptcache";
$yum_changelog_cache_dir = "$module_config_directory/yumchangelog";

# test_connection()
# Returns undef if we can connect OK, or an error message
sub test_connection
{
return undef if (&free_virtualmin_licence() ||	# GPL version
		 &free_cloudmin_licence());
my ($user, $pass, $host) = &get_user_pass();
return $text{'index_euser'} if (!$user);
return undef;
}

# get_software_packages()
# Fills in software::packages with list of installed packages (if missing),
# returns count.
sub get_software_packages
{
if (!$get_software_packages_cache) {
	%software::packages = ( );
	$get_software_packages_cache = &software::list_packages();
	}
return $get_software_packages_cache;
}

# list_current(nocache)
# Returns a list of packages and versions for the core packages managed
# by this module. Return keys are :
#  name - The my package name (ie. CSWapache2)
#  update - Name used to refer to it by the updates system (ie. apache2)
#  version - Version number
#  epoch - Epoch part of the version
#  desc - Human-readable description
#  package - Original generic program, like apache
sub list_current
{
my ($nocache) = @_;
if ($nocache || &cache_expired($current_cache_file)) {
	my $n = &get_software_packages();
	my @rv;
	foreach my $p (@update_packages) {
		my @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			my $updatepn = $pn;
			$pn = &csw_to_pkgadd($pn);
			for(my $i=0; $i<$n; $i++) {
				next if ($software::packages{$i,'name'}
					 !~ /^$pn$/);
				push(@rv, {
				  'update' =>
				    $updatepn eq $pn ? 
					$software::packages{$i,'name'} :
					$updatepn,
				  'name' =>
				    $software::packages{$i,'name'},
				  'version' =>
				    $software::packages{$i,'version'},
				  'epoch' =>
				    $software::packages{$i,'epoch'},
				  'desc' =>
				    $software::packages{$i,'desc'},
				  'package' => $p,
				  'system' => $software::update_system,
				  'software' => 1,
				  });
				&fix_pkgadd_version($rv[$#rv]);
				}
			}
		}

	# Filter out dupes and sort by name
	@rv = &filter_duplicates(\@rv);

	my $incwebmin = &include_webmin_modules();
	if ($incwebmin) {
		# Add installed Webmin modules
		foreach my $minfo (&get_all_module_infos()) {
			push(@rv, { 'name' => $minfo->{'dir'},
				    'update' => $minfo->{'dir'},
				    'desc' => &text('index_webmin',
						    $minfo->{'desc'}),
				    'version' => $minfo->{'version'},
				    'system' => 'webmin',
				    'updateonly' => 1,
				  });
			}

		# Add installed Webmin themes
		foreach my $tinfo (&webmin::list_themes()) {
			push(@rv, { 'name' => $tinfo->{'dir'},
				    'update' => $tinfo->{'dir'},
				    'desc' => &text('index_webmintheme',
						    $tinfo->{'desc'}),
				    'version' => $tinfo->{'version'},
				    'system' => 'webmin',
				    'updateonly' => 1,
				  });
			}

		# Add an entry for Webmin itself, but only if this was
		# a tar.gz install
		if ($incwebmin != 2) {
			push(@rv, { 'name' => 'webmin',
				    'update' => 'webmin',
				    'desc' => 'Webmin Package',
				    'version' => &get_webmin_version(),
				    'system' => 'tgz',
				    'updateonly' => 1,
				  });
			}
		else {
			# Remove Webmin from the list, as YUM sometimes
			# includes it in the 'yum list' output even though
			# it cannot actual do an update!
			@rv = grep { $_->{'name'} ne 'webmin' } @rv;
			}

		# If Usermin is installed from a tgz, add it too
		if (&include_usermin_modules() == 1) {
			push(@rv, { 'name' => 'usermin',
				    'update' => 'usermin',
				    'desc' => 'Usermin Package',
				    'version' =>
					&usermin::get_usermin_version(),
				    'system' => 'tgz',
				    'updateonly' => 1,
				  });
			}
		else {
			@rv = grep { $_->{'name'} ne 'usermin' } @rv;
			}
		}

	&write_cache_file($current_cache_file, \@rv);
	return @rv;
	}
else {
	return &read_cache_file($current_cache_file);
	}
}

# list_all_current(nocache)
# Returns a list of all installed packages, in the same format as list_current
sub list_all_current
{
my ($nocache) = @_;
my ($nocache) = @_;
if ($nocache || &cache_expired($current_all_cache_file)) {
	my $n = &get_software_packages();
	my @rv;
	my %pkgmap;
	foreach my $p (@update_packages) {
		my @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			$pkgmap{$pn} = $p;
			}
		}
	for(my $i=0; $i<$n; $i++) {
		push(@rv, { 'name' => $software::packages{$i,'name'},
			    'update' => $software::packages{$i,'name'},
			    'version' =>
			      $software::packages{$i,'version'},
			    'epoch' =>
			      $software::packages{$i,'epoch'},
			    'desc' =>
			      $software::packages{$i,'desc'},
			    'package' => $pkgmap{$software::packages{$i,'name'}},
			    'system' => $software::update_system,
			});
		&fix_pkgadd_version($rv[$#rv]);
		}

	# Filter out dupes and sort by name
	@rv = &filter_duplicates(\@rv);

	&write_cache_file($current_all_cache_file, \@rv);
	return @rv;
	}
else {
	return &read_cache_file($current_all_cache_file);
	}
}

# list_available(nocache, all)
# Returns the names and versions of packages available from the update
# system, that we are interested in.
sub list_available
{
my ($nocache, $all) = @_;
my $expired = &cache_expired($available_cache_file.int($all));
if ($nocache || $expired == 2 ||
    $expired == 1 && !&check_available_lock()) {
	# Get from update system
	my @rv;
	my @avail = &packages_available();
	if (!$all) {
		# Limit to packages Virtualmin cares about
		@avail = &filter_virtualmin(\@avail);
		}
	foreach my $avail (@avail) {
		$avail->{'update'} = $avail->{'name'};
		$avail->{'name'} = &csw_to_pkgadd($avail->{'name'});
		if (!$all && &installation_candiate($avail)) {
			$avail->{'desc'} ||= &generate_description($avail);
			}
		push(@rv, $avail);
		}
	&set_pinned_versions(\@rv);

	# Filter out dupes and sort by name
	@rv = &filter_duplicates(\@rv);

	if (!$all && &include_webmin_modules()) {
		# Get from Webmin updates services. We exclude Webmin and
		# Usermin for now, as they cannot be updated via YUM.
		@rv = grep { $_->{'name'} ne 'webmin' &&
			     $_->{'name'} ne 'usermin' } @rv;
		push(@rv, &webmin_modules_available());
		}

	if (!@rv) {
		# Failed .. fall back to cache
		@rv = &read_cache_file($available_cache_file.int($all));
		}
	&write_cache_file($available_cache_file.int($all), \@rv);
	return @rv;
	}
else {
	return &read_cache_file($available_cache_file.int($all));
	}
}

# filter_virtualmin(&packages)
# Given a list of updates to include only those Virtualmin-related
sub filter_virtualmin
{
my ($avail) = @_;
my @rv;
foreach my $p (@update_packages) {
	my @pkgs = split(/\s+/, &package_resolve($p));
	foreach my $pn (@pkgs) {
		my @mavail = grep { $_->{'name'} =~ /^$pn$/ } @$avail;
		foreach my $avail (@mavail) {
			$avail->{'package'} = $p;
			push(@rv, $avail);
			}
		}
	}
return @rv;
}

# check_available_lock()
# Returns 1 if the package update system is currently locked
sub check_available_lock
{
if ($software::update_system eq "yum") {
	return &check_pid_file("/var/run/yum.pid");
	}
return 0;
}

# filter_duplicates(&packages)
# Given a list of package structures, orders them by name and version number,
# and removes dupes with the same name
sub filter_duplicates
{
my ($pkgs) = @_;
my @rv = sort { $a->{'name'} cmp $b->{'name'} ||
	         &compare_versions($b, $a) } @$pkgs;
my %done;
return grep { !$done{$_->{'name'},$_->{'system'}}++ } @rv;
}

# cache_expired(file)
# Checks if some cache has expired. Returns 0 if OK, 1 if expired, 2 if
# totally missing.
sub cache_expired
{
my ($file) = @_;
my @st = stat($file);
return 2 if (!@st);
if (!$config{'cache_time'} || time()-$st[9] > $config{'cache_time'}*60*60) {
	return 1;
	}
return 0;
}

sub write_cache_file
{
my ($file, $arr) = @_;
&open_tempfile(FILE, ">$file");
&print_tempfile(FILE, Dumper($arr));
&close_tempfile(FILE);
$read_cache_file_cache{$file} = $arr;
}

# read_cache_file(file)
# Returns the contents of some cache file, as an array ref
sub read_cache_file
{
my ($file) = @_;
if (defined($read_cache_file_cache{$file})) {
        return @{$read_cache_file_cache{$file}};
        }
if (-r $file) {
        do $file;
        $read_cache_file_cache{$file} = $VAR1;
        return @$VAR1;
        }
return ( );
}

# compare_versions(&pkg1, &pk2)
# Returns -1 if the version of pkg1 is older than pkg2, 1 if newer, 0 if same.
sub compare_versions
{
my ($pkg1, $pkg2) = @_;
if ($pkg1->{'system'} eq 'webmin' && $pkg2->{'system'} eq 'webmin') {
	# Webmin module version compares are always numeric
	return $pkg1->{'version'} <=> $pkg2->{'version'};
	}
my $ec = $pkg1->{'epoch'} <=> $pkg2->{'epoch'};
if ($ec && ($pkg1->{'epoch'} eq '' || $pkg2->{'epoch'} eq '') &&
    $pkg1->{'system'} eq 'apt') {
	# On some Debian systems, we don't have a my epoch
	$ec = undef;
	}
return $ec ||
       &software::compare_versions($pkg1->{'version'}, $pkg2->{'version'});
}

sub find_cron_job
{
my @jobs = &cron::list_cron_jobs();
my ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $cron_cmd } @jobs;
return $job;
}

# package_resolve(name)
# Given a package code name from @update_packages, returns a string of the
# underlying packages that implement it. This may come from the update system
# if the OS has one (YUM or APT, or from Virtualmin's built-in list)
sub package_resolve
{
my ($name) = @_;
my $realos = $gconfig{'real_os_type'};
$realos =~ s/ /-/g;
my $realver = $gconfig{'real_os_version'};
$realver =~ s/ /-/g;
if (open(RESOLV, "$module_root_directory/resolve.$realos-$realver") ||
    open(RESOLV, "$module_root_directory/resolve.$realos") ||
    open(RESOLV, "$module_root_directory/resolve.$gconfig{'os_type'}-$gconfig{'os_version'}") ||
    open(RESOLV, "$module_root_directory/resolve.$gconfig{'os_type'}")) {
	my $rv;
	while(<RESOLV>) {
		if (/^(\S+)\s+(.*)/ && $1 eq $name) {
			$rv = $2;
			}
		elsif (/^\*/) {
			# All other packages have the same name as their code
			$rv = $name;
			}
		}
	close(RESOLV);
	return $rv if ($rv);
	}
if (defined(&software::update_system_resolve)) {
	return &software::update_system_resolve($name);
	}
return $name;
}

# packages_available()
# Returns a list of all available packages, as hash references with name and
# version keys. These come from the APT, YUM or CSW update system, if available.
# If not, nothing is returned.
sub packages_available
{
if (@packages_available_cache) {
	return @packages_available_cache;
	}
if (defined(&software::update_system_available)) {
	# From a decent package system
	my @rv = software::update_system_available();
	my %done;
	foreach my $p (@rv) {
		$p->{'system'} = $software::update_system;
		$p->{'version'} =~ s/,REV=.*//i;		# For CSW
		if ($p->{'system'} eq 'apt' && !$p->{'source'}) {
			$p->{'source'} =
			    $p->{'file'} =~ /virtualmin/i ? 'virtualmin' : 
			    $p->{'file'} =~ /debian/i ? 'debian' :
			    $p->{'file'} =~ /ubuntu/i ? 'ubuntu' : undef;
			}
		$done{$p->{'name'}} = $p;
		}
	if ($software::update_system eq "yum" &&
	    &has_command("up2date")) {
		# YUM is the package system select, but up2date is installed
		# too (ie. RHEL). Fetch its packages too..
		if (!$done_rhn_lib++) {
			do "../software/rhn-lib.pl";
			}
		my @rhnrv = &update_system_available();
		foreach my $p (@rhnrv) {
			$p->{'system'} = "rhn";
			my $d = $done{$p->{'name'}};
			if ($d) {
				# Seen already .. but is this better?
				if (&compare_versions($p, $d) > 0) {
					# Yes .. replace
					@rv = grep { $_ ne $d } @rv;
					push(@rv, $p);
					$done{$p->{'name'}} = $p;
					}
				}
			else {
				push(@rv, $p);
				$done{$p->{'name'}} = $p;
				}
			}
		}
	@packages_available_cache = @rv;
	return @rv;
	}
return ( );
}

# supports_updates_available()
# Returns true if the package update system has a function to find just
# updates, and we aren't including Webmin modules
sub supports_updates_available
{
return defined(&software::update_system_updates) &&
       !&include_webmin_modules();
}

# updates_available(no-cache, all)
# Returns an array of hash refs of package updates available, according to
# the update system, with caching.
sub updates_available
{
my ($nocache, $all) = @_;
if (!scalar(@updates_available_cache)) {
	if ($nocache || &cache_expired($updates_cache_file)) {
		# Get from original source
		@updates_available_cache = &software::update_system_updates();
		foreach my $a (@updates_available_cache) {
			$a->{'update'} = $a->{'name'};
			$a->{'system'} = $software::update_system;
			}
		&write_cache_file($updates_cache_file,
				  \@updates_available_cache);
		}
	else {
		# Use on-disk cache
		@updates_available_cache =
			&read_cache_file($updates_cache_file);
		}
	}
if ($all) {
	return @updates_available_cache;
	}
else {
	return &filter_virtualmin(\@updates_available_cache);
	}
}

# package_install(package, [system], [check-all])
# Install some package, either from an update system or from Virtualmin. Returns
# a list of updated package names.
sub package_install
{
my ($name, $system, $all) = @_;
my @rv;
my $pkg;

# First get from list of updates
($pkg) = grep { $_->{'update'} eq $name &&
		($_->{'system'} eq $system || !$system) }
	      sort { &compare_versions($b, $a) }
		   &list_possible_updates(0, $all);
if (!$pkg) {
	# Then try list of all available packages
	($pkg) = grep { $_->{'update'} eq $name &&
			($_->{'system'} eq $system || !$system) }
		      sort { &compare_versions($b, $a) }
			   &list_available(0, $all);
	}

if (!$pkg) {
	print &text('update_efindpkg', $name),"<p>\n";
	return ( );
	}
if ($pkg->{'system'} eq 'webmin') {
	# Webmin module, which we can download and install 
	my ($host, $port, $page, $ssh) =
		&parse_http_url($pkg->{'updatesurl'});
	my ($mhost, $mport, $mpage, $mssl) =
		&parse_http_url($pkg->{'url'}, $host, $port, $page, $ssl);
	my $mfile;
	($mfile = $mpage) =~ s/^(.*)\///;
	my $mtemp = &transname($mfile);
	my $error;
	print &text('update_wdownload', $pkg->{'name'}),"<br>\n";
	&http_download($mhost, $mport, $mpage, $mtemp, \$error, undef, $mssl,
		       $webmin::config{'upuser'}, $webmin::config{'uppass'});
	if ($error) {
		print &text('update_ewdownload', $error),"<p>\n";
		return ( );
		}
	print $text{'update_wdownloaded'},"<p>\n";

	# Install the module
	print &text('update_winstall', $pkg->{'name'}),"<br>\n";
	my $irv = &webmin::install_webmin_module($mtemp, 1, 0);
	if (!ref($irv)) {
		print &text('update_ewinstall', $irv),"<p>\n";
		}
	else {
		print $text{'update_winstalled'},"<p>\n";
		@rv = map { /([^\/]+)$/; $1 } @{$irv->[1]};
		}
	}
elsif ($pkg->{'system'} eq 'tgz') {
	# Tar file of Webmin or Usermin, which we have to download and
	# install into the destination directory
	my $temp = &transname($pkg->{'name'}."-".$pkg->{'version'}.
				 ".tar.gz");
	my $error;
	print &text('update_tgzdownload', ucfirst($pkg->{'name'})),"<br>\n";
	my ($user, $pass) = &get_user_pass();
	my $free = free_virtualmin_licence() ||
		   free_cloudmin_licence();
	my $path = $pkg->{'name'} eq 'webmin' && $free ?
			$free_webmin_download_path :
		      $pkg->{'name'} eq 'webmin' && !$free ?
			$webmin_download_path :
		      $pkg->{'name'} eq 'usermin' && $free ?
			$free_usermin_download_path :
			$usermin_download_path;
	&http_download($virtualmin_host, $virtualmin_port, $path,
		       $temp, \$error, undef, 0, $user, $pass);
	if ($error || !-r $temp) {
		print &text('update_ewdownload',
			    $error || "Nothing downloaded"),"<p>\n";
		return ( );
		}
	else {
		my @st = stat($temp);
		print &text('update_tgzdownloaded', &nice_size($st[7])),"<p>\n";
		}

	# Get the current install directory
	print $text{'update_tgzuntar'},"<br>\n";
	my $curdir;
	if ($pkg->{'name'} eq 'webmin') {
		$curdir = $root_directory;
		$pkg_config_dir = $config_directory;
		}
	else {
		my %miniserv;
		&foreign_require("usermin", "usermin-lib.pl");
		&usermin::get_usermin_miniserv_config(\%miniserv);
		$curdir = $miniserv{'root'};
		$pkg_config_dir = $usermin::config{'usermin_dir'};
		}
	if (!$curdir || $curdir eq "/") {
		print $text{'update_ecurdir'},"<p>\n";
		return ( );
		}
	if (!-r "$pkg_config_dir/config") {
		print $text{'update_econfigdir'},"<p>\n";
		return ( );
		}
	my $targetdir = &read_file_contents("$pkg_config_dir/install-dir");
	$targetdir =~ s/\r|\n//g;

	# Un-tar the archive next to it
	my $pardir = $curdir;
	$pardir =~ s/\/([^\/]+)$//;
	my $out = &backquote_command("cd ".quotemeta($pardir)." && ".
					"gunzip -c $temp | tar xf -");
	if ($?) {
		my @lines = split(/\n/, $out);
		while(@lines > 10) { shift(@lines); }  # Last 10 only
		print "<pre>",&html_escape(join("\n", @lines)),"</pre>\n";
		print $text{'update_etgzuntar'},"<p>\n";
		return ( );
		}
	my $xtractdir = $pardir."/".$pkg->{'name'}."-".$pkg->{'version'};
	print $text{'update_tgzuntardone'},"<p>\n";

	# Save this CGI from being killed by the upgrade
	$SIG{'TERM'} = 'IGNORE';

	# Run setup.sh to upgrade
	print $text{'update_tgzsetup'},"<br>\n";
	print "<pre>";
	&clean_environment();
	&open_execute_command(SETUP, "cd $xtractdir && config_dir=$pkg_config_dir autothird=1 ./setup.sh $targetdir 2>&1 </dev/null", 1);
	while(<SETUP>) {
		print &html_escape($_);
		}
	close(SETUP);
	print "</pre>\n";
	&reset_environment();
	if ($out =~ /ERROR/) {
		print $text{'update_etgzsetup'},"<p>\n";
		}
	else {
		print $text{'update_tgzsetupdone'},"<p>\n";
		}

	if ($targetdir) {
		# Delete the extract directory, if we copied to elsewhere
		&execute_command("rm -rf ".quotemeta($xtractdir));
		}
	elsif ($out !~ /ERROR/) {
		# Delete the old directory
		&execute_command("rm -rf ".quotemeta($curdir));
		}
	&unlink_file($temp);

	@rv = ( $pkg->{'name'} );
	}
elsif (defined(&software::update_system_install)) {
	# Using some update system, like YUM or APT
	&clean_environment();
	if ($software::update_system eq $pkg->{'system'}) {
		# Can use the default system
		if ($name eq "apache2" &&
		    $pkg->{'system'} eq 'apt') {
			# If updating the apache2 package on an apt system
			# and apache2-mpm-prefork is installed, also update it
			# so that ubuntu doesn't pull in the apache2-mpm-worker
			# instead, which breaks PHP :-(
			local @pinfo = &software::package_info(
					"apache2-mpm-prefork");
			if (@pinfo) {
				$name .= " apache2-mpm-prefork";
				}
			}
		@rv = &software::update_system_install($name, undef, 1);
		}
	else {
		# Another update system exists!! Use it..
		if (!$done_rhn_lib++) {
			do "../software/$pkg->{'system'}-lib.pl";
			}
		if (!$done_rhn_text++) {
			%text = ( %text, %software::text );
			}
		@rv = &update_system_install($name, undef, 1);
		}
	&reset_environment();
	}
else {
	&error("Don't know how to install package $pkg->{'name'} with type $pkg->{'type'}");
	}
# Flush installed cache
unlink($current_cache_file);
unlink($current_all_cache_file);
return @rv;
}

# package_install_multiple(&package-names, system)
# Install multiple packages, either from an update system or from Webmin.
# Returns a list of updated package names.
sub package_install_multiple
{
my ($names, $system) = @_;
my @rv;
my $pkg;

if ($system eq "webmin" || $system eq "tgz") {
	# Install one by one
	foreach my $name (@$names) {
		push(@rv, &package_install($name, $system));
		}
	}
elsif (defined(&software::update_system_install)) {
	# Using some update system, like YUM or APT
	&clean_environment();
	if ($software::update_system eq $system) {
		# Can use the default system
		@rv = &software::update_system_install(
			join(" ", @$names), undef, 1);
		}
	else {
		# Another update system exists!! Use it..
		if (!$done_rhn_lib++) {
			do "../software/$pkg->{'system'}-lib.pl";
			}
		if (!$done_rhn_text++) {
			%text = ( %text, %software::text );
			}
		@rv = &update_system_install(join(" ", @$names), undef, 1);
		}
	&reset_environment();
	}
else {
	&error("Don't know how to install packages");
	}
# Flush installed cache
unlink($current_cache_file);
return @rv;
}

# get_user_pass()
# Returns the username and password to use for HTTP requests, and the base site
sub get_user_pass
{
my %licence;
if (-r $virtualmin_licence) {
	&read_env_file($virtualmin_licence, \%licence);
	return ($licence{'SerialNumber'}, $licence{'LicenseKey'},
		$virtualmin_host);
	}
elsif (-r $server_manager_licence) {
	&read_env_file($server_manager_licence, \%licence);
	return ($licence{'SerialNumber'}, $licence{'LicenseKey'},
		$server_manager_host);
	}
else {
	return ( );
	}
}

# free_virtualmin_licence()
# Returns 1 if this is a GPL/free install of Virtualmin
sub free_virtualmin_licence
{
my %minfo = &get_module_info('virtual-server');
if (%minfo && $minfo{'virtualmin'} eq 'gpl') {
	return 1;
	}
if (-r $virtualmin_licence) {
	local %licence;
	&read_env_file($virtualmin_licence, \%licence);
	return $licence{'SerialNumber'} eq 'GPL' ? 1 : 0;
	}
return 0;
}

# free_cloudmin_licence()
# Returns 1 if this is a GPL/free install of Cloudmin
sub free_cloudmin_licence
{
my %minfo = &get_module_info('server-manager');
if (%minfo && $minfo{'gpl'}) {
	return 1;
	}
if (-r $server_manager_licence) {
	local %licence;
	&read_env_file($server_manager_licence, \%licence);
	return $licence{'SerialNumber'} eq 'GPL' ? 1 : 0;
	}
return 0;
}

# list_possible_updates([nocache], [all])
# Returns a list of updates that are available. Each element in the array
# is a hash ref containing a name, version, description and severity flag.
# Intended for calling from themes. Nocache 0=cache everything, 1=flush all
# caches, 2=flush only current
sub list_possible_updates
{
my ($nocache, $all) = @_;
my @rv;
my @current = $all ? &list_all_current($nocache)
                   : &list_current($nocache);
if (&supports_updates_available()) {
	# Software module supplies a function that can list just packages
	# that need updating
	my %currentmap;
	foreach my $c (@current) {
		$currentmap{$c->{'name'},$c->{'system'}} ||= $c;
		}
	foreach my $a (&updates_available($nocache == 1, $all)) {
		my $c = $currentmap{$a->{'name'},$a->{'system'}};
		next if (!$c);
		next if ($a->{'version'} eq $c->{'version'});
		push(@rv, { 'name' => $a->{'name'},
			    'update' => $a->{'update'},
			    'system' => $a->{'system'},
			    'version' => $a->{'version'},
			    'oldversion' => $c->{'version'},
			    'epoch' => $a->{'epoch'},
			    'oldepoch' => $c->{'epoch'},
			    'security' => $a->{'security'},
			    'source' => $a->{'source'},
			    'desc' => $c->{'desc'} || $a->{'desc'},
			    'url' => $a->{'url'},
			    'updatesurl' => $a->{'updatesurl'},
			    'severity' => 0 });
		}
	}
else {
	# Compute from current and available list
	my @avail = &list_available($nocache == 1, $all);
	my %availmap;
	foreach my $a (@avail) {
		my $oa = $availmap{$a->{'name'},$a->{'system'}};
		if (!$oa || &compare_versions($a, $oa) > 0) {
			$availmap{$a->{'name'},$a->{'system'}} = $a;
			}
		}
	foreach my $c (sort { $a->{'name'} cmp $b->{'name'} } @current) {
		# Work out the status
		my $a = $availmap{$c->{'name'},$c->{'system'}};
		if ($a->{'version'} && &compare_versions($a, $c) > 0) {
			# A regular update is available
			push(@rv, { 'name' => $a->{'name'},
				    'update' => $a->{'update'},
				    'system' => $a->{'system'},
				    'version' => $a->{'version'},
				    'oldversion' => $c->{'version'},
				    'epoch' => $a->{'epoch'},
				    'desc' => $c->{'desc'} || $a->{'desc'},
				    'url' => $a->{'url'},
				    'updatesurl' => $a->{'updatesurl'},
				    'severity' => 0 });
			}
		}
	}
return @rv;
}

# list_possible_installs([nocache])
# Returns a list of packages that could be installed, but are not yet
sub list_possible_installs
{
my ($nocache) = @_;
my @rv;
my @current = &list_current($nocache);
my @avail = &list_available($nocache == 1);
my %currentmap;
foreach my $c (@current) {
	$currentmap{$c->{'name'},$c->{'system'}} = $c;
	}
foreach my $a (sort { $a->{'name'} cmp $b->{'name'} } @avail) {
	my $c = $currentmap{$a->{'name'},$a->{'system'}};
	if (!$c && &installation_candiate($a)) {
		push(@rv, { 'name' => $a->{'name'},
			    'update' => $a->{'update'},
			    'system' => $a->{'system'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $a->{'desc'},
			    'url' => $a->{'url'},
			    'updatesurl' => $a->{'updatesurl'},
			    'severity' => 0 });
		}
	}
return @rv;
}

# csw_to_pkgadd(package)
# On Solaris systems, convert a CSW package name like ap2_modphp5 to a
# real package name like CSWap2modphp5
sub csw_to_pkgadd
{
my ($pn) = @_;
if ($gconfig{'os_type'} eq 'solaris') {
	$pn =~ s/[_\-]//g;
	$pn = "CSW$pn";
	}
return $pn;
}

# fix_pkgadd_version(&package)
# If this is Solaris and the package version is missing, we need to make 
# a separate pkginfo call to get it.
sub fix_pkgadd_version
{
my ($pkg) = @_;
if ($gconfig{'os_type'} eq 'solaris') {
	if (!$pkg->{'version'}) {
		# Make an extra call to get the version
		my @pinfo = &software::package_info($pkg->{'name'});
		$pinfo[4] =~ s/,REV=.*//i;
		$pkg->{'version'} = $pinfo[4];
		}
	else {
		# Trip off the REV=
		$pkg->{'version'} =~ s/,REV=.*//i;
		}
	}
$pkg->{'desc'} =~ s/^\Q$pkg->{'update'}\E\s+\-\s+//;
}

# include_webmin_modules()
# Returns 1 if we should include all Webmin modules and the program itself in
# the list of updates. Returns 2 if only non-core modules should be included.
# The first case is selected when you have a tar.gz install, while the second
# corresponds to a rpm or deb install with Virtualmin modules added.
sub include_webmin_modules
{
return 0 if (&webmin::shared_root_directory());
my $type = &read_file_contents("$root_directory/install-type");
chop($type);
if (!$type) {
	# Webmin tar.gz install
	return 1;
	}
elsif (&foreign_check("virtual-server")) {
	# How was virtual-server installed?
	my $vtype = &read_file_contents(
		&module_root_directory("virtual-server")."/install-type");
	chop($vtype);
	if (!$vtype) {
		# A tar.gz install ... which we may be able to update
		return 2;
		}
	return 0;
	}
elsif (&foreign_check("server-manager")) {
	# How was server-manager installed?
	my $vtype = &read_file_contents(
		&module_root_directory("server-manager")."/install-type");
	chop($vtype);
	if (!$vtype) {
		# A tar.gz install ... which we may be able to update
		return 2;
		}
	return 0;
	}
return 0;
}

# include_usermin_modules()
# Returns 1 if Usermin was installed from a tar.gz, 2 if installed from an
# RPM but virtualmin-specific modules were from a tar.gz
sub include_usermin_modules
{
if (&foreign_installed("usermin")) {
	&foreign_require("usermin", "usermin-lib.pl");
	my $type = &usermin::get_install_type();
	if (!$type) {
		# Usermin tar.gz install
		return 1;
		}
	else {
		# How was virtual-server-theme installed?
		my %miniserv;
		&usermin::get_usermin_miniserv_config(\%miniserv);
		my $vtype = &read_file_contents(
			"$miniserv{'root'}/virtual-server-theme/install-type");
		chop($vtype);
		if (!$vtype) {
			# A tar.gz install ... which we may be able to update
			return 2;
			}
		return 0;
		}
	}
return 0;
}

# webmin_modules_available()
# Returns a list of Webmin modules available for update
sub webmin_modules_available
{
my @rv;
my @urls = $webmin::config{'upsource'} ?
			split(/\t+/, $webmin::config{'upsource'}) :
			( $webmin::update_url );
my %donewebmin;
foreach my $url (@urls) {
	my ($updates, $host, $port, $page, $ssl) =
	    &webmin::fetch_updates($url, $webmin::config{'upuser'},
					 $webmin::config{'uppass'});
	foreach $u (@$updates) {
		# Skip modules that are not for this version of Webmin, IF this
		# is a core module or is not installed
		my %minfo = &get_module_info($u->[0]);
		my %tinfo = &get_theme_info($u->[0]);
		my %info = %minfo ? %minfo : %tinfo;
		my $noinstall = !%info &&
				   $u->[0] !~ /(virtualmin|virtual-server)-/;
		next if (($u->[1] >= &webmin::get_webmin_base_version() + .01 ||
			  $u->[1] < &webmin::get_webmin_base_version()) &&
			 ($noinstall || $info{'longdesc'} ||
			  !$webmin::config{'upthird'}));

		# Skip if not supported on this OS
		my $osinfo = { 'os_support' => $u->[3] };
		next if (!&check_os_support($osinfo));

		next if ($donewebmin{$u->[0],$u->[1]}++);
		push(@rv, { 'update' => $u->[0],
			    'name' => $u->[0],
			    'system' => 'webmin',
			    'desc' => $u->[4] || &text('index_webmin',
					$tinfo{'desc'} || $minfo{'desc'}),
			    'version' => $u->[1],
			    'updatesurl' => $url,
			    'url' => $u->[2],
			   });
		}
	}

# Add latest Webmin version available from Virtualmin, but only if was a
# tar.gz install
my $free = free_virtualmin_licence() ||
	   free_cloudmin_licence();
my ($user, $pass) = &get_user_pass();
if (&include_webmin_modules() == 1) {
	my ($wver, $error);
	&http_download($virtualmin_host, $virtualmin_port,
		       $free ? $free_webmin_version_path : $webmin_version_path,
		       \$wver, \$error, undef, 0, $user, $pass);
	$wver =~ s/\r|\n//g;
	if (!$error) {
		push(@rv, { 'name' => 'webmin',
			    'update' => 'webmin',
			    'system' => 'tgz',
			    'desc' => 'Webmin Package',
			    'version' => $wver });
		}
	}

# And Usermin
if (&include_usermin_modules() == 1) {
	my ($uver, $error);
	&http_download($virtualmin_host, $virtualmin_port,
		     $free ? $free_usermin_version_path : $usermin_version_path,
		     \$uver, \$error, undef, 0, $user, $pass);
	$uver =~ s/\r|\n//g;
	if (!$error) {
		push(@rv, { 'name' => 'usermin',
			    'update' => 'usermin',
			    'system' => 'tgz',
			    'desc' => 'Usermin Package',
			    'version' => $uver });
		}
	}

return @rv;
}

# installation_candiate(&package)
# Returns 1 if some package can be installed, even when it currently isn't.
# For now, only Virtualmin plugins are considered.
sub installation_candiate
{
my ($p) = @_;
if (!defined($webmin_install_type_cache)) {
	$webmin_install_type_cache = &webmin::get_install_type() || "";
	}
if (!defined($usermin_install_type_cache)) {
	&foreign_require("usermin", "usermin-lib.pl");
	$usermin_install_type_cache = &usermin::get_install_type() || "";
	}
return # RPM packages from YUM
       $p->{'system'} eq 'yum' &&
       $p->{'name'} =~ /^(wbm|usm|wbt|ust)-(virtualmin|virtual-server)/ &&
       $webmin_install_type_cache eq 'rpm' ||

       # Debian packages from APT
       $p->{'system'} eq 'apt' &&
       $p->{'name'} =~ /^(webmin|usermin)-(virtualmin|virtual-server)/ &&
       $webmin_install_type_cache eq 'deb' ||

       # Webmin modules from .wbms
       $p->{'system'} eq 'webmin' &&
       $p->{'name'} =~ /^(virtualmin|virtual-server)/ &&
       !$webmin_install_type_cache ||

       # Usermin modules from .wbms
       $p->{'system'} eq 'usermin' &&
       $p->{'name'} =~ /^(virtualmin|virtual-server)/ &&
       !$usermin_install_type_cache;
}

# generate_description(package)
# Fakes up a description for a Webmin/Usermin module/theme package
sub generate_description
{
my ($p) = @_;
my $name = $p->{'name'};
if ($p->{'system'} eq 'yum') {
	# Use yum info to get the description, and cache it
	my %yumcache;
	&read_file_cached($yum_cache_file, \%yumcache);
	if ($yumcache{$p->{'name'}."-".$p->{'version'}}) {
		return $yumcache{$p->{'name'}."-".$p->{'version'}};
		}
	my ($desc, $started_desc);
	open(YUM, "yum info ".quotemeta($name)." |");
	while(<YUM>) {
		s/\r|\n//g;
		if (/^Description:\s*(.*)$/) {
			$desc = $1;
			$started_desc = 1;
			}
		elsif (/\S/ && $started_desc) {
			$desc .= " ".$_;
			}
		}
	close(YUM);
	$desc =~ s/^\s+//;
	$yumcache{$p->{'name'}."-".$p->{'version'}} = $desc;
	&write_file($yum_cache_file, \%yumcache);
	return $desc if ($desc =~ /\S/);
	}
elsif ($p->{'system'} eq 'apt') {
	# Use APT to get description
	my %aptcache;
	&read_file_cached($apt_cache_file, \%aptcache);
	if ($aptcache{$p->{'name'}."-".$p->{'version'}}) {
		return $aptcache{$p->{'name'}."-".$p->{'version'}};
		}
	my ($desc, $started_desc);
	open(YUM, "apt-cache show ".quotemeta($name)." |");
	while(<YUM>) {
		s/\r|\n//g;
		if (/^Description:\s*(.*)$/) {
			$desc = $1;
			}
		}
	close(YUM);
	$aptcache{$p->{'name'}."-".$p->{'version'}} = $desc;
	&write_file($apt_cache_file, \%aptcache);
	return $desc if ($desc =~ /\S/);
	}

return # RPM names
       $name =~ /^wbm-virtualmin-/ ? "Virtualmin plugin" :
       $name =~ /^wbm-vm2-/ ? "Cloudmin plugin" :
       $name =~ /^wbm-/ ? "Webmin module" :
       $name =~ /^wbt-virtualmin-/ ? "Virtualmin theme" :
       $name =~ /^wbt-/ ? "Webmin theme" :
       $name =~ /^usm-/ ? "Usermin module" :
       $name =~ /^ust-/ ? "Usermin theme" :

       # Debian names
       $name =~ /^webmin-virtualmin-/ ? "Virtualmin plugin or theme" :
       $name =~ /^webmin-vm2-/ ? "Cloudmin plugin" :
       $name =~ /^webmin-/ ? "Webmin module" :
       $name =~ /^usermin-virtualmin-/ ? "Usermin theme" :
       $name =~ /^usermin-/ ? "Usermin module" :

       undef;
}

# clear_repository_cache()
# Clear any YUM or APT caches
sub clear_repository_cache
{
if ($software::update_system eq "yum") {
	&execute_command("yum clean all");
	}
elsif ($software::update_system eq "apt") {
	&execute_command("apt-get update");
	}
}

# set_pinned_versions(&packages)
# If on Debian, set available package versions based on APT pinning
sub set_pinned_versions
{
my ($avail) = @_;
my @davail = grep { $_->{'system'} eq 'apt' } @$avail;
return 0 if (!@davail);
my %nmap = map { $_->{'name'}, $_ } @davail;
while(@davail) {
	# Process 256 at a time, to prevent huge command line
	my @dwant;
	while(@davail && @dwant < 256) {
		push(@dwant, shift(@davail));
		}
	my $cmd = "apt-cache policy ".
		  join(" ", map { quotemeta($_->{'name'}) } @dwant);
	&open_execute_command(POLICY, "LANG='' LC_ALL='' $cmd 2>/dev/null", 1);
	my $currpkg;
	while(<POLICY>) {
		if (/^(\S+):/) {
			$currpkg = $nmap{$1};
			}
		elsif (/^\s+Candidate:\s+(\S+)/ && $currpkg) {
			my $candidate = $1;
			$candidate = "" if ($candidate eq "(none)");
			my $cepoch;
			if ($candidate =~ s/^(\d+)://) {
				$cepoch = $1;
				}
			if ($currpkg->{'version'} ne $candidate) {
				$currpkg->{'version'} = $candidate;
				$currpkg->{'epoch'} = $cepoch;
				}
			}
		}
	close(POLICY);
	}
}

# get_changelog(&pacakge)
# If possible, returns information about what has changed in some update
sub get_changelog
{
my ($pkg) = @_;
if ($pkg->{'system'} eq 'yum') {
	# See if yum supports changelog
	if (!defined($supports_yum_changelog)) {
		my $out = &backquote_command("yum -h 2>&1 </dev/null");
		$supports_yum_changelog = $out =~ /changelog/ ? 1 : 0;
		}
	return undef if (!$supports_yum_changelog);

	# Check if we have this info cached
	my $cfile = $yum_changelog_cache_dir."/".
		       $pkg->{'name'}."-".$pkg->{'version'};
	my $cl = &read_file_contents($cfile);
	if (!$cl) {
		# Run it for this package and version
		my $started = 0;
		&open_execute_command(YUMCL, "yum changelog all ".
					     quotemeta($pkg->{'name'}), 1, 1);
		while(<YUMCL>) {
			s/\r|\n//g;
			if (/^\Q$pkg->{'name'}-$pkg->{'version'}\E/) {
				$started = 1;
				}
			elsif (/^==========/ || /^changelog stats/) {
				$started = 0;
				}
			elsif ($started) {
				$cl .= $_."\n";
				}
			}
		close(YUMCL);

		# Save the cache
		if (!-d $yum_changelog_cache_dir) {
			&make_dir($yum_changelog_cache_dir, 0700);
			}
		&open_tempfile(CACHE, ">$cfile");
		&print_tempfile(CACHE, $cl);
		&close_tempfile(CACHE);
		}
	return $cl;
	}
return undef;
}

# Returns 1 if an option should be shown to list all packages. Only true for
# YUM and APT at the moment
sub show_all_option
{
return $software::update_system eq 'apt' || $software::update_system eq 'yum';
}

sub flush_package_caches
{
unlink($current_cache_file);
unlink($current_all_cache_file);
unlink($updates_cache_file);
unlink($available_cache_file);
unlink($available_cache_file.'0');
unlink($available_cache_file.'1');
@packages_available_cache = ( );
%read_cache_file_cache = ( );
}

# list_for_mode(mode, nocache, all)
# If not is 'updates' or 'security', return just updates. Othewise, return
# all available packages.
sub list_for_mode
{
my ($mode, $nocache, $all) = @_;
return $mode eq 'updates' || $mode eq 'security' ?
	&list_possible_updates($nocache, $all) :
	&list_available($nocache, $all);
}

1;

