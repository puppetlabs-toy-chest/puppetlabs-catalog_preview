source 'https://rubygems.org'

def location_for(place, fake_version = nil)
  if place =~ /^(git[:@][^#]*)#(.*)/
    [fake_version, { :git => $1, :branch => $2, :require => false }].compact
  elsif place =~ /^file:\/\/(.*)/
    ['>= 0', { :path => File.expand_path($1), :require => false }]
  else
    [place, { :require => false }]
  end
end


group :test do
  gem 'rake'
  gem 'puppet', *location_for(ENV['PUPPET_LOCATION'] || ENV['PUPPET_VERSION'] || '~> 3.8.0')
  gem 'puppet-lint'
  gem 'puppet-syntax'
  gem 'beaker'
  gem 'beaker-rspec'
end

group :development, :unit_tests do
  gem 'rspec',                   :require => false
  gem 'rspec-core',              :require => false
  gem 'rspec-puppet',            :require => false
  gem 'mocha',                   :require => false
  gem 'rubocop',                 :require => false
  gem 'json-schema',             :require => false
end

group :development, :unit_tests, :test do
  gem 'puppetlabs_spec_helper',  :require => false
end

group :development do
  gem 'travis'
  gem 'travis-lint'
  gem 'vagrant-wrapper'
  gem 'puppet-blacksmith'
  gem 'guard-rake'
end

if File.exists? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end

