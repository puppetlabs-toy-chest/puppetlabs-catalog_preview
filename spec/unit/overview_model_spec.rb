require 'spec_helper'
require 'puppet_x/puppetlabs/preview'
require 'json'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    describe 'Factory' do
      let!(:conflicting_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('conflicting-delta.json')) }
      let!(:conflict_without_location_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('conflict-without-location-delta.json')) }
      let!(:compliant_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('compliant-delta.json')) }
      let!(:equal_delta_hash) { load_catalog_delta('equal-delta.json')}
      let!(:equal_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash) }
      let!(:fine_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash.merge(:node_name => 'fine.example.com')) }
      let!(:great_delta) { CatalogDeltaModel::CatalogDelta.from_hash(equal_delta_hash.merge(:node_name => 'great.example.com')) }
      let!(:assignment_failed_log) { load_compile_log('assignment_failed.json') }

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

      it 'can merge a CatalogDelta that has resources with no file/line information' do
        factory.merge(conflict_without_location_delta)
        overview = factory.create_overview
        expect(overview.of_class(ResourceIssue).select { |r| r.location.nil? }.size).to eq(1)
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
                            .merge_failure('fail.example.com', 'test', now, 2).create_overview }

        it 'can produce summary list' do
          summary = Hash[[ :equal, :compliant, :conflicting, :error ].map do |severity|
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
          expect(summary[:conflicting].size).to eq(1)
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

      context 'when loading logs' do
        let(:now) { Time.now.iso8601(9) }
        let!(:overview) { Factory.new.merge_failure('fail.example.com', 'test', now, 3, assignment_failed_log).create_overview }

        it 'contains log levels' do
          expect(overview.of_class(LogLevel)).not_to be_empty
        end

        it 'contains log issues' do
          expect(overview.of_class(LogIssue)).not_to be_empty
        end

        it 'contains log messages' do
          expect(overview.of_class(LogMessage)).not_to be_empty
        end

        it 'contains log entries' do
          expect(overview.of_class(LogEntry)).not_to be_empty
        end

        it 'can navigate from entry to level via message and issue' do
          expect(overview.of_class(LogEntry).message.issue.level).not_to be_empty
        end

        it 'can navigate from level to entry via issues and messages' do
          expect(overview.of_class(LogLevel).issues.messages.log_entries).not_to be_empty
        end

        it 'can navigate directly from level to entry' do
          expect(overview.of_class(LogLevel).log_entries).not_to be_empty
        end

        it 'contains expected data' do
          le = overview.of_class(LogEntry).first
          expect(le.timestamp).to eq('2015-06-03T05:55:19.133433903-07:00')
          expect(le.compilation.environment.name).to eq('test')
          expect(le.compilation.node.name).to eq('fail.example.com')
          expect(le.compilation.baseline?).to be_falsey
          rc = le.message
          if rc.is_a?(Proc)
            puts "le is_a #{le.class.name} and answers #{le.is_a?(Minitest::Assertions)} to is_a?(MiniTest::Assertions)"
            puts rc.source_location
            puts rc.to_s
            puts rc.parameters.to_s
            puts rc.arity
            puts rc.lambda?
          end
          expect(le.message.message).to eq("Illegal attempt to assign to 'a Name'. Not an assignable reference")
          expect(le.message.issue.name).to eq('ILLEGAL_ASSIGNMENT')
          expect(le.message.issue.level.name).to eq('err')
          expect(le.location.file.path).to eq('/tmp/preview_broken_test.YE0REF/environments/test/manifests/init.pp')
          expect(le.location.line).to eq(3)
          expect(le.location.pos).to eq(5)
        end
      end
    end
  end
end

