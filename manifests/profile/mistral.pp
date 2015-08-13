# == Class: st2::profile::mistral
#
# This class installs OpenStack Mistral, a workflow engine that integrates with
# StackStorm. Has the option to manage a companion MySQL Server
#
# === Parameters
#  [*manage_mysql*]        - Flag used to have MySQL installed/managed via this profile (Default: false)
#  [*git_branch*]          - Tagged branch of Mistral to download/install
#  [*db_root_password*]    - Root MySQL Password
#  [*db_mistral_password*] - Mistral user MySQL Password
#  [*db_server*]           - Server hosting Mistral DB
#  [*db_database*]         - Database storing Mistral Data
#  [*db_max_pool_size*]    - Max DB Pool size for Mistral Connections
#  [*db_max_overflow*]     - Max DB overload for Mistral Connections
#  [*db_pool_recycle*]     - DB Pool recycle time
#  [*api_url*]             - URI of Mistral backend (e.x.: http://localhost)
#  [*api_port*]            - Port of Mistral backend. (Default: 8989)
#
# === Examples
#
#  include st2::profile::mistral
#
#  class { '::st2::profile::mistral':
#    manage_mysql        => true,
#    db_root_password    => 'datsupersecretpassword',
#    db_mistral_password => 'mistralpassword',
#  }
#
class st2::profile::mistral(
  $autoupdate          = $::st2::autoupdate,
  $manage_mysql        = false,
  $git_branch          = $::st2::mistral_git_branch,
  $db_root_password    = 'StackStorm',
  $db_mistral_password = 'StackStorm',
  $db_server           = 'localhost',
  $db_database         = 'mistral',
  $db_max_pool_size    = '100',
  $db_max_overflow     = '400',
  $db_pool_recycle     = '3600',
  $api_url             = $::st2::mistral_api_url,
  $api_port            = $::st2::mistral_api_port,
  $manage_service      = true,
) inherits st2 {
  include '::st2::dependencies'

  # This needs a bit more modeling... need to understand
  # what current mistral code ships with st2 - jdf

  $_mistral_root = '/opt/openstack/mistral'
  $_bootstrapped = $::mistral_bootstrapped ? {
    undef   => false,
    default => str2bool($::mistral_bootstrapped)
  }
  $_update_vcsroot = $autoupdate ? {
    true    => 'latest',
    default => 'present',
  }

  ### Dependencies ###
  if !defined(Class['::mysql::bindings']) {
    class { '::mysql::bindings':
      client_dev => true,
      daemon_dev => true,
    }
  }

  ### Mistral Downloads ###
  if !defined(File['/opt/openstack']) {
    file { '/opt/openstack':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  file { [ '/etc/mistral', '/etc/mistral/actions']:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Currently, this resource will break in the event that a node is offline,
  # causing a cascading failure in the rest of catalog compilation. The
  # correct answer is to build well-created packages, and this is in fact
  # underway. For now, if $autoupdate is false, detach all of the various
  # downstream dependencies so that compliation continues when git update
  # attempts to run
  if $autoupdate or ! $_bootstrapped {
    $_mistral_root_before = [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
      Python::Virtualenv[$_mistral_root],
      Python::Pip['mysql-python'],
      Exec['setup mistral database'],
    ]
    $_st2mistral_before = [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
    ]
  } else {
    $_mistral_root_before = undef
    $_st2mistral_before = undef
  }

  vcsrepo { $_mistral_root:
    ensure   => $_update_vcsroot,
    source   => 'https://github.com/StackStorm/mistral.git',
    revision => $git_branch,
    provider => 'git',
    require  => File['/opt/openstack'],
    before   => $_mistral_root_before,
  }
  vcsrepo { '/etc/mistral/actions/st2mistral':
    ensure => $_update_vcsroot,
    source => 'https://github.com/StackStorm/st2mistral.git',
    revision => $git_branch,
    provider => 'git',
    require  => File['/etc/mistral/actions'],
    before   => $_st2mistral_before,
  }

  file { '/etc/mistral/wf_trace_logging.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0444',
    source  => 'puppet:///modules/st2/etc/mistral/wf_trace_logging.conf',
  }

  ### END Mistral Downloads ###

  ### Bootstrap Python ###
  python::virtualenv { $_mistral_root:
    ensure       => present,
    version      => 'system',
    systempkgs   => false,
    venv_dir     => "${_mistral_root}/.venv",
    cwd          => $_mistral_root,
    notify       => [
      Exec['setup mistral', 'setup st2mistral plugin'],
      Exec['python_requirementsmistral'],
    ],
    before       => File['/etc/mistral/database_setup.lock'],
  }

  # Not using virtualenv requirements attribute because oslo has bad wheel, and fails
  python::requirements { 'mistral':
    requirements => "${_mistral_root}/requirements.txt",
    virtualenv   => "${_mistral_root}/.venv",
  }

  python::pip { 'mysql-python':
    ensure     => present,
    virtualenv => "${_mistral_root}/.venv",
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
      Exec['setup mistral database'],
    ],
  }

  python::pip { 'python-mistralclient':
    ensure => present,
    url    => "git+https://github.com/StackStorm/python-mistralclient.git@${git_branch}",
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
      Exec['setup mistral database'],
    ],
  }
  ### END Bootstrap Python ###

  ### Bootstrap Mistral ###
  exec { 'setup mistral':
    command     => 'python setup.py develop',
    cwd         => $_mistral_root,
    path        => [
      "${_mistral_root}/.venv/bin",
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    refreshonly => true,
  }

  exec { 'setup st2mistral plugin':
    command     => 'python setup.py develop',
    cwd         => '/etc/mistral/actions/st2mistral',
    path        => [
      "${_mistral_root}/.venv/bin",
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    refreshonly => true,
  }
  ### END Bootstrap Mistral ###


  ### Mistral Config Modeling ###
  ini_setting { 'connection config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'connection',
    value   => "mysql://mistral:${db_mistral_password}@${db_server}/${db_database}",
  }
  ini_setting { 'connection pool config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'max_pool_size',
    value   => $db_max_pool_size,
  }
  ini_setting { 'connection overflow config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'max_overflow',
    value   => $db_max_overflow,
  }
  ini_setting { 'db pool recycle config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'pool_recycle',
    value   => $db_pool_recycle,
  }

  ini_setting { 'pecan settings':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'pecan',
    setting => 'auth_enable',
    value   => 'false',
  }


  File<| tag == 'mistral' |> -> Ini_setting <| tag == 'mistral' |> -> Exec['setup mistral database']
  ### End Mistral Config Modeling ###

  ### Setup Mistral Database ###
  if $manage_mysql {
    class { '::mysql::server':
      root_password => $db_root_password,
    }
  }

  mysql::db { 'mistral':
    user     => 'mistral',
    password => $db_mistral_password,
    before   => Exec['setup mistral database'],
  }

  file { '/etc/mistral/database_setup.lock':
    ensure => file,
    content => 'This file is the lock file that prevents Puppet from attempting to setup the database again. Delete this file if it needs to be re-run',
    notify  => Exec['setup mistral database'],
  }

  exec { 'setup mistral database':
    command     => 'python ./tools/sync_db.py --config-file /etc/mistral/mistral.conf',
    refreshonly => true,
    cwd         => $_mistral_root,
    path        => [
      "${_mistral_root}/.venv/bin",
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    notify      => File['/etc/facter/facts.d/mistral_bootstrapped.txt'],
  }

  # Once everything is done, let the system know so we can avoid some future processing
  file { '/etc/facter/facts.d/mistral_bootstrapped.txt':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0444',
    content => 'mistral_bootstrapped=true'
  }

  ### Set Mistral API Settings. Useful when setting up uWSGI or other server
  if $api_url {
    ini_setting { 'mistral_api_host':
      ensure  => present,
      path    => '/etc/mistral/mistral.conf',
      section => 'api',
      setting => 'host',
      value   => $api_url,
    }

    ini_setting { 'mistral_api_port':
      ensure  => present,
      path    => '/etc/mistral/mistral.conf',
      section => 'api',
      setting => 'port',
      value   => $api_port,
    }
  }

  ### Mistral Init Scripts ###
  if $manage_service {
    case $::osfamily {
      'Debian': {
        file { '/etc/init/mistral.conf':
          ensure => file,
          owner  => 'root',
          group  => 'root',
          mode   => '0444',
          source => 'puppet:///modules/st2/etc/init/mistral.conf',
        }
      }
      'RedHat': {
        file { '/etc/systemd/system/mistral.service':
          ensure => file,
          owner  => 'root',
          group  => 'root',
          mode   => '0444',
          source => 'puppet:///modules/st2/etc/systemd/system/mistral.service',
        }
      }
    }

    service { 'mistral':
      ensure     => running,
      enable     => true,
      hasstatus  => true,
      hasrestart => true,
    }

    # Setup refresh events on config change for mistral
    Ini_setting<| tag == 'mistral' |> ~> Service['mistral']
  }
  ### END Mistral Init Scripts ###
}
