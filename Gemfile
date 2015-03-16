source ENV['GEM_SOURCE'] || "https://rubygems.org"

puppetversion = ENV['PUPPET_VERSION']

if puppetversion
  gem 'puppet', puppetversion
else
  gem 'puppet'
end

group :development, :unit_tests do
  gem 'rspec',                   :require => false
  gem 'rspec-core',              :require => false
  gem 'rspec-puppet',            :require => false
  gem 'mocha',                   :require => false
  gem 'puppetlabs_spec_helper',  :require => false
  gem 'rubocop',                 :require => false
end

group :system_tests do
  gem 'beaker',        :require => false
  gem 'beaker-rspec',  :require => false
  gem 'serverspec',    :require => false
end
