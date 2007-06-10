
do 'security-updates-lib.pl';

sub module_install
{
# Force clear all caches, as collected information may have changed
unlink($security_cache_file);
unlink($available_cache_file);
unlink($current_cache_file);
}

