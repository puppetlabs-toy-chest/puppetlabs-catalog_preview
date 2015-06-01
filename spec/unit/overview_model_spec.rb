require 'spec_helper'
require 'puppet_x/puppetlabs/preview'
require 'json'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    describe 'Factory' do
      let!(:conflicting_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('conflicting-delta.json')) }
      let!(:compliant_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('compliant-delta.json')) }
      let!(:equal_delta_hash) { load_catalog_delta('equal-delta.json')}
      let!(:equal_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash) }
      let!(:fine_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash.merge(:node_name => 'fine.example.com')) }
      let!(:great_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash.merge(:node_name => 'great.example.com')) }

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
        factory.merge(conflicting_delta)
        overview_hash1 = factory.create_overview.to_hash
        factory.merge(conflicting_delta)
        overview_hash2 = factory.create_overview.to_hash
        expect(overview_hash1).to eq(overview_hash2)
      end

      context 'when queried' do
        let!(:overview) { Factory.new.merge(conflicting_delta).create_overview }

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
        let!(:overview) { Factory.new.merge(conflicting_delta).merge(compliant_delta).merge(equal_delta).merge(fine_delta).merge(great_delta)
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

