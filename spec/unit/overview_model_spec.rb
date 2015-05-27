require 'spec_helper'
require 'puppet'
require 'puppet/pops'
require 'puppet_x/puppetlabs/preview'
require 'json'
require 'json-schema'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    describe 'Factory' do

      let!(:catalog_delta) do CatalogDeltaModel::CatalogDelta.from_hash(JSON.parse(<<END_JSON))
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-05-21T18:09:01.000869134+02:00",
  "baseline_catalog": "/path/to/baseline/catalog",
  "preview_catalog": "/path/to/preview/catalog",
  "node_name": "different.example.com",
  "tags_ignored": true,
  "string_numeric_diff_ignored": false,
  "baseline_env": "production",
  "preview_env": "preview",
  "version_equal": true,
  "baseline_resource_count": 3,
  "preview_resource_count": 3,
  "added_resources": [
    {
      "location": {
        "file": "/etc/puppet/environments/production/manifests/site.pp",
        "line": 4
      },
      "type": "File",
      "title": "/tmp/baztest",
      "diff_id": 1
    }
  ],
  "added_resource_count": 1,
  "added_attribute_count": 3,
  "missing_resources": [
    {
      "location": {
        "file": "/etc/puppet/environments/production/manifests/site.pp",
        "line": 3
      },
      "type": "File",
      "title": "/tmp/fumtest",
      "diff_id": 2
    }
  ],
  "missing_resource_count": 1,
  "missing_attribute_count": 11,
  "equal_resource_count": 1,
  "equal_attribute_count": 12,
  "conflicting_attribute_count": 1,
  "conflicting_resources": [
    {
      "baseline_location": {
        "file": "/etc/puppet/environments/production/manifests/site.pp",
        "line": 2
      },
      "preview_location": {
        "file": "/etc/puppet/environments/production/manifests/site.pp",
        "line": 2
      },
      "type": "File",
      "title": "/tmp/bartest",
      "equal_attribute_count": 9,
      "added_attributes": [
        {
          "name": "added",
          "value": "Just arrived",
          "diff_id": 4
        }
      ],
      "added_attribute_count": 1,
      "missing_attributes": [
        {
          "name": "array",
          "value": [
            "a",
            "b",
            "c",
            "c"
          ],
          "diff_id": 5
        },
        {
          "name": "before",
          "value": "#<Set:0x00000003b20220>",
          "diff_id": 6
        },
        {
          "name": "after",
          "value": "#<Set:0x00000003b1be00>",
          "diff_id": 7
        },
        {
          "name": "subscribe",
          "value": "#<Set:0x00000003b1bb80>",
          "diff_id": 8
        },
        {
          "name": "notify",
          "value": "#<Set:0x00000003b1b9f0>",
          "diff_id": 9
        },
        {
          "name": "hash",
          "value": {
            "a": "A",
            "b": [
              1,
              2
            ]
          },
          "diff_id": 10
        },
        {
          "name": "mol",
          "value": "42",
          "diff_id": 11
        }
      ],
      "missing_attribute_count": 7,
      "conflicting_attributes": [
        {
          "name": "ensure",
          "baseline_value": "present",
          "preview_value": "purged",
          "compliant": false,
          "diff_id": 12
        }
      ],
      "conflicting_attribute_count": 1,
      "diff_id": 3
    }
  ],
  "conflicting_resource_count": 1,
  "baseline_edge_count": 1,
  "preview_edge_count": 1,
  "added_edges": [
    {
      "source": "Class[main]",
      "target": "File[/tmp/bartest]",
      "diff_id": 13
    }
  ],
  "added_edge_count": 1,
  "missing_edges": [
    {
      "source": "Class[main]",
      "target": "File[/tmp/footest]",
      "diff_id": 14
    }
  ],
  "missing_edge_count": 1,
  "preview_compliant": false,
  "preview_equal": false
}
END_JSON
      end

      let!(:compliant_catalog_delta) do CatalogDeltaModel::CatalogDelta.from_hash(JSON.parse(<<END_JSON))
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-05-25T18:01:22.753510131+02:00",
  "baseline_catalog": "/path/to/baseline/catalog",
  "preview_catalog": "/path/to/preview/catalog",
  "node_name": "compliant.example.com",
  "tags_ignored": true,
  "string_numeric_diff_ignored": false,
  "baseline_env": "production",
  "preview_env": "preview",
  "version_equal": true,
  "baseline_resource_count": 3,
  "preview_resource_count": 4,
  "added_resources": [
    {
      "location": {
      "file": "/etc/puppet/environments/production/manifests/site.pp",
      "line": 4
      },
      "type": "File",
      "title": "/tmp/baztest",
      "diff_id": 1
    }
  ],
  "added_resource_count": 1,
  "added_attribute_count": 2,
  "missing_resources": [],
  "missing_resource_count": 0,
  "missing_attribute_count": 0,
  "equal_resource_count": 3,
  "equal_attribute_count": 17,
  "conflicting_attribute_count": 0,
  "conflicting_resources": [],
  "conflicting_resource_count": 0,
  "baseline_edge_count": 1,
  "preview_edge_count": 1,
  "added_edges": [],
  "added_edge_count": 0,
  "missing_edges": [],
  "missing_edge_count": 0,
  "preview_compliant": true,
  "preview_equal": false
}
END_JSON
      end
      let!(:fine_catalog_delta) do CatalogDeltaModel::CatalogDelta.from_hash(JSON.parse(<<END_JSON))
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-05-25T18:10:27.123815346+02:00",
  "baseline_catalog": "/path/to/baseline/catalog",
  "preview_catalog": "/path/to/preview/catalog",
  "node_name": "fine.example.com",
  "tags_ignored": true,
  "string_numeric_diff_ignored": false,
  "baseline_env": "production",
  "preview_env": "preview",
  "version_equal": true,
  "baseline_resource_count": 3,
  "preview_resource_count": 3,
  "added_resources": [],
  "added_resource_count": 0,
  "added_attribute_count": 0,
  "missing_resources": [],
  "missing_resource_count": 0,
  "missing_attribute_count": 0,
  "equal_resource_count": 3,
  "equal_attribute_count": 17,
  "conflicting_attribute_count": 0,
  "conflicting_resources": [],
  "conflicting_resource_count": 0,
  "baseline_edge_count": 1,
  "preview_edge_count": 1,
  "added_edges": [],
  "added_edge_count": 0,
  "missing_edges": [],
  "missing_edge_count": 0,
  "preview_compliant": true,
  "preview_equal": true
}
END_JSON
      end

      let!(:great_catalog_delta) do CatalogDeltaModel::CatalogDelta.from_hash(JSON.parse(<<END_JSON))
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-05-25T18:10:27.123815346+02:00",
  "baseline_catalog": "/path/to/baseline/catalog",
  "preview_catalog": "/path/to/preview/catalog",
  "node_name": "great.example.com",
  "tags_ignored": true,
  "string_numeric_diff_ignored": false,
  "baseline_env": "production",
  "preview_env": "preview",
  "version_equal": true,
  "baseline_resource_count": 3,
  "preview_resource_count": 3,
  "added_resources": [],
  "added_resource_count": 0,
  "added_attribute_count": 0,
  "missing_resources": [],
  "missing_resource_count": 0,
  "missing_attribute_count": 0,
  "equal_resource_count": 3,
  "equal_attribute_count": 17,
  "conflicting_attribute_count": 0,
  "conflicting_resources": [],
  "conflicting_resource_count": 0,
  "baseline_edge_count": 1,
  "preview_edge_count": 1,
  "added_edges": [],
  "added_edge_count": 0,
  "missing_edges": [],
  "missing_edge_count": 0,
  "preview_compliant": true,
  "preview_equal": true
}
END_JSON
      end

      let!(:ok_catalog_delta) do CatalogDeltaModel::CatalogDelta.from_hash(JSON.parse(<<END_JSON))
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-05-25T18:10:27.123815346+02:00",
  "baseline_catalog": "/path/to/baseline/catalog",
  "preview_catalog": "/path/to/preview/catalog",
  "node_name": "ok.example.com",
  "tags_ignored": true,
  "string_numeric_diff_ignored": false,
  "baseline_env": "production",
  "preview_env": "preview",
  "version_equal": true,
  "baseline_resource_count": 3,
  "preview_resource_count": 3,
  "added_resources": [],
  "added_resource_count": 0,
  "added_attribute_count": 0,
  "missing_resources": [],
  "missing_resource_count": 0,
  "missing_attribute_count": 0,
  "equal_resource_count": 3,
  "equal_attribute_count": 17,
  "conflicting_attribute_count": 0,
  "conflicting_resources": [],
  "conflicting_resource_count": 0,
  "baseline_edge_count": 1,
  "preview_edge_count": 1,
  "added_edges": [],
  "added_edge_count": 0,
  "missing_edges": [],
  "missing_edge_count": 0,
  "preview_compliant": true,
  "preview_equal": true
}
END_JSON
      end

      let(:factory) { Factory.new }

      it 'assigns id to created instances' do
        resource_type = factory.send(:new_entity, ResourceType, 'baz')
        expect(resource_type.id).to eq(0)
        environment = factory.send(:new_entity, Environment, 'bez')
        expect(environment.id).to eq(1)
        expect(factory[resource_type.id]).to be(resource_type)
        expect(factory[environment.id]).to be(environment)
      end

      it 'can serialize and restore with JSON' do
        resource_type = factory.send(:new_entity, ResourceType, 'baz')
        environment = factory.send(:new_entity, Environment, 'bez')
        overview = Overview.new({0 => resource_type, 1 => environment})

        overview_json = JSON.unparse(overview.to_hash)
        parsed_overview = Overview.from_hash(JSON.parse(overview_json))

        expect(parsed_overview).to be_instance_of(Overview)
        resource_type = parsed_overview[0]
        expect(resource_type).to be_instance_of(ResourceType)
        expect(resource_type.id).to eq(0)
        environment = parsed_overview[1]
        expect(environment).to be_instance_of(Environment)
        expect(environment.id).to eq(1)
      end

      it 'can merge a CatalogDelta twice without creating redundant entries' do
        factory.merge(catalog_delta)
        overview_hash1 = factory.create_overview.to_hash
        factory.merge(catalog_delta)
        overview_hash2 = factory.create_overview.to_hash
        expect(overview_hash1).to eq(overview_hash2)
      end

      context 'when queried' do
        let!(:overview) { Factory.new.merge(catalog_delta).create_overview }

        it 'can traverse relationships using dot notation' do
          expect(overview.of_class(Resource).map { |r| r.type.name }.uniq).to include(*%w(File Class))
        end

        it 'will produce aggregated properties' do
          expect(overview.of_class(Resource).select { |r| r.type.name == 'Class' }.title).to eq(%w(main))
        end

        it 'can traverse many-to-many relationships' do
          expect(overview.of_class(Node).issues.empty?).to be_falsey
        end

        it 'can traverse using class cast' do
          expect(overview.of_class(Node).issues.of_class(ResourceIssue).resource.any? { |r| r.title == '/tmp/baztest' }).to be_truthy
          expect(overview.of_class(Node).issues.of_class(EdgeIssue).source.any? { |r| r.title == 'main' }).to be_truthy
        end
      end

      context 'when dealing with several deltas' do
        let(:now) { Time.now.iso8601(9) }
        let!(:overview) { Factory.new.merge(catalog_delta).merge(compliant_catalog_delta).merge(ok_catalog_delta).merge(fine_catalog_delta).merge(great_catalog_delta)
                            .merge_failure('fail.example.com', 'production', 'preview', now, 2).create_overview }

        it 'can produce summary list' do
          summary = Hash[[ :equal, :compliant, :different, :error ].map do |severity|
                [severity, overview.of_class(Node).select { |n| n.severity == severity }.sort.map do |n|
                    { :name => n.name,
                      :baseline_env => n.baseline_env.name,
                      :preview_env => n.preview_env.name
                    }
                  end]
            end]

          # Check that we got all entries
          expect(summary[:equal].size).to eq(3)
          expect(summary[:compliant].size).to eq(1)
          expect(summary[:different].size).to eq(1)
          expect(summary[:error].size).to eq(1)

          # Check that the equal entries were sorted by node name
          expect(summary[:equal].map { |entry| entry[:name] }).to eq(%w(fine.example.com great.example.com ok.example.com))
        end

        it 'can cut and use a slice' do
          extractor = Query::NodeExtractor.new
          node = overview.of_class(Node).select {|n| n.name == 'different.example.com'}.first
          extractor.add_node(node)

          # Overview should only contain one node
          overview = extractor.create_overview
          nodes = overview.of_class(Node)
          expect(nodes.size).to eq(1)
          expect(nodes.first).to eq(node)
          expect(nodes.issues.of_class(EdgeIssue).source.any? { |r| r.title == 'main' }).to be_truthy
          expect(nodes.issues.of_class(ResourceIssue).resource.any? { |r| r.title == '/tmp/baztest' }).to be_truthy
        end
      end
    end
  end
end

