require 'puppetlabs_spec_helper/module_spec_helper'

def fixture(*path_segments)
  File.join(File.expand_path(File.join(Dir.pwd, 'spec')), 'fixtures', *path_segments)
end

def load_catalog_delta(name)
  JSON.load(File.read(fixture('catalog_deltas', name)))
end

def load_compile_log(name)
  JSON.load(File.read(fixture('compile_logs', name)))
end
