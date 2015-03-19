require 'puppet'
require 'puppet/pops'
require 'puppet_x'

module PuppetX::Puppetlabs
  module Migration
    require 'puppet_x/puppetlabs/migration/migration_checker'
    require 'puppet_x/puppetlabs/migration/migration_issues'
  end
end