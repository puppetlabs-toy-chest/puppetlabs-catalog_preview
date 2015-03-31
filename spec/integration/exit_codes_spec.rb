require 'spec_helper_integration'

describe 'preview subcommand' do
  it 'should be able to run --help' do
    on default, puppet('preview --help'), {:catch_failures => true} do |r|
      expect(r.stdout).to match(/^puppet-preview\(8\).*SYNOPSIS.*USAGE.*DESCRIPTION.*OPTIONS.*AUTHOR.*COPYRIGHT/m)
      expect(r.stderr).to    be_empty
      expect(r.exit_code).to be_zero
    end
  end

  it 'should be able to run --schema help' do
    on default, puppet('preview --schema help'), {:catch_failures => true} do |r|
      expect(r.stdout).to match(/^Catalog Delta.*Exit Status.*Missing Resources.*Added Resources.*Conflicting Resources/m)
      expect(r.stderr).to    be_empty
      expect(r.exit_code).to be_zero
    end
  end

  # limit puppet apply as much as possible.  create all needed environments here
  testdir_simple            = master.tmpdir('preview')
  testdir_broken_production = master.tmpdir('preview_broken_production')
  testdir_broken_test       = master.tmpdir('preview_broken_test')
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
  parser=future
  ',
  mode => "0640",
}
file { '#{testdir_broken_test}/environments/test/environment.conf':
  ensure => file,
  content => 'environment_timeout = 0
  parser=future
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


  it 'should be able to compare simple catalogs and exit with 0' do
    env_path = File.join(testdir_simple, 'environments')
    on default, puppet("preview --preview_environment test --migrate nonesuch --environmentpath #{env_path}"),
                {:catch_failures => true} do |r|
      expect(r.stderr).not_to    be_empty
      expect(r.exit_code).to be_zero
    end
  end

  it 'should fail to run and exit 1 if no node given' do
    env_path = File.join(testdir_simple, 'environments')
    on default, puppet("preview --preview_environment test --environmentpath #{env_path}"), :acceptable_exit_codes => [1] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 2 when baseline compilation fails' do
    env_path = File.join(testdir_broken_production, 'environments')
    on default, puppet("preview --preview_environment test --migrate nonesuch --environmentpath #{env_path}"),
                :acceptable_exit_codes => [2] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 3 when preview compilation fails' do
    env_path = File.join(testdir_broken_test, 'environments')
    on default, puppet("preview --preview_environment test --migrate nonesuch --environmentpath #{env_path}"),
                :acceptable_exit_codes => [3] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 4 when -assert equal is used and catalogs are not equal' do
    env_path = File.join(testdir_simple, 'environments')
    on default, puppet("preview --preview_environment test --assert equal --migrate nonesuch --environmentpath #{env_path}"),
                :acceptable_exit_codes => [4] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end

  it 'should exit with 5 when -assert compliant is used and preview is not compliant' do
    env_path = File.join(testdir_simple, 'environments')
    on default, puppet("preview --preview_environment test --assert compliant --migrate nonesuch --environmentpath #{env_path}"),
                :acceptable_exit_codes => [5] do |r|
      expect(r.stderr).not_to    be_empty
    end
  end
end
