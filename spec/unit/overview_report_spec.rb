require 'spec_helper'
require 'puppet_x/puppetlabs/preview'
require 'json'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    describe Report do
      let!(:conflicting_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('conflicting-delta.json')) }
      let!(:assignment_failed_log) { load_compile_log('assignment_failed.json') }
      let!(:nodes_table) do
        <<-NODES_TABLE
        node name        errors  warnings   diffs
  --------------------- -------- -------- --------
  different.example.com        1        0        0
  failed.example.com           1        0        0
  different.example.com        0        0        3
        NODES_TABLE
      end

      context 'when reporting' do
        let!(:now) { Time.now.iso8601(9) }
        let!(:overview) do
          factory = Factory.new
          factory.merge(conflicting_delta)
          factory.merge_failure('failed.example.com', 'test', now, 2, assignment_failed_log)

          # Fake that the same error is logged for both nodes.
          entry = assignment_failed_log[0].clone
          entry[:node] = 'different.example.com'
          factory.merge_failure('different.example.com', 'test', now, 2, [entry])
          factory.create_overview
        end

        let(:report) { Report.new(overview) }

        it 'can produce a hash' do
          hash = report.to_hash
          expect(hash).to include(:stats, :baseline, :all_nodes, :changes)
          expect(hash[:changes]).to include(:resource_type_changes, :edge_changes)
        end

        it 'eliminates duplicate line:position entries' do
          baseline = report.to_hash[:baseline]
          expect(baseline[:error_count_by_issue_code][0][:manifests].values[0].size).to eq(1)
        end

        it 'eliminates duplicate compilation errors' do
          baseline = report.to_hash[:baseline]
          expect(baseline[:compilation_errors][0][:errors].size).to eq(1)
        end

        it 'can produce a text with top ten nodes' do
          text = report.to_text(true)
          expect(text).to match(/^Stats$/)
          expect(text).to match(/^Baseline Errors \(by manifest\)$/)
          expect(text).to match(/^Baseline Errors \(by issue\)$/)
          expect(text).to match(/^Changes per Resource Type$/)
          expect(text).to match(/^Changes of Edges$/)
          expect(text).to end_with("Top ten nodes with most issues\n" + nodes_table)
        end

        it 'can produce a text with all nodes' do
          text = report.to_text(false)
          expect(text).to match(/^Stats$/)
          expect(text).to match(/^Baseline Errors \(by manifest\)$/)
          expect(text).to match(/^Baseline Errors \(by issue\)$/)
          expect(text).to match(/^Changes per Resource Type$/)
          expect(text).to end_with("All nodes\n" + nodes_table)
        end
      end
    end
  end
end
