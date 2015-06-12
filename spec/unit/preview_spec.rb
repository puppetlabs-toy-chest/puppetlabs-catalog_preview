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

    context "with one or more nodes" do
      let!(:overview) { PuppetX::Puppetlabs::Migration::OverviewModel::Factory.new.merge(conflicting_delta).merge(compliant_delta).merge(equal_delta).merge(fine_delta).merge(great_delta).merge_failure('fail.example.com', 'test', now, 2).create_overview }

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

    context "with only one node" do
      diff_string = <<-TEXT
{
  "produced_by": "puppet preview 3.8.0",
  "timestamp": "2015-06-12T11:32:17.754118000-07:00",
  "baseline_catalog": "/Users/HAIL9000/.puppet/var/preview/centagent.local/baseline_catalog.json",
  "preview_catalog": "/Users/HAIL9000/.puppet/var/preview/centagent.local/preview_catalog.json",
  "node_name": "centagent.local",
  "baseline_env": "production",
  "preview_env": "testing",
  "version_equal": true,
  "baseline_resource_count": 4,
  "preview_resource_count": 4,
  "added_resources": [

  ],
  "added_resource_count": 0,
  "added_attribute_count": 0,
  "missing_resources": [

  ],
  "missing_resource_count": 0,
  "missing_attribute_count": 0,
  "equal_resource_count": 4,
  "equal_attribute_count": 10,
  "conflicting_attribute_count": 0,
  "conflicting_resources": [

  ],
  "conflicting_resource_count": 0,
  "baseline_edge_count": 3,
  "preview_edge_count": 3,
  "added_edges": [

  ],
  "added_edge_count": 0,
  "missing_edges": [

  ],
  "missing_edge_count": 0,
  "preview_compliant": true,
  "preview_equal": true
}
      TEXT

      diff_json = JSON.load(diff_string)

      let(:diff_catalog) { catalog_delta.from_hash(diff_json) }

      let(:overview) { PuppetX::Puppetlabs::Migration::OverviewModel::Factory.new.merge(compliant_delta).create_overview }

      let(:preview) {
        preview = Puppet::Application[:preview]
        preview.options[:nodes] = ['compliant.example.com']
        preview.instance_variable_set("@overview", overview)
        preview
      }

      it "should work with the 'summary' argument" do
        expected_summary = <<-TEXT

Catalog:
  Versions......: equal
  Preview.......: equal
  Tags..........: compared
  String/Numeric: type significant compare

Resources:
  Baseline......: 4
  Preview.......: 4
  Equal.........: 4
  Compliant.....: 0
  Missing.......: 0
  Added.........: 0
  Conflicting...: 0

Attributes:
  Equal.........: 10
  Compliant.....: 0
  Missing.......: 0
  Added.........: 0
  Conflicting...: 0

Edges:
  Baseline......: 3
  Preview.......: 3
  Missing.......: 0
  Added.........: 0

Output:
  For node......: /dev/null/preview/

\e[0;32mCatalogs for node '' are equal.\e[0m
        TEXT
        preview.options[:view] = :summary
        expect{ preview.view(diff_catalog)}.to output(expected_summary).to_stdout
      end

      it "should work with the 'status' argument" do
        preview.options[:view] = :status
        expect{ preview.view(diff_catalog)}.to output("\e[0;32mCatalogs for node '' are equal.\e[0m\n").to_stdout
      end
    end
  end
end
