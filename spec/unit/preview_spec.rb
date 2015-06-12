require 'spec_helper'
require 'puppet'
require 'puppet_x/puppetlabs/preview'
require 'puppet/application/preview'
require 'puppet_x/puppetlabs/migration/catalog_delta_model'
require 'puppet_x/puppetlabs/migration/overview_model/factory'
require 'json'

describe Puppet::Application::Preview do

  context "when running with --view" do

    let(:catalog_delta) { PuppetX::Puppetlabs::Migration::CatalogDeltaModel::CatalogDelta }

    let!(:conflicting_delta) { catalog_delta.from_hash(load_catalog_delta('conflicting-delta.json')) }
    let!(:compliant_delta) { catalog_delta.from_hash(load_catalog_delta('compliant-delta.json')) }
    let!(:equal_delta_hash) { load_catalog_delta('equal-delta.json')}
    let!(:equal_delta) { catalog_delta.from_hash(equal_delta_hash) }
    let!(:fine_delta) { catalog_delta.from_hash(equal_delta_hash.merge(:node_name => 'fine.example.com')) }
    let!(:great_delta) { catalog_delta.from_hash(equal_delta_hash.merge(:node_name => 'great.example.com')) }
    let(:now) { Time.now.iso8601(9) }

    let(:factory) { PuppetX::PuppelLabs::Migration::OverviewModel::Factory.new }

    context "with one or more nodes" do
      let!(:overview) { PuppetX::Puppetlabs::Migration::OverviewModel::Factory.new.merge(conflicting_delta)
      .merge(compliant_delta).merge(equal_delta).merge(fine_delta).merge(great_delta)
      .merge_failure('fail.example.com', 'test', now, 2).create_overview }

      let(:preview) {
        preview = Puppet::Application[:preview]
        preview.options[:nodes] = ['fine.example.com', 'great.example.com', 'ok.example.com', 'compliant.example.com', 'different.example.com', 'fail.example.com']
        preview.instance_variable_set("@overview", overview)
        preview
      }

      it "should work with the 'summary' argument"  do
        expected_summary = <<-TEXT

Summary:
  Total Number of Nodes...: 6
  Baseline Failed.........: 1
  Preview Failed..........: 0
  Catalogs with Difference: 5
  Compliant Catalogs......: 1
  Equal Catalogs..........: 3

\e[0;32mequal: fine.example.com\e[0m
\e[0;32mequal: great.example.com\e[0m
\e[0;32mequal: ok.example.com\e[0m
compliant: compliant.example.com
catalog delta: different.example.com
\e[0;31mbaseline failed ([]): fail.example.com\e[0m
        TEXT

        preview.options[:view] = 'summary'

        expect{ preview.view }.to output(expected_summary).to_stdout
      end

      it "should work with the 'status' argument"  do
        expected_status = <<-TEXT

Summary:
  Total Number of Nodes...: 6
  Baseline Failed.........: 1
  Preview Failed..........: 0
  Catalogs with Difference: 5
  Compliant Catalogs......: 1
  Equal Catalogs..........: 3

        TEXT

        preview.options[:view] = :status
        expect{ preview.view }.to output(expected_status).to_stdout
      end

      it "should work with the 'none' argument"  do
        preview.options[:view] = :none
        expect{preview.view}.to_not output.to_stdout
      end

      it "should work with the 'diff_nodes' argument"  do
        expected_node_list = <<-TEXT
fail.example.com
different.example.com
        TEXT

        preview.options[:view] = :diff_nodes
        expect{ preview.view }.to output(expected_node_list).to_stdout
      end

      it "should work with the 'failed_nodes' argument"  do
        expected_node_list = <<-TEXT
fail.example.com
        TEXT

        preview.options[:view] = :failed_nodes
        expect{ preview.view }.to output(expected_node_list).to_stdout
      end

      it "should work with the 'equal_nodes' argument"  do
        expected_node_list = <<-TEXT
fine.example.com
great.example.com
ok.example.com
        TEXT

        preview.options[:view] = :equal_nodes
        expect{ preview.view }.to output(expected_node_list).to_stdout
      end

      it "should work with the 'compliant_nodes' argument"  do
        expected_node_list = <<-TEXT
compliant.example.com
fine.example.com
great.example.com
ok.example.com
        TEXT

        preview.options[:view] = :compliant_nodes

        expect{ preview.view }.to output(expected_node_list).to_stdout
      end
    end
  end
end
