# An implementation of the MigrationChecker API
# This class should be added in the puppet context under the key :migration_Checker
# when the future parser and evaluator is operating in order to get callbacks to the methods
# of this class.
#
class PuppetX::Puppetlabs::Migration::MigrationChecker < Puppet::Pops::Migration::MigrationChecker
  def initialize()
    # TODO: configure acceptors
  end
end