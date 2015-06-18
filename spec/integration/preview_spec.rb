require 'spec_helper_integration'
require 'json'

describe 'preview subcommand' do
  it 'should be able to run --help' do
    on master, puppet('preview --help'), {:catch_failures => true} do |r|
      expect(r.stdout).to match(/^puppet-preview\(8\).*SYNOPSIS.*USAGE.*DESCRIPTION.*OPTIONS.*COPYRIGHT/m)
      expect(r.exit_code).to be_zero
    end
  end

  it 'should be able to run --schema help' do
    on master, puppet('preview --schema help'), {:catch_failures => true} do |r|
      expect(r.stdout).to match(/^Catalog Delta.*Exit Status.*Missing Resources.*Added Resources.*Conflicting Resources/m)
      expect(r.exit_code).to be_zero
    end
  end

  # limit puppet apply as much as possible.  create all needed environments here
  testdir_simple            = master.tmpdir('preview')
  testdir_broken_production = master.tmpdir('preview_broken_production')
  testdir_broken_test       = master.tmpdir('preview_broken_test')
  # Do not use parser=future in environment configurations for version >= 4.0.0 since it has been removed
  puppet_version            =  on(master, 'puppet --version').stdout.chomp
  use_future_parser         =  puppet_version =~ /^3\./ ? 'parser=future' : ''

  pp = <<-EOS
File {
  ensure => directory,
  mode => "0750",
  owner => #{master.puppet['user']},
  group => #{master.puppet['group']},
}
file {
  '#{testdir_simple}':;
  '#{testdir_simple}/environments':;
  '#{testdir_simple}/environments/production':;
  '#{testdir_simple}/environments/production/manifests':;
  '#{testdir_simple}/environments/test':;
  '#{testdir_simple}/environments/test/manifests':;
  '#{testdir_broken_production}':;
  '#{testdir_broken_production}/environments':;
  '#{testdir_broken_production}/environments/production':;
  '#{testdir_broken_production}/environments/production/manifests':;
  '#{testdir_broken_production}/environments/test':;
  '#{testdir_broken_production}/environments/test/manifests':;
  '#{testdir_broken_test}':;
  '#{testdir_broken_test}/environments':;
  '#{testdir_broken_test}/environments/production':;
  '#{testdir_broken_test}/environments/production/manifests':;
  '#{testdir_broken_test}/environments/test':;
  '#{testdir_broken_test}/environments/test/manifests':;
}

file { '#{testdir_simple}/environments/test/environment.conf':
  ensure => file,
  content => 'environment_timeout = 0
  #{use_future_parser}
  ',
  mode => "0640",
}
file { '#{testdir_broken_test}/environments/test/environment.conf':
  ensure => file,
  content => 'environment_timeout = 0
  #{use_future_parser}
  ',
  mode => "0640",
}

file { '#{testdir_simple}/environments/production/manifests/init.pp':
  ensure => file,
  content => '
    notify{"yay we be the same":}
  ',
  mode => "0640",
}

file { '#{testdir_simple}/environments/test/manifests/init.pp':
  ensure => file,
  content => '
    notify{"yay we be the same, but different":}
  ',
  mode => "0640",
}

file { '#{testdir_broken_production}/environments/production/manifests/init.pp':
  ensure => file,
  content => '
    # this should fail compilation in any parser
    name = notify{"yay we be the same":}
  ',
  mode => "0640",
}

file { '#{testdir_broken_test}/environments/test/manifests/init.pp':
  ensure => file,
  content => '
    # this should fail compilation in any parser
    name = notify{"yay we be the same":}
  ',
  mode => "0640",
}
EOS

  apply_manifest(pp, :catch_failures => true)
  node_name = 'nonesuch'

  it 'should be able to compare simple catalogs and exit with 0 and produce json logfiles' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path}"),
                {:catch_failures => true} do |r|
      expect(r.exit_code).to be_zero

      vardir = on(master, puppet('master --configprint vardir')).stdout.strip
      logfile_extension  = '.json'
      # create a string to send to on master that tests all the files at once
      test_files_short   = ['baseline_catalog','baseline_log','catalog_diff','preview_catalog','preview_log']
      # make the filenames fully qualified and with extensions
      test_files_long    = test_files_short.map { |logfile| File.join(vardir,'preview',node_name,logfile + logfile_extension) }
      # add the test to each filename
      test_strings       = test_files_long.map { |logfile| "test -s #{logfile}" }
      # join the array with && to test each file in series
      test_files_command = test_strings.join(' && ')
      on master, test_files_command
      # validate if json
      test_files_long.each do |file|
        on master, "cat #{file}" do
          JSON.parse(stdout)
        end
      end
    end
  end

  # TODO: TESTS TO ADD
  # TODO: same as for one node, but for multiple nodes (just given on the command line)
  # TODO: same as for multiple nodes but for nodes from a file (--nodes filename)
  # TODO: same as for multiple nodes but for nodes from stdin (--nodes -)
  # TODO: same as for multiple nodes mixing explicitly given nodes with those given with --nodes (unique set)

  it 'should output valid json from --view diff' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --view diff"),
                {:catch_failures => true} do |r|
      expect(r.exit_code).to be_zero
      JSON.parse(r.stdout)
    end
  end

  it 'should output valid json from --view overview_json' do
    env_path = File.join(testdir_simple, 'environments')
    on(master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --view overview_json"),
      {:catch_failures => true, :acceptable_exit_codes => [0]}) { |r| JSON.parse(r.stdout) }
  end

  it 'should output valid json from --view baseline_log' do
    env_path = File.join(testdir_broken_production, 'environments')
    on(master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path}"),
      :acceptable_exit_codes => [2]) { |r| }
    on(master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --last --view baseline_log"),
      {:catch_failures => true, :acceptable_exit_codes => [0]}) { |r| JSON.parse(r.stdout) }
  end

  it 'should output valid json from --view preview_log' do
    env_path = File.join(testdir_broken_test, 'environments')
    on(master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path}"),
      :acceptable_exit_codes => [3]) { |r| }
    on(master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --last --view preview_log"),
      {:catch_failures => true, :acceptable_exit_codes => [0]}) { |r| JSON.parse(r.stdout) }
  end

  it 'should --view diff_nodes' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --view diff_nodes"),
      :acceptable_exit_codes => [0] do |r|
      expect(r.stderr).to be_empty
      expect(r.stdout).to match(/#{node_name}/)
    end
  end

  it 'should output nothing from --view failed_nodes with no failed nodes' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --view failed_nodes"),
      {:acceptable_exit_codes => [0]} do |r|
      expect(r.exit_code).to be_zero
      expect(r.stderr).to be_empty
      expect(r.stdout).to be_empty
    end
  end

  it 'should show the error and the failed nodes with --view failed_nodes' do
    env_path = File.join(testdir_broken_test, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path} --view failed_nodes"),
      :acceptable_exit_codes => [3] do |r|
      expect(r.stderr).to match(/Illegal attempt to assign to 'a Name'/)
      expect(r.stdout).to match(/#{node_name}/)
    end
  end

  it 'should fail to run and exit 1 if no node given' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test --environmentpath #{env_path}"), :acceptable_exit_codes => [1] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 2 when baseline compilation fails' do
    env_path = File.join(testdir_broken_production, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path}"),
                :acceptable_exit_codes => [2] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 3 when preview compilation fails' do
    env_path = File.join(testdir_broken_test, 'environments')
    on master, puppet("preview --preview_environment test #{node_name} --environmentpath #{env_path}"),
                :acceptable_exit_codes => [3] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 4 when -assert equal is used and catalogs are not equal' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test --assert equal --migrate 3.8/4.0 #{node_name} --environmentpath #{env_path}"),
                :acceptable_exit_codes => [4]
  end

  it 'should exit with 5 when -assert compliant is used and preview is not compliant' do
    env_path = File.join(testdir_simple, 'environments')
    on master, puppet("preview --preview_environment test --assert compliant --migrate 3.8/4.0 nonesuch --environmentpath #{env_path}"),
                :acceptable_exit_codes => [5]
  end

  if puppet_version =~ /^3\./ # constrained to >= 3.8.0 in dependencies

    it 'accepts --migrate 3.8/4.0' do
      env_path = File.join(testdir_simple, 'environments')
      on master, puppet("preview --preview_environment test --migrate 3.8/4.0 #{node_name} --environmentpath #{env_path}"),
                  { :catch_failures => true } do |r|
        expect(r.exit_code).to be_zero
      end
    end
  else

    it 'errors with exit 1 on --migrate 3.8/4.0' do
      env_path = File.join(testdir_simple, 'environments')
      on master, puppet("preview --preview_environment test --migrate 3.8/4.0 #{node_name} --environmentpath #{env_path}"),
                  :acceptable_exit_codes => [1]
    end
  end

end
