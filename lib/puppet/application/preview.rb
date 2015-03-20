require 'puppet/application'

class Puppet::Application::Preview < Puppet::Application
  run_mode :master

  def main
    puts 'Hello, world!'
  end
end
