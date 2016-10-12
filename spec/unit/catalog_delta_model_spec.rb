require 'spec_helper'
require 'puppet'
require 'puppet/pops'
require 'puppet_x/puppetlabs/preview'
require 'json'
require 'json-schema'

module PuppetX::Puppetlabs::Migration::CatalogDeltaModel
describe 'CatalogDelta' do

  let(:baseline_hash) do
    {
      'tags' => ['settings'],
      'name' => 'test.example.com',
      'version' => 1427456346,
      'environment' => 'production',
      'resources' => [
        {
          'type' => 'File',
          'title' => '/tmp/footest',
          'tags' => ['file', 'class'],
          'file' => '/etc/puppet/environments/production/manifests/site.pp',
          'line' => 1,
          'exported' => false,
          'parameters' => {
            'ensure' => 'present',
            'mode' => '0600',
          }
        },
        {
          'type' => 'File',
          'title' => '/tmp/bartest',
          'tags' => ['file', 'class'],
          'file' => '/etc/puppet/environments/production/manifests/site.pp',
          'line' => 2,
          'exported' => false,
          'parameters' => {
            'ensure' => 'present',
            'mode' => '0600',
            'array' => %w(a b c c),
            'before' => %w(a b c c),
            'after' => %w(a b c),
            'subscribe' => %w(a b c),
            'notify' => %w(a b c),
            'tags' => %w(a b c),
            'hash' => { 'a' => 'A', 'b' => [1,2]},
            'mol' => '42'
          }
        },
        {
          'type' => 'File',
          'title' => '/etc/puppetlabs/console-services/conf.d/console_secret_key.conf',
          'line' => 1,
          'exported' => false,
          'parameters' => {
            'content' => 'secret',
          }
        },
        {
          'type' => 'File',
          'title' => '/tmp/fumtest',
          'tags' => ['file', 'class'],
          'file' => '/etc/puppet/environments/production/manifests/site.pp',
          'line' => 3,
          'exported' => false,
          'parameters' => {
            'before' => 'a',
            'after' => ['a']
          }
        }
      ],
      'edges' => [
        {
          'source' => 'Class[main]',
          'target' => 'File[/tmp/fumtest]'
        }
      ]
    }
  end

  def deep_clone(x)
    case x
    when Array
      x.map {|e| deep_clone(e)}
    when Hash
      c = {}
      x.each_pair {|k,v| c[k] = deep_clone(v)}
      c
    else
      x
    end
  end

  let(:preview_hash) { deep_clone(baseline_hash)}

  let(:timestamp) { Time.now.iso8601(9) }
  let(:options) { {
    :node => 'test.example.com',
    :baseline_catalog => '/path/to/baseline/catalog',
    :preview_catalog => '/path/to/preview/catalog',
    :migration_checker => false,
    :diff_string_numeric => false,
    :skip_tags => true,
    :verbose_diff => false
  } }

  let(:schema_dir) { 'lib/puppet_x/puppetlabs/preview/api/schemas' }
  let(:json_meta_schema) { JSON.parse(File.read(File.join(schema_dir, 'json-meta-schema.json'))) }
  let(:catalog_delta_schema) { JSON.parse(File.read(File.join(schema_dir, 'catalog-delta.json'))) }
  let(:excludes_schema) { JSON.parse(File.read(File.join(schema_dir, 'excludes.json'))) }

  it 'has a valid JSON schema' do
    JSON::Validator.validate!(json_meta_schema, catalog_delta_schema)
  end

  it 'reports that tags are skipped' do
    delta = CatalogDelta.new(baseline_hash, preview_hash, options, timestamp)
    expect(delta.tags_ignored?).to be(true)
  end

  it 'reports version_equal' do
    delta = CatalogDelta.new(baseline_hash, preview_hash, options, timestamp)
    expect(delta.version_equal?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))

    delta = CatalogDelta.new(baseline_hash, preview_hash.merge!('version' => 1427456348), options, timestamp)
    expect(delta.version_equal?).to be(false)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'version inequality has no impact on preview equality or compliance' do
    delta = CatalogDelta.new(baseline_hash, preview_hash.merge!('version' => 1427456348), options, timestamp)
    expect(delta.preview_equal?).to be(true)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports missing resource' do
    pv = preview_hash
    pv['resources'].pop
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.missing_resource_count).to eq(1)
    expect(delta.missing_resources).to contain_exactly(be_a(Resource))
    expect(delta.missing_resources[0].type).to eq('File')
    expect(delta.missing_resources[0].title).to eq('/tmp/fumtest')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports added resource' do
    pv = preview_hash
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.added_resource_count).to eq(1)
    expect(delta.added_resources).to contain_exactly(be_a(Resource))
    expect(delta.added_resources[0].type).to eq('File')
    expect(delta.added_resources[0].title).to eq('/tmp/baztest')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports conflicting resource when preview is missing an attribute' do
    pv = preview_hash
    pv['resources'][0] = {
        'type' => 'File',
        'title' => '/tmp/footest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 1,
        'exported' => false,
        'parameters' => {
        }
      }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/footest')
    expect(conflict.added_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(0)
    expect(conflict.missing_attribute_count).to eq(2)
    expect(conflict.missing_attributes).to contain_exactly(be_a(Attribute), be_a(Attribute))
    attr = conflict.missing_attributes[0]
    expect(attr.name).to eq('ensure')
    attr = conflict.missing_attributes[1]
    expect(attr.name).to eq('mode')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports conflicting resource when preview is adding an attribute' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'present',
        'mode' => '0600',
        'content' => 'hello'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/footest')
    expect(conflict.missing_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(0)
    expect(conflict.added_attribute_count).to eq(1)
    expect(conflict.added_attributes).to contain_exactly(be_a(Attribute))
    attr = conflict.added_attributes[0]
    expect(attr.name).to eq('content')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports conflicting resource when there is a conflicting attribute' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'absent',
        'mode' => '0600'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/footest')
    expect(conflict.missing_attribute_count).to eq(0)
    expect(conflict.added_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(1)
    expect(conflict.conflicting_attributes).to contain_exactly(be_a(AttributeConflict))
    attr = conflict.conflicting_attributes[0]
    expect(attr.name).to eq('ensure')
    expect(attr.baseline_value).to eq('present')
    expect(attr.preview_value).to eq('absent')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'ignores excluded attribute removals' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'mode' => '0600'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, [ Exclude.new('file', '/tmp/footest', ['ensure']) ])
    expect(delta.conflicting_resource_count).to eq(0)
  end

  it 'ignores excluded attribute additions' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'present',
        'mode' => '0600',
        'content' => 'hello'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, [ Exclude.new('file', '/tmp/footest', ['content']) ])
    expect(delta.conflicting_resource_count).to eq(0)
  end

  it 'ignores excluded attribute conflicts' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'absent',
        'mode' => '0600'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, [ Exclude.new('file', '/tmp/footest', ['ensure']) ])
    expect(delta.conflicting_resource_count).to eq(0)
  end

  it 'ignores attributes excluded by default' do
    pv = preview_hash
    pv['resources'][2] = {
      'type' => 'File',
      'title' => '/etc/puppetlabs/console-services/conf.d/console_secret_key.conf',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'content' => 'secret2',
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.conflicting_resource_count).to eq(0)
  end

  it 'ignores excluded resource removals' do
    pv = preview_hash
    pv['resources'].pop
    pv['edges'].pop
    excludes_file = fixture('excludes', 'exclude_all_file.json')
    excludes = Exclude.parse_file(excludes_file)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, excludes)
    expect(delta.missing_resource_count).to eq(0)
    expect(delta.preview_equal?).to be(true)
  end

  it 'ignores excluded resource additions' do
    pv = preview_hash
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'File[/tmp/baztest]'
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, [ Exclude.new('file', nil, nil) ])
    expect(delta.added_resource_count).to eq(0)
    expect(delta.preview_equal?).to be(true)
  end

  it 'ignores excluded resource conflicts' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'absent',
        'mode' => '0600'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp, [ Exclude.new('file', nil, nil) ])
    expect(delta.conflicting_resource_count).to eq(0)
    expect(delta.preview_equal?).to be(true)
  end

  it 'reports missing edges' do
    pv = preview_hash
    pv['edges'].pop
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.missing_edge_count).to eq(1)
    expect(delta.missing_edges).to contain_exactly(be_a(Edge))
    edge = delta.missing_edges[0]
    expect(edge.source).to eq('Class[main]')
    expect(edge.target).to eq('File[/tmp/fumtest]')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'reports added edges' do
    pv = preview_hash
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'Notify[roses are red]'
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.baseline_edge_count).to eq(1)
    expect(delta.preview_edge_count).to eq(2)
    expect(delta.added_edge_count).to eq(1)
    expect(delta.added_edges).to contain_exactly(be_a(Edge))
    edge = delta.added_edges[0]
    expect(edge.source).to eq('Class[main]')
    expect(edge.target).to eq('Notify[roses are red]')
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers added resources to be different but compliant' do
    pv = preview_hash
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers missing resources to be different and not compliant' do
    pv = preview_hash
    pv['resources'].pop
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers added edges to be different but compliant' do
    pv = preview_hash
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'Notify[roses are red]'
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers missing edges to be different and not compliant' do
    pv = preview_hash
    pv['edges'].pop
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers adding attributes to be different but compliant' do
    pv = preview_hash
    pv['resources'][0] = {
      'type' => 'File',
      'title' => '/tmp/footest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 1,
      'exported' => false,
      'parameters' => {
        'ensure' => 'present',
        'mode' => '0600',
        'content' => 'hello'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers adding a value to an array attribute to be different but compliant' do
    pv = preview_hash
    pv['resources'][1]['parameters']['array'].push(4)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers adding a value to a hash attribute to be different but compliant' do
    pv = preview_hash
    pv['resources'][1]['parameters']['hash']['c'] = 3
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers changing an element of a hash attribute to a compliant element to be different but compliant' do
    pv = preview_hash
    pv['resources'][1]['parameters']['hash']['b']= [2,1]
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers array attributes with the same content but differnet order to be different but compliant' do
    pv = preview_hash
    pv['resources'][1]['parameters']['array'] = %w(c b a c)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers array attributes named before, after, subscribe, notify, or tags to use Set semantics' do
    pv = preview_hash
    params = pv['resources'][1]['parameters']
    %w(before after subscribe notify tags).each do |attr|
      params[attr] = %w(c b a c a)
      delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
      expect(delta.preview_equal?).to be(true)
      JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
    end
  end

  it 'converts the value of attributes that use Set semantics into an array' do
    pv = preview_hash
    pv['resources'][1]['parameters']['before'] = %w(c b)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    crs = delta.conflicting_resources
    expect(crs.size).to eq(1)
    cas = crs[0].conflicting_attributes
    expect(cas.size).to eq(1)
    ca = cas[0]
    expect(ca.baseline_value).to be_an(Array)
    expect(ca.preview_value).to be_an(Array)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'allows variables that have Set semantics to be strings' do
    pv = preview_hash
    pv['resources'][3]['parameters'] =  {
        'before' => ['a'],
        'after' => 'a'
    }
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(true)
    expect(delta.preview_compliant?).to be(true)
  end

  it 'considers array attributes not named before, after, subscribe, notify, or tags to use List semantics' do
    pv = preview_hash
    pv['resources'][1]['parameters']['array'] = %w(c b a)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'considers array attributes with less content to be non compliant' do
    pv = preview_hash
    pv['resources'][1]['parameters']['array'] = %w(c b)
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'does not include resource attributes in delta unless verbose is given' do
    pv = preview_hash
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    expect(delta.added_resources[0].attributes).to be_nil
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))

    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:verbose_diff => true), timestamp)
    expect(delta.added_resources[0].attributes).to be_a(Array)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'ignores or detects string/int differences depending on migration_checker and diff_string_numeric flag' do
    pv = preview_hash
    pv['resources'][1]['parameters']['mol'] = 42
    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => true, :diff_string_numeric => false), timestamp)
    expect(delta.preview_equal?).to be(true)
    expect(delta.preview_compliant?).to be(true)
    expect(delta.string_numeric_diff_ignored?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))

    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => true, :diff_string_numeric => true), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.string_numeric_diff_ignored?).to be(false)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/bartest')
    expect(conflict.missing_attribute_count).to eq(0)
    expect(conflict.added_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(1)
    expect(conflict.conflicting_attributes).to contain_exactly(be_a(AttributeConflict))
    attr = conflict.conflicting_attributes[0]
    expect(attr.name).to eq('mol')
    expect(attr.baseline_value).to eq('42')
    expect(attr.preview_value).to eq(42)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))

    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => false, :diff_string_numeric => true), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.string_numeric_diff_ignored?).to be(false)

    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => false, :diff_string_numeric => false), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.string_numeric_diff_ignored?).to be(false)
  end

  it 'ignores array[value]/value differences when --migration MIGRATION is used with --no-diff-array-value' do
    pv = preview_hash
    pv['resources'][1]['parameters']['mol'] = ['42']
    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => true, :diff_array_value => false), timestamp)
    expect(delta.preview_equal?).to be(true)
    expect(delta.preview_compliant?).to be(true)
    expect(delta.array_value_diff_ignored?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'ignores both string/int differences and array[value]/value differences when --migration MIGRATION is used with --no-diff-array-value' do
    pv = preview_hash
    pv['resources'][1]['parameters']['mol'] = [42]
    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => true, :diff_array_value => false), timestamp)
    expect(delta.preview_equal?).to be(true)
    expect(delta.preview_compliant?).to be(true)
    expect(delta.array_value_diff_ignored?).to be(true)
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'detects array[value]/value differences when --migration MIGRATION is used with --diff-array-value' do
    pv = preview_hash
    pv['resources'][1]['parameters']['mol'] = ['42']
    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => true, :diff_array_value => true), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.array_value_diff_ignored?).to be(false)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/bartest')
    expect(conflict.missing_attribute_count).to eq(0)
    expect(conflict.added_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(1)
    expect(conflict.conflicting_attributes).to contain_exactly(be_a(AttributeConflict))
    attr = conflict.conflicting_attributes[0]
    expect(attr.name).to eq('mol')
    expect(attr.baseline_value).to eq('42')
    expect(attr.preview_value).to eq(['42'])
    JSON::Validator.validate!(catalog_delta_schema, JSON.dump(delta.to_hash))
  end

  it 'ignores setting of --diff-array-value unless --migration MIGRATION is used' do
    pv = preview_hash
    pv['resources'][1]['parameters']['mol'] = ['42']
    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => false, :diff_array_value => true), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.array_value_diff_ignored?).to be(false)

    delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => false, :diff_array_value => false), timestamp)
    expect(delta.preview_equal?).to be(false)
    expect(delta.preview_compliant?).to be(false)
    expect(delta.array_value_diff_ignored?).to be(false)
  end

  it "reports string/int differences of the File 'mode' attribute regardless of migration_checker and diff_string_numeric flag" do
    pv = preview_hash
    pv['resources'][0]['parameters']['mode'] = 0600
    [[false, false], [true, false], [false, true], [true, true]].each do |mc,dsn|
      delta = CatalogDelta.new(baseline_hash, pv, options.merge(:migration_checker => mc, :diff_string_numeric => dsn), timestamp)
      expect(delta.preview_equal?).to be(false)
      expect(delta.conflicting_resource_count).to eq(1)
      expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
      conflict = delta.conflicting_resources[0]
      expect(conflict.conflicting_attribute_count).to eq(1)
      expect(conflict.conflicting_attributes).to contain_exactly(be_a(AttributeConflict))
      attr = conflict.conflicting_attributes[0]
      expect(attr.name).to eq('mode')
    end
  end

  it 'allows titles to have integer value' do
    pv = preview_hash
    pv['resources'][1] = {
      'type' => 'File',
      'title' => 42,
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 2,
      'exported' => false,
      'parameters' => {
        'ensure' => 'purged',
        'added' => 'Just arrived'
      }
    }
    pv['resources'].pop
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    pv['edges'].pop
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'File[42]'
      }
    )

    expect { CatalogDelta.new(baseline_hash, pv, options, timestamp) }.to_not raise_error()
  end

  it 'can be created from a hash' do
    pv = preview_hash
    pv['resources'][1] = {
      'type' => 'File',
      'title' => '/tmp/bartest',
      'tags' => ['file', 'class'],
      'file' => '/etc/puppet/environments/production/manifests/site.pp',
      'line' => 2,
      'exported' => false,
      'parameters' => {
        'ensure' => 'purged',
        'added' => 'Just arrived'
      }
    }
    pv['resources'].pop
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/baztest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 4,
      }
    )
    pv['edges'].pop
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'File[/tmp/bartest]'
      }
    )

    delta = CatalogDelta.new(baseline_hash, pv, options, timestamp)
    first_hash = delta.to_hash

    delta_from_hash = CatalogDelta.from_hash(first_hash)
    expect(delta_from_hash.added_resources).to contain_exactly(be_a(Resource))
    expect(delta_from_hash.missing_resources).to contain_exactly(be_a(Resource))
    expect(delta_from_hash.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    rc = delta_from_hash.conflicting_resources[0]
    expect(rc.added_attributes).to contain_exactly(be_a(Attribute))
    expect(rc.missing_attributes).to include(be_a(Attribute))
    expect(rc.conflicting_attributes).to contain_exactly(be_a(AttributeConflict))
    expect(delta_from_hash.added_edges).to contain_exactly(be_a(Edge))
    expect(delta_from_hash.missing_edges).to contain_exactly(be_a(Edge))

    second_hash = delta_from_hash.to_hash
    expect(first_hash).to eq(second_hash)
  end

  it 'has a valid JSON schema for excludes' do
    JSON::Validator.validate!(json_meta_schema, excludes_schema)
  end

  it 'can read and validate excludes JSON file' do
    excludes_file = fixture('excludes', 'excludes.json')
    excludes = JSON.load(File.read(excludes_file))
    JSON::Validator.validate!(excludes_schema, excludes)
  end

  it 'creates valid JSON array from array of Exclude instances' do
    excludes_file = fixture('excludes', 'excludes.json')
    excludes = Exclude.parse_file(excludes_file)
    JSON::Validator.validate!(excludes_schema, excludes.map {|e| e.to_hash })
  end
end
end
