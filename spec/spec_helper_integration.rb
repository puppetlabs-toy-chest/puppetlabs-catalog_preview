require 'beaker-rspec/spec_helper'
require 'beaker-rspec/helpers/serverspec'

# to run against foss 3.x: set :type foss and something like:
# PUPPET_VER=3.8.1 SERVER_VER=1.1.1 BEAKER_debug=yes BEAKER_setfile=spec/integration/nodesets/redhat-7-x86_64.yaml bundle exec rspec spec/integration/
# to run against foss 4.x: set :type foss and something like:
# BEAKER_debug=yes BEAKER_setfile=spec/integration/nodesets/redhat-7-x86_64.yaml bundle exec rspec spec/integration/
# to run against PE:
# BEAKER_PE_DIR="http://enterprise.delivery.puppetlabs.net/2015.2/preview" BEAKER_debug=yes BEAKER_destroy=no BEAKER_setfile=spec/integration/nodesets/pe/redhat-7-64mda bundle exec rspec spec/integration/

# below methods copy pasted from puppetdb acceptance

def initialize_repo_on_host(host, os)
  case os
  when /(debian|ubuntu)/
    if options[:type] =~ /(aio|foss)/ then
      on host, "curl -O http://apt.puppetlabs.com/puppetlabs-release-pc1-$(lsb_release -sc).deb"
      on host, "dpkg -i puppetlabs-release-pc1-$(lsb_release -sc).deb"
    else
      on host, "curl -O http://apt.puppetlabs.com/puppetlabs-release-$(lsb_release -sc).deb"
      on host, "dpkg -i puppetlabs-release-$(lsb_release -sc).deb"
    end
      on host, "apt-get update"
  when /(redhat|centos|scientific)/
    if options[:type] =~ /(aio|foss)/ then
      /^(el|centos)-(\d+)-(.+)$/.match(host.platform)
      variant = ($1 == 'centos') ? 'el' : $1
      version = $2

      on host, "curl -O http://yum.puppetlabs.com/puppetlabs-release-pc1-#{variant}-#{version}.noarch.rpm"
      on host, "rpm -i puppetlabs-release-pc1-#{variant}-#{version}.noarch.rpm"
    else
      create_remote_file host, '/etc/yum.repos.d/puppetlabs-dependencies.repo', <<-REPO.gsub(' '*8, '')
[puppetlabs-dependencies]
name=Puppet Labs Dependencies - $basearch
baseurl=http://yum.puppetlabs.com/el/$releasever/dependencies/$basearch
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
      REPO

      create_remote_file host, '/etc/yum.repos.d/puppetlabs-products.repo', <<-REPO.gsub(' '*8, '')
[puppetlabs-products]
name=Puppet Labs Products - $basearch
baseurl=http://yum.puppetlabs.com/el/$releasever/products/$basearch
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
      REPO

      create_remote_file host, '/etc/yum.repos.d/epel.repo', <<-REPO
[epel]
name=Extra Packages for Enterprise Linux $releasever - $basearch
baseurl=http://download.fedoraproject.org/pub/epel/$releasever/$basearch
mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=epel-$releasever&arch=$basearch
failovermethod=priority
enabled=1
gpgcheck=0
      REPO
    end
  when /fedora/
    create_remote_file host, '/etc/yum.repos.d/puppetlabs-dependencies.repo', <<-REPO.gsub(' '*8, '')
[puppetlabs-dependencies]
name=Puppet Labs Dependencies - $basearch
baseurl=http://yum.puppetlabs.com/fedora/f$releasever/dependencies/$basearch
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
    REPO

    create_remote_file host, '/etc/yum.repos.d/puppetlabs-products.repo', <<-REPO.gsub(' '*8, '')
[puppetlabs-products]
name=Puppet Labs Products - $basearch
baseurl=http://yum.puppetlabs.com/fedora/f$releasever/products/$basearch
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
    REPO
  else
    raise ArgumentError, "Unsupported OS '#{os}'"
  end
end

# stolen from puppet acceptance
# required because beaker is seriously broken
def install_repos_on(host, project, sha)
  platform = host['platform'].with_version_codename
  tld     = sha == 'nightly' ? 'nightlies.puppetlabs.com' : 'builds.puppetlabs.lan'
  project = sha == 'nightly' ? project + '-latest'        :  project
  sha     = sha == 'nightly' ? nil                        :  sha

  case platform
  when /^(fedora|el|centos)-(\d+)-(.+)$/
    variant = (($1 == 'centos') ? 'el' : $1)
    fedora_prefix = ((variant == 'fedora') ? 'f' : '')
    version = $2
    arch = $3

    repo_filename = "pl-%s%s-%s-%s%s-%s.repo" % [
      project,
      sha ? '-' + sha : '',
      variant,
      fedora_prefix,
      version,
      arch
    ]
    repo_url = "http://%s/%s/%s/repo_configs/rpm/%s" % [tld, project, sha, repo_filename]

    on host, "curl -o /etc/yum.repos.d/#{repo_filename} #{repo_url}"
  when /^(debian|ubuntu)-([^-]+)-(.+)$/
    variant = $1
    version = $2
    arch = $3

    list_filename = "pl-%s%s-%s.list" % [
      project,
      sha ? '-' + sha : '',
      version
    ]
    list_url = "http://%s/%s/%s/repo_configs/deb/%s" % [tld, project, sha, list_filename]

    on host, "curl -o /etc/apt/sources.list.d/#{list_filename} #{list_url}"
    on host, "apt-get update"
  else
    host.logger.notify("No repository installation step for #{platform} yet...")
  end
end

# TODO: remove this once beaker has it merged in
def stop_puppetserver(host)
  if options[:type] =~ /(foss|git)/
    on host, 'service puppetserver stop'
  else
    on host, 'service pe-puppetserver stop'
  end
end

def start_puppetserver(host)
  # TODO: reconcile the various sources of options
  if options[:type] =~ /(foss|git)/
    on host, 'service puppetserver start'
  else
    on host, puppet('resource service pe-puppetserver ensure=running')
  end
    opts = {
      :desired_exit_codes => [35, 60],
      :max_retries => 60,
      :retry_interval => 1
    }
    url = 'https://localhost:8140'
    retry_on(host, "curl -m 1 #{url}", opts)
end

# TODO: remove this once beaker has it merged in
def start_puppetdb(host, version)
  test_url = version == '2.3.5' ? '/v4/version' : '/pdb/meta/v1/version'

  step "Starting PuppetDB" do
    if host.is_pe?
      on host, "service pe-puppetdb start"
    else
      on host, "service puppetdb start"
    end
    sleep_until_started(host, test_url)
  end
end

# Sleep until PuppetDB is completely started
#
# @param host Hostname to test for PuppetDB availability
# @return [void]
# @api public
def sleep_until_started(host, test_url="/pdb/meta/v1/version")
  # Hit an actual endpoint to ensure PuppetDB is up and not just the webserver.
  # Retry until an HTTP response code of 200 is received.
  desired_exit_code = 0
  max_retries = 120
  retry_interval = 1
  curl_with_retries("start puppetdb", host,
                    "-s -w '%{http_code}' http://localhost:8080#{test_url} -o /dev/null",
                    desired_exit_code, max_retries, retry_interval, /200/)
  curl_with_retries("start puppetdb (ssl)", host,
                    "https://#{host.node_name}:8081#{test_url}", [35, 60])
rescue RuntimeError => e
  display_last_logs(host)
  raise
end

def get_package_version(host, version = nil)
  # version can look like:
  #   3.0.0
  #   3.0.0.SNAPSHOT.2015.07.08T0945

  # Rewrite version if its a SNAPSHOT in rc form
  if version.include?("SNAPSHOT")
    version = version.sub(/^(.*)\.(SNAPSHOT\..*)$/, "\\1-0.1\\2")
  else
    version = version + "-1"
  end

  ## These 'platform' values come from the acceptance config files, so
  ## we're relying entirely on naming conventions here.  Would be nicer
  ## to do this using lsb_release or something, but...
  if host['platform'].include?('el-5')
    "#{version}.el5"
  elsif host['platform'].include?('el-6')
    "#{version}.el6"
  elsif host['platform'].include?('el-7')
    "#{version}.el7"
  elsif host['platform'].include?('fedora')
    version_tag = host['platform'].match(/^fedora-(\d+)/)[1]
    "#{version}.fc#{version_tag}"
  elsif host['platform'].include?('ubuntu') or host['platform'].include?('debian')
    "#{version}puppetlabs1"
  else
    raise ArgumentError, "Unsupported platform: '#{host['platform']}'"
  end
end

def install_puppetdb(host, version=nil)
  test_url = version == '2.3.5' ? '/v4/version' : '/pdb/meta/v1/version'

  if version == '2.3.5'
    db = 'embedded'
    puppetdb_manifest = <<-EOS
    class { 'puppetdb::globals':
      version => '#{get_package_version(host, version)}',
    }
    class { 'puppetdb::server':
      database               => '#{db}',
      manage_firewall        => false,
    }
    EOS
  else
    puppetdb_manifest = <<-EOS
    class { 'puppetdb': }
    EOS
  end
  apply_manifest_on(host, puppetdb_manifest)
  sleep_until_started(host, test_url)
end

# Keep curling until the required condition is met
#
# Condition can be a desired_exit code, and/or expected_output, and it will
# keep executing the curl command until one of these conditions are met
# or the max_retries is reached.
#
# @param desc [String] descriptive name for this cycling
# @param host [String] host to execute retry on
# @param curl_args [String] the curl_args to use for testing
# @param desired_exit_codes [Number,Array<Number>] a desired exit code, or array of exist codes
# @param max_retries [Number] maximum number of retries before failing
# @param retry_interval [Number] time in secs to wait before next try
# @param expected_output [Regexp] a regexp to use for matching the output
# @return [void]
def curl_with_retries(desc, host, curl_args, desired_exit_codes, max_retries = 60, retry_interval = 1, expected_output = /.*/)
  command = "curl --tlsv1 #{curl_args}"
  log_prefix = host.log_prefix
  logger.debug "\n#{log_prefix} #{Time.new.strftime('%H:%M:%S')}$ #{command}"
  logger.debug "  Trying command #{max_retries} times."
  logger.debug ".", add_newline=false

  desired_exit_codes = [desired_exit_codes].flatten
  result = on host, command, :acceptable_exit_codes => (0...127), :silent => true
  num_retries = 0
  until desired_exit_codes.include?(exit_code) and (result.stdout =~ expected_output)
    sleep retry_interval
    result = on host, command, :acceptable_exit_codes => (0...127), :silent => true
    num_retries += 1
    logger.debug ".", add_newline=false
    if (num_retries > max_retries)
      logger.debug "  Command \`#{command}\` failed."
      fail("Command \`#{command}\` failed. Unable to #{desc}.")
    end
  end
  logger.debug "\n#{log_prefix} #{Time.new.strftime('%H:%M:%S')}$ #{command} ostensibly successful."
end

def databases
  extend Beaker::DSL::Roles
  hosts_as(:database).sort_by {|db| db.to_str}
end

def database
  # primary database must be numbered lowest
  databases[0]
end

RSpec.configure do |c|
  if ENV['RS_PROVISION'] == 'no' or ENV['BEAKER_provision'] == 'no'
    puppet_version = on(master, 'puppet --version').stdout.chomp
    puppetdb_ver = puppet_version =~ /3\./ ? '2.3.5' : 'latest'
  else
    if default[:type] =~ /(foss|git)/
      puppet_ver   = ENV['PUPPET_VER'] || ENV['SHA'] || 'nightly'
      server_ver   = ENV['SERVER_VER']               || 'nightly'
      step 'install foss puppet'
      if puppet_ver =~ /3\./
        install_puppet_on(master, {:version => puppet_ver})
      else
        install_repos_on(master, 'puppet-agent', puppet_ver)
        master.add_env_var('PATH', '/opt/puppetlabs/puppet/bin/')
      end
      install_repos_on(master, 'puppetserver', server_ver)
      install_package(master,  'puppetserver')
    else
      step 'install PE'
      install_pe
    end

    on master, puppet('config set autosign          true --section master')
    on master, puppet('config set trusted_node_data true --section main')
    puppet_version = on(master, 'puppet --version').stdout.chomp
    puppetdb_ver = puppet_version =~ /3\./ ? '2.3.5' : 'latest'

    if default[:type] =~ /(foss|git)/
      step 'install/configure foss puppetdb'
      start_puppetserver(master)

      initialize_repo_on_host(master, master[:template])
      on master, puppet('module install puppetlabs/puppetdb')
      on master, puppet("agent -t --server #{master.hostname}")
      if puppetdb_ver == 'latest'
        puppetdb_terminus_ver = puppetdb_ver
      else
        puppetdb_terminus_ver = master.platform =~ /ubuntu/ ? puppetdb_ver + '-1puppetlabs1' : puppetdb_ver
      end
      install_puppetdb(master, puppetdb_ver)
      if puppet_version =~ /3\./
        on master, puppet("resource package puppetdb-terminus ensure='#{puppetdb_terminus_ver}'")
      else
        on master, puppet("resource package puppetdb-termini ensure='#{puppetdb_terminus_ver}'")
      end
      puppet_confdir = on(master, puppet('master --configprint confdir')).stdout.chomp
      puppetdb_port  = '8081'
      if puppet_version =~ /3\./
        create_remote_file(master, "#{puppet_confdir}/puppetdb.conf", <<HERE
[main]
server = #{master.hostname}
port = #{puppetdb_port}
HERE
                        )
      else
        create_remote_file(master, "#{puppet_confdir}/puppetdb.conf", <<HERE
[main]
server_urls = https://#{master.hostname}:#{puppetdb_port}
HERE
                        )
      end
      stop_puppetserver(master)
      on master, puppet('config set storeconfigs         true --section master')
      on master, puppet('config set storeconfigs_backend puppetdb --section master')
      route_file = on(master, puppet('master --configprint route_file')).stdout.chomp
      create_remote_file(master, route_file, <<HERE
---
master:
  facts:
    terminus: puppetdb
    cache: yaml
HERE
                        )
      on master, "chown -R puppet:puppet #{puppet_confdir}"
      start_puppetdb(master, puppetdb_ver)
      start_puppetserver(master)

      on master, puppet("agent -t --server #{master.hostname}")
    else
      step 'install/configure PE puppetdb'
      on master, puppet('resource service pe-puppetserver ensure=running')
      opts = {
        :desired_exit_codes => [35, 60],
        :max_retries => 60,
        :retry_interval => 1
      }
      url = 'https://localhost:8140'
      retry_on(master, "curl -m 1 #{url}", opts)
      on master, puppet('agent --disable')
    end
    on master, puppet('resource user previewser ensure=present managehome=true')
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
    module_path = master.puppet['modulepath'].split(':')
    target_module_path = module_path.length > 2 ? module_path[2] : module_path[0]
    if ENV['SPEC_FORGE']
      puppet_module_install(:source => proj_root, :module_name => 'preview', :forge_host => ENV['SPEC_FORGE'])
    else
      puppet_module_install(:source => proj_root, :module_name => 'preview', :target_module_path => target_module_path)
    end
    # ensure non-root users can access the module in PE 3x:
    on master, "mkdir -p /usr/share/puppet/modules && ln -s #{target_module_path}/preview /usr/share/puppet/modules", :accept_all_exit_codes => true

    step 'add node names to puppetdb that are used in the tests' do
      node_names_file = ['file_node1', 'file_node2']
      node_names_cli  = ['nonesuch', 'andanother']
      node_names_all  = node_names_cli + node_names_file
      curl_headers = "--silent --show-error -H 'Content-Type:application/json'   -H 'Accept:application/json'"

      ['production','test'].each do |environment|
        node_names_all.each do |node_name|
          if puppetdb_ver == 'latest'
            curl_payload = "{\"command\":\"replace facts\",\"version\":4,\"payload\":{\"certname\":\"#{node_name}\",\"environment\":\"#{environment}\",\"values\":{\"osfamily\":\"myvalue\"},\"producer_timestamp\":\"2015-01-01\"}}"
            on master, "curl -X POST #{curl_headers} -d '#{curl_payload}' 'http://localhost:8080/pdb/cmd/v1'"
          else
            curl_payload = "{\"command\":\"replace facts\",\"version\":3,\"payload\":{\"name\":\"#{node_name}\",\"environment\":\"#{environment}\",\"values\":{\"osfamily\":\"myvalue\"},\"producer-timestamp\":\"2015-01-01\"}}"
            on master, "curl -X POST #{curl_headers} -d '#{curl_payload}' 'http://localhost:8080/v3/commands'"
          end
        end
      end
    end

  end
end
