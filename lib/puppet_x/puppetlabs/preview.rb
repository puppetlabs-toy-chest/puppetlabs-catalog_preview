require 'puppet'
require 'puppet/pops'

module PuppetX
  module Puppetlabs
    module Migration
      DOUBLE_COLON = '::'.freeze
      EMPTY_HASH = {}.freeze
      EMPTY_ARRAY = [].freeze
      UNDEFINED_ID = -1

      CATALOG_DELTA = 0
      GENERAL_ERROR = 1
      BASELINE_FAILED = 2
      PREVIEW_FAILED = 3

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
