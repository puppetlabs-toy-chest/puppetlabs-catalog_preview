require 'puppet'
require 'puppet/pops'

module PuppetX
  module Puppetlabs
    module Migration
      require 'puppet_x/puppetlabs/migration/migration_issues'
      require 'puppet_x/puppetlabs/migration/migration_checker'
      require 'puppet_x/puppetlabs/migration/catalog_delta_model'
      require 'puppet_x/puppetlabs/migration/overview_model'
    end
    module Preview
      require 'puppet_x/puppetlabs/preview/errors'
    end
  end
end
