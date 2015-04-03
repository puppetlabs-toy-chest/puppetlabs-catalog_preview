require 'beaker-rspec/spec_helper'
require 'beaker-rspec/helpers/serverspec'

def lookup_in_env(env_variable_name, project_name, default)
  project_specific_name = "#{project_name.upcase.gsub('-','_')}_#{env_variable_name}"
  ENV[project_specific_name] || ENV[env_variable_name] || default
end

def build_giturl(project_name, git_fork = nil, git_server = nil)
  git_fork ||= lookup_in_env('FORK', project_name, 'puppetlabs')
  git_server ||= lookup_in_env('GIT_SERVER', project_name, 'github.com')
  repo = (git_server == 'github.com') ?
    "#{git_fork}/#{project_name}.git" :
    "#{git_fork}-#{project_name}.git"
    " git@#{git_server}:#{repo}"
end

RSpec.configure do |c|
  unless ENV['RS_PROVISION'] == 'no' or ENV['BEAKER_provision'] == 'no'
    puppet_sha   = ENV['PUPPET_VERSION']
    if hosts.options[:type] =~ /foss/ && puppet_sha
      install_package(master, 'git')
      tmp_repositories = []
      ['puppet', 'facter#2.x', 'hiera'].each do |uri|
        uri += '#' + puppet_sha if puppet_sha && uri =~ /^puppet/
        project = uri.split('#')
        newURI = "#{build_giturl(project[0])}#{newURI}##{project[1]}"
        tmp_repositories << extract_repo_info_from(newURI)
      end

      repositories = order_packages(tmp_repositories)
      on master, "echo #{GitHubSig} >> $HOME/.ssh/known_hosts"

      repositories.each do |repository|
        step "Install #{repository[:name]}"
        install_from_git master, SourcePath, repository
      end

      step "ensure puppet user and group added to master because this is what the packages do" do
        on master, puppet('resource user puppet ensure=present')
        on master, puppet('resource group puppet ensure=present')
      end
    else
      hosts.each do |host|
        # Install Puppet
        if host[:type] =~ /foss/
          install_puppet
        else
          install_pe
        end
      end
    end
  end

  # Project root
  proj_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    # Install module and dependencies
    # if forge_host is included in options, this installs via pmt
    #   if not, it scp's it to 'default' host :-\
    #   if running this on foss, make sure to specify type as :foss
    if ENV['SPEC_FORGE']
      puppet_module_install(:source => proj_root, :module_name => 'preview', :forge_host => ENV['SPEC_FORGE'])
    else
      puppet_module_install(:source => proj_root, :module_name => 'preview')
    end
  end
end
