source ENV['GEM_SOURCE'] || 'https://rubygems.org'
# attempt to resolve gem dependencies by ruby version
ruby RUBY_VERSION

def location_for(place, fake_version = nil)
  if place =~ /^(git[:@][^#]*)#(.*)/
    [fake_version, { :git => $1, :branch => $2, :require => false }].compact
  elsif place =~ /^file:\/\/(.*)/
    ['>= 0', { :path => File.expand_path($1), :require => false }]
  else
    [place, { :require => false }]
  end
end

current_ruby_version = Gem::Version.new(RUBY_VERSION)
ruby_1_9_3 = Gem::Version.new('1.9.3')
ruby_2_1_5 = Gem::Version.new('2.1.5')
ruby_2_1_8 = Gem::Version.new('2.1.8')

group :system_tests do
  gem 'rake',                    '~> 0'
  gem 'beaker-rspec',            *location_for(ENV['BEAKER_RSPEC_VERSION'] || '<  6.0') if current_ruby_version <  ruby_2_1_8
  gem 'beaker-rspec',            *location_for(ENV['BEAKER_RSPEC_VERSION'] || '~> 6.0') if current_ruby_version >= ruby_2_1_8
  # even though we define ruby version above, we need to pin some gems
  #   probably due to gems without `required_ruby_version` defined
  gem 'beaker',                  *location_for(ENV['BEAKER_VERSION'] || '<  3.16') if current_ruby_version <  ruby_2_1_8
  gem 'beaker',                  *location_for(ENV['BEAKER_VERSION'] || '~> 3.0')  if current_ruby_version >= ruby_2_1_8
  gem 'beaker-pe',               *location_for(ENV['BEAKER_PE_VERSION'] || '~> 1.1')
  gem 'beaker-hostgenerator',    *location_for(ENV['BEAKER_HOSTGENERATOR_VERSION'] || '~> 0')
  gem "beaker-abs",              *location_for(ENV['BEAKER_ABS_VERSION'] || '~> 0.2')
end

group :development, :unit_tests do
  gem 'puppetlabs_spec_helper',  :require => false
  gem 'puppet',                  *location_for(ENV['PUPPET_LOCATION'] || ENV['PUPPET_VERSION'] || '~> 3.8.0')
  # puppet depends on hiera, which has an unbound dependency on json_pure
  gem 'json_pure',               '< 2.0.2' if current_ruby_version <  ruby_2_1_5 # puppet deps or transitive deps
  gem 'rspec',                   :require => false
  gem 'rspec-core',              :require => false
  gem 'rspec-puppet',            :require => false
  gem 'mocha',                   :require => false
  gem 'json-schema',             :require => false
end

group :development do
  gem 'travis'                   if current_ruby_version >= ruby_1_9_3
  gem 'travis-lint'              if current_ruby_version >= ruby_1_9_3
  gem 'puppet-blacksmith'        if current_ruby_version >= ruby_1_9_3
  gem 'guard-rake'               if current_ruby_version >= ruby_1_9_3
  gem 'listen',                   '~> 3.0.0'
  gem 'rubocop'                  if current_ruby_version >= ruby_1_9_3
  if current_ruby_version >= Gem::Version.new('2.3.0')
    gem 'rubocop-rspec',         '~> 1.6'
    gem 'safe_yaml',             '~> 1.0.4'
  end
end

local_gemfile = "#{__FILE__}.local"
if File.exists? local_gemfile
  eval(File.read(local_gemfile), binding)
end

user_gemfile = File.join(File.expand_path("~"),'.Gemfile')
if File.exists? user_gemfile
  eval(File.read(user_gemfile), binding)
end
