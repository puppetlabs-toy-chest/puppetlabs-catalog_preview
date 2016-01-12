source ENV['GEM_SOURCE'] || 'https://rubygems.org'

def location_for(place, fake_version = nil)
  if place =~ /^(git[:@][^#]*)#(.*)/
    [fake_version, { :git => $1, :branch => $2, :require => false }].compact
  elsif place =~ /^file:\/\/(.*)/
    ['>= 0', { :path => File.expand_path($1), :require => false }]
  else
    [place, { :require => false }]
  end
end

group :system_tests do
  gem 'rake'
  gem 'beaker'
  gem 'beaker-rspec'
end

group :development, :unit_tests do
  gem 'puppetlabs_spec_helper',  :require => false
  gem 'puppet', *location_for(ENV['PUPPET_LOCATION'] || ENV['PUPPET_VERSION'] || '~> 3.8.0')
  gem 'rspec',                   :require => false
  gem 'rspec-core',              :require => false
  gem 'rspec-puppet',            :require => false
  gem 'mocha',                   :require => false
  gem 'json-schema',             :require => false
end

group :development do
  gem 'travis'
  gem 'travis-lint'
  gem 'puppet-blacksmith'
  gem 'guard-rake'
  gem 'rubocop',                 :require => false
end

local_gemfile = "#{__FILE__}.local"
if File.exists? local_gemfile
  puts "using #{local_gemfile}"
  eval(File.read(local_gemfile), binding)
end

user_gemfile = File.join(Dir.home,'.Gemfile')
if File.exists? user_gemfile
  puts "using #{user_gemfile}"
  eval(File.read(user_gemfile), binding)
end
