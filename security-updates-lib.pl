# Functions for checking for security updates of core Virtualmin packages
# XXX need to setup software.virtualmin.com with packages?
# XXX authentication?
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
		   ); 

$updates_cache_file = "$module_config_directory/updates.cache";
$available_cache_file = "$module_config_directory/available.cache";
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
local ($list, @rv, $error);
local ($user, $pass) = &get_user_pass();
&http_download($virtualmin_host, $virtualmin_port, $virtualmin_security,
	       \$list, \$error, undef, 0, $user, $pass);
return ( ) if ($error);		# None for this OS
foreach my $l (split(/\r?\n/, $list)) {
	next if ($l =~ /^#/);
	local ($name, $version, $os, $desc) = split(/\s+/, $l, 4);
	if ($name && $version) {
		$os =~ s/;/ /g;
		local %info = ( 'os_support' => $os );
		if (&check_os_support(\%info)) {
			push(@rv, { 'name' => $name,
				    'version' => $version,
				    'desc' => $desc });
			}
		}
	}
return @rv;
}

# list_current(nocache)
# Returns a list of packages and versions for the core packages managed
# by this module.
sub list_current
{
local ($nocache) = @_;
local $n = &software::list_packages();
local @rv;
foreach my $p (@update_packages) {
	local @pkgs = split(/\s+/, &package_resolve($p));
	foreach my $pn (@pkgs) {
		for(my $i=0; $i<$n; $i++) {
			if ($software::packages{$i,'name'} eq $pn) {
				# Found it!
				push(@rv, { 'name' => $pn,
					    'version' =>
					     $software::packages{$i,'version'},
					    'desc' =>
					     $software::packages{$i,'desc'},
					    'package' => $p,
					});
				last;
				}
			}
		}
	}
return @rv;
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
			local ($avail) = grep { $_->{'name'} eq $pn } @avail;
			if ($avail) {
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

# compare_versions(ver1, ver2)
# Returns -1 if ver1 is older than ver2, 1 if newer, 0 if same
sub compare_versions
{
local @sp1 = split(/[\.\-]/, $_[0]);
local @sp2 = split(/[\.\-]/, $_[1]);
for(my $i=0; $i<@sp1 || $i<@sp2; $i++) {
	local $v1 = $sp1[$i];
	local $v2 = $sp2[$i];
	local $comp;
	if ($v1 =~ /^\d+$/ && $v2 =~ /^\d+$/) {
		$comp = $v1 <=> $v2;
		}
	else {
		$comp = $v1 cmp $v2;
		}
	return $comp if ($comp);
	}
return 0;
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
if (open(RESOLV, "$module_root_directory/resolve.$gconfig{'os_type'}")) {
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
	return &software::update_system_available();
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
					    'desc' => $desc });
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
if (defined(&software::update_system_install)) {
	return &software::update_system_install($name);
	}
else {
	# Need to download and install manually, and print out result.
	local ($pkg) = grep { $_->{'name'} eq $name } &packages_available();
	if (!$pkg) {
		print &text('update_efound', $name),"<br>\n";
		return ( );
		}
	local @rv;

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
		    &compare_versions($curr->{'version'}, $dver) < 0) {
			# We need this dependency!
			print &text('update_depend', $dname, $dver),"<br>\n";
			print "<ul>\n";
			local @dgot = &package_install($dname);
			print "</ul>\n";
			if (@dgot) {
				push(@rv, @dgot);
				}
			else {
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
		print &text('update_edownload', $pfile, $error),
		      "<br>\n";
		return ( );
		}

	# Install it
	local %fakein = ( 'upgrade' => 1 );
	local $err = &software::install_package($temp, $pkg->{'name'}, \%fakein);
	if ($err) {
		print &text('update_einstall', $err),"<br>\n";
		return ( );
		}
	else {
		local @info = &software::package_info($pkg->{'name'},
						      $pkg->{'version'});
		print &text('update_done', $info[0], $info[4], $info[2]),
		      "<br>\n";
		return ( @rv, $info[0] );
		}
	}
}

# get_user_pass()
# Returns the username and password to use for HTTP requests
sub get_user_pass
{
local %licence;
&read_env_file($virtualmin_licence, \%licence);
return ($licence{'SerialNumber'}, $licence{'LicenseKey'});
}

1;

