# Functions for checking for security updates of core Virtualmin packages
# XXX need to setup software.virtualmin.com with packages?
# XXX other packages?

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&foreign_require("software", "software-lib.pl");
&foreign_require("cron", "cron-lib.pl");

@update_packages = ( "apache", "postfix", "sendmail", "bind", "procmail",
		     "spamassassin", "logrotate", "webalizer", "mysql",
		     "postgresql", "proftpd", "clamav", "php4", "mailman",
		     "subversion", "python", "ruby", "irb", "rdoc",
		     "openssl", "perl", "php5", "webmin", "usermin",
		     "virtualmin-modules",
		   ); 

$security_cache_file = "$module_config_directory/security.cache";
$available_cache_file = "$module_config_directory/available.cache";
$current_cache_file = "$module_config_directory/current.cache";
$cron_cmd = "$module_config_directory/update.pl";

$virtualmin_host = $config{'host'} || "software.virtualmin.com";
$virtualmin_port = 80;
$virtualmin_dir = "/updates/$gconfig{'os_type'}";
$virtualmin_list = "$virtualmin_dir/index.txt";
$virtualmin_security = "$virtualmin_dir/security.txt";
$virtualmin_licence = "/etc/virtualmin-license";

# test_connection()
# Returns undef if we can connect OK, or an error message
sub test_connection
{
local ($user, $pass) = &get_user_pass();
return $text{'index_euser'} if (!$user);
local $error;
&http_download($virtualmin_host, $virtualmin_port, $virtualmin_security,
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
# by this module.
sub list_current
{
local ($nocache) = @_;
if ($nocache || &cache_expired($current_cache_file)) {
	local $n = &software::list_packages();
	local @rv;
	foreach my $p (@update_packages) {
		local @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			for(my $i=0; $i<$n; $i++) {
				if ($software::packages{$i,'name'} =~ /^$pn$/) {
					# Found it!
					push(@rv, {
					  'name' =>
					    $software::packages{$i,'name'},
					  'version' =>
					    $software::packages{$i,'version'},
					  'epoch' =>
					    $software::packages{$i,'epoch'},
					  'desc' =>
					    $software::packages{$i,'desc'},
					  'package' => $p,
					  });
					last;
					}
				}
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
		});
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
	local @rv;
	local @avail = &packages_available();
	foreach my $p (@update_packages) {
		local @pkgs = split(/\s+/, &package_resolve($p));
		foreach my $pn (@pkgs) {
			local @mavail = grep { $_->{'name'} =~ /^$pn$/ } @avail;
			foreach my $avail (@mavail) {
				$avail->{'package'} = $p;
				push(@rv, $avail);
				}
			}
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
local $ec = $pkg1->{'epoch'} <=> $pkg2->{'epoch'};
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
return undef;
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

# package_install(package)
# Install some package, either from an update system or from Virtualmin
sub package_install
{
local ($name) = @_;
local @rv;
local ($pkg) = grep { $_->{'name'} eq $name } &list_available();
if (defined(&software::update_system_install)) {
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
	}
else {
	# Need to download and install manually, and print out result.
	local ($pkg) = grep { $_->{'name'} eq $name } &packages_available();
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
}

# get_user_pass()
# Returns the username and password to use for HTTP requests
sub get_user_pass
{
local %licence;
&read_env_file($virtualmin_licence, \%licence);
return ($licence{'SerialNumber'}, $licence{'LicenseKey'});
}

# list_possible_updates([nocache])
# Returns a list of updates that are available. Each element in the array
# is a hash ref containing a name, version, description and severity flag.
# Intended for calling from themes.
sub list_possible_updates
{
local ($nocache) = @_;
local @rv;
local @updates = &list_security_updates($nocache == 1);
local @current = &list_current($nocache);
local @avail = &list_available($nocache == 1);
foreach $c (sort { $a->{'name'} cmp $b->{'name'} } @current) {
	# Work out the status
	($a) = grep { $_->{'name'} eq $c->{'name'} } @avail;
	($u) = grep { $_->{'name'} eq $c->{'name'} } @updates;
	if ($u && &compare_versions($u, $c) > 0 &&
	    $a && &compare_versions($a, $u) >= 0) {
		# Security update is available
		push(@rv, { 'name' => $a->{'name'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $u->{'desc'},
			    'severity' => $u->{'severity'} });
		}
	elsif (&compare_versions($a, $c) > 0) {
		# A regular update is available
		push(@rv, { 'name' => $a->{'name'},
			    'version' => $a->{'version'},
			    'epoch' => $a->{'epoch'},
			    'desc' => $c->{'desc'} || $a->{'desc'},
			    'severity' => 0 });
		}
	}
return @rv;
}

1;

