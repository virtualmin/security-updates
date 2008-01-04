# Functions for checking for security updates of core Virtualmin packages

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&foreign_require("software", "software-lib.pl");
&foreign_require("cron", "cron-lib.pl");
&foreign_require("webmin", "webmin-lib.pl");

@update_packages = ( "apache", "postfix", "sendmail", "bind", "procmail",
		     "spamassassin", "logrotate", "webalizer", "mysql",
		     "postgresql", "proftpd", "clamav", "php4", "mailman",
		     "subversion", "python", "ruby", "irb", "rdoc", "rubygems",
		     "openssl", "perl", "php5", "webmin", "usermin",
		     "fcgid", "awstats", "dovecot", "virtualmin-modules",
		   ); 

$security_cache_file = "$module_config_directory/security.cache";
$available_cache_file = "$module_config_directory/available.cache";
$current_cache_file = "$module_config_directory/current.cache";
$cron_cmd = "$module_config_directory/update.pl";

$virtualmin_host = $config{'host'} || "software.virtualmin.com";
$server_manager_host = "vm2.virtualmin.com";
$virtualmin_port = 80;
$virtualmin_dir = "$config{'suffix'}/updates/$gconfig{'os_type'}";
$virtualmin_list = "$virtualmin_dir/index.txt";
$virtualmin_security = "$virtualmin_dir/security.txt";
$virtualmin_licence = "/etc/virtualmin-license";
$server_manager_licence = "/etc/server-manager-license";
$webmin_version_path = "$config{'suffix'}/wbm/webmin-version";
$usermin_version_path = "$config{'suffix'}/wbm/usermin-version";
$webmin_download_path = "$config{'suffix'}/wbm/webmin-current.tar.gz";
$usermin_download_path = "$config{'suffix'}/wbm/usermin-current.tar.gz";

$yum_cache_file = "$module_config_directory/yumcache";
$apt_cache_file = "$module_config_directory/aptcache";

# test_connection()
# Returns undef if we can connect OK, or an error message
sub test_connection
{
return undef if (&free_virtualmin_licence());	# GPL install
local ($user, $pass, $host) = &get_user_pass();
return $text{'index_euser'} if (!$user);
local $error;
&http_download($host, $virtualmin_port, $virtualmin_security,
	       \$list, \$error, undef, 0, $user, $pass);
if ($error =~ /authorization|authentication/i) {
	return $text{'index_eauth'};
	}
elsif ($error) {
	return $error;
	}
else {
	return undef;
	}
}

# list_security_updates()
# Returns a list of packages, versions and problem descriptions from the
# Virtualmin server. 
sub list_security_updates
{
local ($nocache) = @_;
if ($nocache || &cache_expired($security_cache_file)) {
	local ($list, @rv, $error);
	return ( ) if (&free_virtualmin_licence());	# GPL install
	local ($user, $pass) = &get_user_pass();
	&http_download($virtualmin_host, $virtualmin_port, $virtualmin_security,
		       \$list, \$error, undef, 0, $user, $pass);
	return ( ) if ($error);		# None for this OS
	foreach my $l (split(/\r?\n/, $list)) {
		next if ($l =~ /^#/);
		local ($name, $version, $severity, $os, $desc) = split(/\s+/, $l, 5);
		if ($name && $version) {
			$os =~ s/;/ /g;
			local %info = ( 'os_support' => $os );
			if (&check_os_support(\%info)) {
				local $epoch;
				if ($version =~ s/^(\S+)://) {
					$epoch = $1;
					}
				push(@rv, { 'name' => $name,
					    'version' => $version,
					    'epoch' => $epoch,
					    'severity' => $severity,
					    'desc' => $desc });
				}
			}
		}
	&write_cache_file($security_cache_file, \@rv);
	return @rv;
	}
else {
	return &read_cache_file($security_cache_file);
	}
}

# list_current(nocache)
# Returns a list of packages and versions for the core packages managed
# by this module. Return keys are :
#  name - The local package name (ie. CSWapache2)
#  update - Name used to refer to it by the updates system (ie. apache2)
#  version - Version number
#  epoch - Epoch part of the version
#  desc - Human-readable description
#  package - Original generic program, like apache
sub list_current
{
local ($nocache) = @_;
if ($nocache || &cache_expired($current_cache_file)) {
	local $n = &software::list_packages();
	local @rv;
	foreach my $p (@update_packages) {
		local @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			my $updatepn = $pn;
			$pn = &csw_to_pkgadd($pn);
			for(my $i=0; $i<$n; $i++) {
				if ($software::packages{$i,'name'} =~ /^$pn$/) {
					# Found a match
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
					  });
					&fix_pkgadd_version($rv[$#rv]);
					}
				}
			}
		}

	# Filter out dupes and sort by name
	@rv = sort { $a->{'name'} cmp $b->{'name'} ||
		     &compare_versions($b, $a) } @rv;
	local %done;
	@rv = grep { !$done{$_->{'name'},$_->{'system'}}++ } @rv;

	local $incwebmin = &include_webmin_modules();
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
local ($nocache) = @_;
local $n = &software::list_packages();
local @rv;
local %pkgmap;
foreach my $p (@update_packages) {
	local @pkgs = split(/\s+/, &package_resolve($p));
	foreach my $pn (@pkgs) {
		$pkgmap{$pn} = $p;
		}
	}
for(my $i=0; $i<$n; $i++) {
	push(@rv, { 'name' => $software::packages{$i,'name'},
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
return @rv;
}

# list_available(nocache)
# Returns the names and versions of packages available from the update
# system, that we are interested in.
sub list_available
{
local ($nocache) = @_;
if ($nocache || &cache_expired($available_cache_file)) {
	# Get from update system
	local @rv;
	local @avail = &packages_available();
	foreach my $p (@update_packages) {
		local @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			local @mavail = grep { $_->{'name'} =~ /^$pn$/ } @avail;
			foreach my $avail (@mavail) {
				$avail->{'update'} = $avail->{'name'};
				$avail->{'name'} = &csw_to_pkgadd(
							$avail->{'name'});
				$avail->{'package'} = $p;
				if (&installation_candiate($avail)) {
					$avail->{'desc'} ||=
						&generate_description($avail);
					}
				push(@rv, $avail);
				}
			}
		}

	if (&include_webmin_modules()) {
		# Get from Webmin updates services. We exclude Webmin and
		# Usermin for now, as they cannot be updated via YUM.
		@rv = grep { $_->{'name'} ne 'webmin' &&
			     $_->{'name'} ne 'usermin' } @rv;
		push(@rv, &webmin_modules_available());
		}

	if (!@rv) {
		# Failed .. fall back to cache
		@rv = &read_cache_file($available_cache_file);
		}
	&write_cache_file($available_cache_file, \@rv);
	return @rv;
	}
else {
	return &read_cache_file($available_cache_file);
	}
}

sub cache_expired
{
local ($file) = @_;
local @st = stat($file);
if (!@st || !$config{'cache_time'} ||
    time()-$st[9] > $config{'cache_time'}*60*60) {
	return 1;
	}
return 0;
}

sub write_cache_file
{
local ($file, $arr) = @_;
&open_tempfile(FILE, ">$file");
&print_tempfile(FILE, &serialise_variable($arr));
&close_tempfile(FILE);
}

sub read_cache_file
{
local ($file) = @_;
&open_readfile(FILE, $file);
local $line = <FILE>;
close(FILE);
local $arr = &unserialise_variable($line);
return @$arr;
}

# compare_versions(&pkg1, &pk2)
# Returns -1 if the version of pkg1 is older than pkg2, 1 if newer, 0 if same
sub compare_versions
{
local ($pkg1, $pkg2) = @_;
if ($pkg1->{'system'} eq 'webmin' && $pkg2->{'system'} eq 'webmin') {
	# Webmin module version compares are always numeric
	return $pkg1->{'version'} <=> $pkg2->{'version'};
	}
local $ec = $pkg1->{'epoch'} <=> $pkg2->{'epoch'};
if ($ec && ($pkg1->{'epoch'} eq '' || $pkg2->{'epoch'} eq '') &&
    $pkg1->{'system'} eq 'apt') {
	# On some Debian systems, we don't have a local epoch
	$ec = undef;
	}
return $ec ||
       &software::compare_versions($pkg1->{'version'}, $pkg2->{'version'});
}

sub find_cron_job
{
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $cron_cmd } @jobs;
return $job;
}

# package_resolve(name)
# Given a package code name from @update_packages, returns a string of the
# underlying packages that implement it. This may come from the update system
# if the OS has one (YUM or APT, or from Virtualmin's built-in list)
sub package_resolve
{
local ($name) = @_;
local $realos = $gconfig{'real_os_type'};
$realos =~ s/ /-/g;
local $realver = $gconfig{'real_os_version'};
$realver =~ s/ /-/g;
if (open(RESOLV, "$module_root_directory/resolve.$realos-$realver") ||
    open(RESOLV, "$module_root_directory/resolve.$realos") ||
    open(RESOLV, "$module_root_directory/resolve.$gconfig{'os_type'}-$gconfig{'os_version'}") ||
    open(RESOLV, "$module_root_directory/resolve.$gconfig{'os_type'}")) {
	local $rv;
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
# Returns a list of available packages, as hash references with name and
# version keys. This may come from the update system (APT or YUM), or from
# the Virtualmin servers.
sub packages_available
{
if (defined(&software::update_system_available)) {
	# From a decent package system
	local @rv = software::update_system_available();
	local %done;
	foreach my $p (@rv) {
		$p->{'system'} = $software::update_system;
		$p->{'version'} =~ s/,REV=.*//i;		# For CSW
		$done{$p->{'name'}} = $p;
		}
	if ($software::update_system eq "yum" &&
	    &has_command("up2date")) {
		# YUM is the package system select, but up2date is installed
		# too (ie. RHEL). Fetch its packages too..
		if (!$done_rhn_lib++) {
			do "../software/rhn-lib.pl";
			}
		local @rhnrv = &update_system_available();
		foreach my $p (@rhnrv) {
			$p->{'system'} = "rhn";
			local $d = $done{$p->{'name'}};
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
	return @rv;
	}
else {
	# From virtualmin's server
	local ($list, @rv);
	local ($user, $pass) = &get_user_pass();
	&http_download($virtualmin_host, $virtualmin_port, $virtualmin_list,
		       \$list, undef, undef, 0, $user, $pass);
	foreach my $l (split(/\r?\n/, $list)) {
		next if ($l =~ /^#/);
		local ($name, $version, $file, $os, $deps, $desc) = split(/\s+/, $l, 6);
		if ($name && $version) {
			$os =~ s/;/ /g;
			local %info = ( 'os_support' => $os );
			if (&check_os_support(\%info)) {
				push(@rv, { 'name' => $name,
					    'version' => $version,
					    'file' => $file,
					    'depends' => $deps eq "none" ? [ ] :
						[ split(/;/, $deps) ],
					    'desc' => $desc,
					    'system' => 'virtualmin', });
				}
			}
		}
	return @rv;
	}
}

# package_install(package, [system])
# Install some package, either from an update system or from Virtualmin. Returns
# a list of updated package names.
sub package_install
{
local ($name, $system) = @_;
local @rv;
local ($pkg) = grep { $_->{'update'} eq $name &&
		      ($_->{'system'} eq $system || !$system) }
		    &list_available();
if (!$pkg) {
	print &text('update_efindpkg', $name),"<p>\n";
	return ( );
	}
if ($pkg->{'system'} eq 'webmin') {
	# Webmin module, which we can download and install 
	local ($host, $port, $page, $ssh) =
		&parse_http_url($pkg->{'updatesurl'});
	local ($mhost, $mport, $mpage, $mssl) =
		&parse_http_url($pkg->{'url'}, $host, $port, $page, $ssl);
	local $mfile;
	($mfile = $mpage) =~ s/^(.*)\///;
	local $mtemp = &transname($mfile);
	local $error;
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
	local $irv = &webmin::install_webmin_module($mtemp, 1, 0);
	if (!ref($irv)) {
		print &text('update_ewinstall', $irv),"<p>\n";
		}
	else {
		print $text{'update_winstalled'},"<p>\n";
		}
	@rv = map { /([^\/]+)$/; $1 } @{$irv->[1]};
	}
elsif ($pkg->{'system'} eq 'tgz') {
	# Tar file of Webmin or Usermin, which we have to download and
	# install into the destination directory
	local $temp = &transname($pkg->{'name'}."-".$pkg->{'version'}.
				 ".tar.gz");
	local $error;
	print &text('update_tgzdownload', ucfirst($pkg->{'name'})),"<br>\n";
	local ($user, $pass) = &get_user_pass();
	local $path = $pkg->{'name'} eq 'webmin' ? $webmin_download_path
						 : $usermin_download_path;
	&http_download($virtualmin_host, $virtualmin_port, $path,
		       $temp, \$error, undef, 0, $user, $pass);
	if ($error || !-r $temp) {
		print &text('update_ewdownload', $error),"<p>\n";
		return ( );
		}
	else {
		local @st = stat($temp);
		print &text('update_tgzdownloaded', &nice_size($st[7])),"<p>\n";
		}

	# Get the current install directory
	print $text{'update_tgzuntar'},"<br>\n";
	local $curdir;
	if ($pkg->{'name'} eq 'webmin') {
		$curdir = $root_directory;
		$pkg_config_dir = $config_directory;
		}
	else {
		local %miniserv;
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
	local $targetdir = &read_file_contents("$pkg_config_dir/install-dir");
	$targetdir =~ s/\r|\n//g;

	# Un-tar the archive next to it
	local $pardir = $curdir;
	$pardir =~ s/\/([^\/]+)$//;
	local $out = &backquote_command("cd ".quotemeta($pardir)." && ".
					"gunzip -c $temp | tar xf -");
	if ($?) {
		local @lines = split(/\n/, $out);
		while(@lines > 10) { shift(@lines); }  # Last 10 only
		print "<pre>",&html_escape(join("\n", @lines)),"</pre>\n";
		print $text{'update_etgzuntar'},"<p>\n";
		return ( );
		}
	local $xtractdir = $pardir."/".$pkg->{'name'}."-".$pkg->{'version'};
	print $text{'update_tgzuntardone'},"<p>\n";

	# Save this CGI from being killed by the upgrade
	$SIG{'TERM'} = 'IGNORE';

	# Run setup.sh to upgrade
	print $text{'update_tgzsetup'},"<br>\n";
	print "<pre>";
	&clean_environment();
	&open_execute_command(SETUP, "cd $xtractdir && config_dir=$pkg_config_dir ./setup.sh $targetdir 2>&1 </dev/null", 1);
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
		@rv = &software::update_system_install($name);
		}
	else {
		# Another update system exists!! Use it..
		if (!$done_rhn_lib++) {
			do "../software/$pkg->{'system'}-lib.pl";
			}
		if (!$done_rhn_text++) {
			%text = ( %text, %software::text );
			}
		@rv = &update_system_install($name);
		}
	&reset_environment();
	}
else {
	# Need to download and install manually, and print out result.
	local ($pkg) = grep { $_->{'name'} eq $name &&
		      	      ($_->{'system'} eq $system || !$system) }
			    &packages_available();
	if (!$pkg) {
		print &text('update_efound', $name),"<br>\n";
		return ( );
		}

	# Recursively resolve any dependencies
	local @current = &list_all_current(1);
	foreach my $d (@{$pkg->{'depends'}}) {
		local ($dname, $dver);
		if ($d =~ /^(\S+)\-([^\-]+)\-([^\-])+$/) {
			$dname = $1;
			$dver = "$2-$3";
			}
		elsif ($d =~ /^(\S+)\-([^\-]+)$/) {
			$dname = $1;
			$dver = $2;
			}
		else {
			$dname = $d;
			}
		local ($curr) = grep { $_->{'name'} eq $dname } @current;
		if (!$curr ||
		    &compare_versions($curr, { 'version' => $dver }) < 0) {
			# We need this dependency!
			print &text('update_depend', $dname, $dver),"<br>\n";
			print "<ul>\n";
			local @dgot = &package_install($dname);
			print "</ul>\n";
			if (@dgot) {
				push(@rv, @dgot);
				}
			else {
				# Could not find!
				return ( );
				}
			}
		}

	# Fetch the package file
	local ($phost, $pport, $ppage, $pssl) = &parse_http_url($pkg->{'file'}, $virtualmin_host, $virtualmin_port, $virtualmin_dir."/", 0);
	local $pfile = $ppage;
	$pfile =~ s/^(.*)\///;
	local $temp = &tempname($pfile);
	local $error;
	$progress_callback_url = "http://$phost:$pport$ppage";
	local ($user, $pass) = &get_user_pass();
	&http_download($phost, $pport, $ppage, $temp, \$error,
		       \&progress_callback, 0, $user, $pass);
	if ($error) {
		# Could not download
		print &text('update_edownload', $pfile, $error),
		      "<br>\n";
		return ( );
		}

	# Install it
	local %fakein = ( 'upgrade' => 1 );
	local $err = &software::install_package($temp, $pkg->{'name'}, \%fakein);
	if ($err) {
		# Could not install
		print &text('update_einstall', $err),"<br>\n";
		return ( );
		}
	else {
		local @info = &software::package_info($pkg->{'name'},
						      $pkg->{'version'});
		print &text('update_done', $info[0], $info[4], $info[2]),
		      "<br>\n";
		push(@rv, $info[0]);
		}
	}
# Flush installed cache
unlink($current_cache_file);
return @rv;
}

# get_user_pass()
# Returns the username and password to use for HTTP requests, and the base site
sub get_user_pass
{
local %licence;
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
if (-r $virtualmin_licence) {
	&read_env_file($virtualmin_licence, \%licence);
	return 1 if ($licence{'SerialNumber'} eq 'GPL');
	}
return 0;
}

# list_possible_updates([nocache])
# Returns a list of updates that are available. Each element in the array
# is a hash ref containing a name, version, description and severity flag.
# Intended for calling from themes. Nocache 0=cache everything, 1=flush all
# caches, 2=flush only current
sub list_possible_updates
{
local ($nocache) = @_;
local @rv;
local @updates = &list_security_updates($nocache == 1);
local @current = &list_current($nocache);
local @avail = &list_available($nocache == 1);
local ($a, $c, $u);
foreach $c (sort { $a->{'name'} cmp $b->{'name'} } @current) {
	# Work out the status
	($a) = grep { $_->{'name'} eq $c->{'name'} &&
		      $_->{'system'} eq $c->{'system'} } @avail;
	($u) = grep { $_->{'name'} eq $c->{'name'} &&
		      $_->{'system'} eq $c->{'system'} } @updates;
	if ($u && &compare_versions($u, $c) > 0 &&
	    $a && &compare_versions($a, $u) >= 0) {
		# Security update is available
		push(@rv, { 'name' => $a->{'name'},
			    'update' => $a->{'update'},
			    'system' => $a->{'system'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $u->{'desc'},
			    'severity' => $u->{'severity'} });
		}
	elsif ($a->{'version'} && &compare_versions($a, $c) > 0) {
		# A regular update is available
		push(@rv, { 'name' => $a->{'name'},
			    'update' => $a->{'update'},
			    'system' => $a->{'system'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $c->{'desc'} || $a->{'desc'},
			    'severity' => 0 });
		}
	}
return @rv;
}

# list_possible_installs([nocache])
# Returns a list of packages that could be installed, but are not yet
sub list_possible_installs
{
local ($nocache) = @_;
local @rv;
local @current = &list_current($nocache);
local @avail = &list_available($nocache == 1);
local ($a, $c);
foreach $a (sort { $a->{'name'} cmp $b->{'name'} } @avail) {
	($c) = grep { $_->{'name'} eq $a->{'name'} &&
		      $_->{'system'} eq $a->{'system'} } @current;
	if (!$c && &installation_candiate($a)) {
		push(@rv, { 'name' => $a->{'name'},
			    'update' => $a->{'update'},
			    'system' => $a->{'system'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $a->{'desc'},
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
local ($pn) = @_;
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
local ($pkg) = @_;
if (!$pkg->{'version'} && $gconfig{'os_type'} eq 'solaris') {
	local @pinfo = &software::package_info($pkg->{'name'});
	$pinfo[4] =~ s/,REV=.*//i;
	$pkg->{'version'} = $pinfo[4];
	}
$pkg->{'desc'} =~ s/^$pkg->{'update'}\s+\-\s+//;
}

# include_webmin_modules()
# Returns 1 if we should include all Webmin modules and the program itself in
# the list of updates. Returns 2 if only non-core modules should be included.
# The first case is selected when you have a tar.gz install, while the second
# corresponds to a rpm or deb install with Virtualmin modules added.
sub include_webmin_modules
{
return 0 if (&webmin::shared_root_directory());
local $type = &read_file_contents("$root_directory/install-type");
chop($type);
if (!$type) {
	# Webmin tar.gz install
	return 1;
	}
else {
	# How was virtual-server installed?
	return 0 if (!&foreign_check("virtual-server"));
	local $vtype = &read_file_contents(
		&module_root_directory("virtual-server")."/install-type");
	chop($vtype);
	if (!$vtype) {
		# A tar.gz install ... which we may be able to update
		return 2;
		}
	return 0;
	}
}

# include_usermin_modules()
# Returns 1 if Usermin was installed from a tar.gz, 2 if installed from an
# RPM but virtualmin-specific modules were from a tar.gz
sub include_usermin_modules
{
if (&foreign_installed("usermin")) {
	&foreign_require("usermin", "usermin-lib.pl");
	local $type = &usermin::get_install_type();
	if (!$type) {
		# Usermin tar.gz install
		return 1;
		}
	else {
		# How was virtual-server-theme installed?
		local %miniserv;
		&usermin::get_usermin_miniserv_config(\%miniserv);
		local $vtype = &read_file_contents(
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
local @rv;
local @urls = $webmin::config{'upsource'} ?
			split(/\t+/, $webmin::config{'upsource'}) :
			( $webmin::update_url );
local %donewebmin;
foreach my $url (@urls) {
	local ($updates, $host, $port, $page, $ssl) =
	    &webmin::fetch_updates($url, $webmin::config{'upuser'},
					 $webmin::config{'uppass'});
	foreach $u (@$updates) {
		# Skip modules that are not for this version of Webmin, IF this
		# is a core module or is not installed
		local %minfo = &get_module_info($u->[0]);
		local %tinfo = &get_theme_info($u->[0]);
		local %info = %minfo ? %minfo : %tinfo;
		local $noinstall = !%info &&
				   $u->[0] !~ /(virtualmin|virtual-server)-/;
		next if (($u->[1] >= &webmin::get_webmin_base_version() + .01 ||
			  $u->[1] < &webmin::get_webmin_base_version()) &&
			 ($noinstall || $info{'longdesc'} ||
			  !$webmin::config{'upthird'}));

		# Skip if not supported on this OS
		local $osinfo = { 'os_support' => $u->[3] };
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
local $free = free_virtualmin_licence();
local ($user, $pass) = &get_user_pass();
if (!$free && &include_webmin_modules() == 1) {
	local ($wver, $error);
	&http_download($virtualmin_host, $virtualmin_port, $webmin_version_path,
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
if (!$free && &include_usermin_modules() == 1) {
	local ($uver, $error);
	&http_download($virtualmin_host, $virtualmin_port,$usermin_version_path,
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
local ($p) = @_;
if (!defined($webmin_install_type_cache)) {
	$webmin_install_type_cache = &webmin::get_install_type();
	}
if (!defined($usermin_install_type_cache)) {
	&foreign_require("usermin", "usermin-lib.pl");
	$usermin_install_type_cache = &usermin::get_install_type();
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
local ($p) = @_;
local $name = $p->{'name'};
if ($p->{'system'} eq 'yum') {
	# Use yum info to get the description, and cache it
	local %yumcache;
	&read_file_cached($yum_cache_file, \%yumcache);
	if ($yumcache{$p->{'name'}."-".$p->{'version'}}) {
		return $yumcache{$p->{'name'}."-".$p->{'version'}};
		}
	local ($desc, $started_desc);
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
	local %aptcache;
	&read_file_cached($apt_cache_file, \%aptcache);
	if ($aptcache{$p->{'name'}."-".$p->{'version'}}) {
		return $aptcache{$p->{'name'}."-".$p->{'version'}};
		}
	local ($desc, $started_desc);
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
       $name =~ /^wbm-/ ? "Webmin module" :
       $name =~ /^wbt-virtualmin-/ ? "Virtualmin theme" :
       $name =~ /^wbt-/ ? "Webmin theme" :
       $name =~ /^usm-/ ? "Usermin module" :
       $name =~ /^ust-/ ? "Usermin theme" :

       # Debian names
       $name =~ /^webmin-virtualmin-/ ? "Virtualmin plugin or theme" :
       $name =~ /^webmin-/ ? "Webmin module" :
       $name =~ /^usermin-virtualmin-/ ? "Usermin theme" :
       $name =~ /^usermin-/ ? "Usermin module" :

       undef;
}

1;

