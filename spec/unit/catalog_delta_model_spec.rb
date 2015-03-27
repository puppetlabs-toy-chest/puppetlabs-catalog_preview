require 'spec_helper'
require 'puppet'
require 'puppet/pops'
require 'puppet_x/puppetlabs/preview'

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
            'ensure' => 'present'
          }
        }
      ],
      'edges' => [
        {
          'source' => 'Class[main]',
          'target' => 'File[/tmp/footest]'
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

  it 'reports that tags are skipped' do
    delta = CatalogDelta.new(baseline_hash, preview_hash, true, false)
    expect(delta.tags_ignored).to be(true)
  end

  it 'reports version_equal' do
    delta = CatalogDelta.new(baseline_hash, preview_hash, true, false)
    expect(delta.version_equal).to be(true)
    delta = CatalogDelta.new(baseline_hash, preview_hash.merge!('version' => 1427456348), true, false)
    expect(delta.version_equal).to be(false)
  end

  it 'reports missing resource' do
    pv = preview_hash
    pv['resources'].pop
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
    expect(delta.missing_resource_count).to eq(1)
    expect(delta.missing_resources).to contain_exactly(be_a(Resource))
    expect(delta.missing_resources[0].type).to eq('File')
    expect(delta.missing_resources[0].title).to eq('/tmp/footest')
  end

  it 'reports added resource' do
    pv = preview_hash
    pv['resources'].push(
      {
        'type' => 'File',
        'title' => '/tmp/bartest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 1,
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
    expect(delta.added_resource_count).to eq(1)
    expect(delta.added_resources).to contain_exactly(be_a(Resource))
    expect(delta.added_resources[0].type).to eq('File')
    expect(delta.added_resources[0].title).to eq('/tmp/bartest')
  end

  it 'reports conflicting resource when preview is missing an attribute' do
    pv = preview_hash
    pv['resources'][0] = {
        'type' => 'File',
        'title' => '/tmp/footest',
        'tags' => ['file', 'class'],
        'file' => '/etc/puppet/environments/production/manifests/site.pp',
        'line' => 1,
      }
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
    expect(delta.conflicting_resource_count).to eq(1)
    expect(delta.conflicting_resources).to contain_exactly(be_a(ResourceConflict))
    conflict = delta.conflicting_resources[0]
    expect(conflict.type).to eq('File')
    expect(conflict.title).to eq('/tmp/footest')
    expect(conflict.added_attribute_count).to eq(0)
    expect(conflict.conflicting_attribute_count).to eq(0)
    expect(conflict.missing_attribute_count).to eq(1)
    expect(conflict.missing_attributes).to contain_exactly(be_a(Attribute))
    attr = conflict.missing_attributes[0]
    expect(attr.name).to eq('ensure')
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
        'mode' => '0775'
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
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
    expect(attr.name).to eq('mode')
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
      }
    }
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
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
  end

  it 'reports missing edges' do
    pv = preview_hash
    pv['edges'].pop
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
    expect(delta.missing_edge_count).to eq(1)
    expect(delta.missing_edges).to contain_exactly(be_a(Edge))
    edge = delta.missing_edges[0]
    expect(edge.source).to eq('Class[main]')
    expect(edge.target).to eq('File[/tmp/footest]')
  end

  it 'reports added edges' do
    pv = preview_hash
    pv['edges'].push(
      {
        'source' => 'Class[main]',
        'target' => 'Notify[roses are red]'
      }
    )
    delta = CatalogDelta.new(baseline_hash, pv, true, false)
    expect(delta.baseline_edge_count).to eq(1)
    expect(delta.preview_edge_count).to eq(2)
    expect(delta.added_edge_count).to eq(1)
    expect(delta.added_edges).to contain_exactly(be_a(Edge))
    edge = delta.added_edges[0]
    expect(edge.source).to eq('Class[main]')
    expect(edge.target).to eq('Notify[roses are red]')
  end
end
end

