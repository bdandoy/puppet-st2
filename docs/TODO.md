# TODO List for this project

- Install and configure st2chatops
- Reorganization effort
  - Migrate to a "modern" puppet model like: https://github.com/puppetlabs/puppetlabs-postgresql
  - All things in st2::profiles::xxx move to st2
  - Create sub folders for each "profile" (server, client, etc)
  - Decompose each "profile" into its parts (config, repo, install, service, etc)
- Ability to install different st2 versions
- Chatops
- Support MongoDB 3.4
- Test alternate auth sources
  - mongodb
  - pam
  - proxy
- Support alternate auth backends
  - LDAP
  - Keystone
- Remove unused code
  - Tiller
  - Unused variables in this like st2::params
  - Unused class level parameters in things like ::st2
- More unit tests
- Figure out how to test different platforms via docker in Travis
- Automated dev environment setup
  - install different ruby versions with something like chruby
- Cleanup class level comments
- Create r10k repos with Puppetfiles detailing exact module versions for each supported OS
  - RHEL 6
  - RHEL 7
  - Ubuntu 14.04
  - Ubuntu 16.04
