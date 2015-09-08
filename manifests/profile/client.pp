# == Class: st2::profile::client
#
#  Profile to install all client libraries for st2
#
# === Parameters
#
#  [*version*]     - Version of StackStorm to install
#  [*base_url*]    - CLI config - Base URL lives
#  [*api_version*] - CLI config - API Version
#  [*debug*]       - CLI config - Enable/Disable Debug
#  [*cache_token*] - CLI config - True to cache auth token until expries
#  [*username*]    - CLI config - Auth Username
#  [*password*]    - CLI config - Auth Password
#  [*api_url*]     - CLI config - API URL
#  [*auth_url*]    - CLI config - Auth URL
#
# === Variables
#
#  [*_client_packages*] - Local scoped variable to store all st2 client packages. Default: $::st2::version
#  [*_client_dependencies*] - Local scoped variable to store any client dependencies Default: $::st2::revision
#
# === Examples
#
#  include st2::profile::client
#
class st2::profile::client (
  $auth        = $::st2::auth,
  $version     = $::st2::version,
  $autoupdate  = $::st2::autoupdate,
  $revision    = $::st2::revision,
  $api_url     = $::st2::cli_api_url,
  $auth_url    = $::st2::cli_auth_url,
  $base_url    = $::st2::cli_base_url,
  $username    = $::st2::cli_username,
  $password    = $::st2::cli_password,
  $api_version = $::st2::cli_api_version,
  $cacert      = $::st2::cli_cacert,
  $debug       = $::st2::cli_debug,
  $cache_token = $::st2::cli_cache_token,
  $global_env  = $::st2::global_env,
) inherits ::st2 {
  $_version = $autoupdate ? {
    true    => st2_latest_stable(),
    default => $version,
  }
  $_revision = $autoupdate ? {
    true    => undef,
    default => $revision,
  }
  $_bootstrapped = $::st2client_bootstrapped ? {
    undef   => false,
    default => true,
  }
  $_git_tag = $_version ? {
    /dev/   => 'master',
    default => "v${_version}",
  }

  include '::st2::notices'
  include '::st2::params'

  $_client_packages = $st2::params::st2_client_packages
  $_client_dependencies = $st2::params::debian_client_dependencies

  st2::dependencies::install { $_client_dependencies: }

  st2::package::install { $_client_packages:
    version  => $_version,
    revision => $_revision,
  }

  ### This should be a versioned download too... currently on master
  ## Only attempt to download this if the server has been appropriately bootstrapped.
  if $autoupdate or ! $_bootstrapped {
    wget::fetch { 'Download st2client requirements.txt':
      source      => "https://raw.githubusercontent.com/StackStorm/st2/${_git_tag}/st2client/requirements.txt",
      cache_dir   => '/var/cache/wget',
      destination => '/tmp/st2client-requirements.txt',
      before      => Python::Requirements['/tmp/st2client-requirements.txt'],
    }
  }

  python::requirements { '/tmp/st2client-requirements.txt':
    notify => File['/etc/facter/facts.d/st2client_bootstrapped.txt'],
  }

  # Once the system is properly bootstrapped, leave a breadcrumb for future runs
  file { '/etc/facter/facts.d/st2client_bootstrapped.txt':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0444',
    content => 'st2client_bootstrapped=true',
  }

  file { '/root/.st2':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  # Setup global environment variables:
  if $global_env {
    file { '/etc/profile.d/st2.sh':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('st2/etc/profile.d/st2.sh.erb'),
    }
  }

  Ini_setting {
    ensure  => present,
    path    => '/root/.st2/config',
    require => File['/root/.st2'],
  }

  ini_setting { 'st2_cli_api_url':
    section => 'api',
    setting => 'url',
    value   => $api_url,
  }
  ini_setting { 'st2_cli_general_base_url':
    section => 'general',
    setting => 'base_url',
    value   => $base_url,
  }
  ini_setting { 'st2_cli_general_api_version':
    section => 'general',
    setting => 'api_version',
    value   => $api_version,
  }
  ini_setting { 'st2_cli_general_cacert':
    section => 'general',
    setting => 'cacert',
    value   => $cacert,
  }

  $_cli_debug = $debug ? {
    true    => 'True',
    default => 'False',
  }
  ini_setting { 'st2_cli_cli_debug':
    section => 'cli',
    setting => 'debug',
    value   => $_cli_debug,
  }
  $_cache_token = $cache_token ? {
    true    => 'True',
    default => 'False',
  }
  ini_setting { 'st2_cli_cache_token':
    section => 'cli',
    setting => 'cache_token',
    value   => $_cache_token,
  }

  if $auth {
    ini_setting { 'st2_cli_credentials_username':
      section => 'credentials',
      setting => 'username',
      value   => $username,
    }
    ini_setting { 'st2_cli_credentials_password':
      section => 'credentials',
      setting => 'password',
      value   => $password,
    }
    ini_setting { 'st2_cli_auth_url':
      section => 'auth',
      setting => 'url',
      value   => $auth_url,
    }
  }
}
