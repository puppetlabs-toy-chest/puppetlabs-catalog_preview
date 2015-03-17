# Migration issues produced by a MigrationChecker
#
module PuppetX::Puppetlabs::Migration::MigrationIssues

  # (see Puppet::Pops::Issues#issue)
  def self.issue (issue_code, *args, &block)
    Puppet::Pops::Issues.issue(issue_code, *args, &block)
  end

#  SAMPLE_ISSUE = issue :SAMPLE_ISSUE, :name do
#    "All is not well in the: #{semantic} named #{name}."
#  end

end