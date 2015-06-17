require 'spec_helper'
require 'puppet_x/puppetlabs/preview'
require 'json'

module PuppetX::Puppetlabs::Migration
  module OverviewModel
    describe Report do
      let!(:conflicting_delta) { CatalogDeltaModel::CatalogDelta.from_hash(load_catalog_delta('conflicting-delta.json')) }
      let!(:assignment_failed_log) { load_compile_log('assignment_failed.json') }

      context 'when reporting' do
        let!(:now) { Time.now.iso8601(9) }
        let!(:overview) { Factory.new.merge(conflicting_delta).merge_failure('failed.example.com', 'test', now, 2, assignment_failed_log).create_overview }

        let(:report) { Report.new(overview) }

        it 'can produce a hash' do
          hash = report.to_hash
          expect(hash).to include(:stats, :baseline, :top_ten, :changes)
          expect(hash[:changes]).to include(:resource_type_changes, :edge_changes)
        end

        it 'can produce a text' do
          text = report.to_s
          expect(text).to match(/^Stats$/)
          expect(text).to match(/^Baseline Errors \(by manifest\)$/)
          expect(text).to match(/^Baseline Errors \(by issue\)$/)
          expect(text).to match(/^Top ten nodes with most issues$/)
          expect(text).to match(/^Changes per Resource Type$/)
          expect(text).to match(/^Changes of Edges$/)
        end
      end
    end
  end
end
