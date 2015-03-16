require 'puppetlabs_spec_helper/rake_tasks'

task :rubocop  do
  require 'rubocop'
  cli = RuboCop::CLI.new
  cli.run(%w(-D -f s))
end
