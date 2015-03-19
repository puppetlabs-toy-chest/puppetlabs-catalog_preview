# Migration issues produced by a MigrationChecker
#
module PuppetX::Puppetlabs::Migration::MigrationIssues

  # (see Puppet::Pops::Issues#issue)
  def self.issue (issue_code, *args, &block)
    Puppet::Pops::Issues.issue(issue_code, *args, &block)
  end

  MIGRATE4_AMBIGOUS_INTEGER = issue :MIGRATE4_AMBIGOUS_INTEGER, :value, :radix do
    formatted = sprintf("'%##{radix == 8 ? 'o' : 'x'}'", value)
    "This #{radix == 8 ? 'octal' : 'hex'} value evaluates to the decimal value '#{value}': Quote if the String #{formatted} was intended."
  end

  MIGRATE4_AMBIGOUS_FLOAT = issue :MIGRATE4_AMBIGOUS_FLOAT, :value do
    "This value evaluates to the imprecise floating point number #{value}: Quote if a String value was intended"
  end

end