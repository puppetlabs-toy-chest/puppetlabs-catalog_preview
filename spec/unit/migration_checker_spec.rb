require 'spec_helper'
require 'puppet'
require 'puppet/pops'
require 'puppet_x/puppetlabs/preview'

describe 'PuppetX::Puppetlabs::MigrationChecker' do

  before(:each) do
    Puppet[:strict_variables] = true

    # These must be set since the 3x logic switches some behaviors on these even if the tests explicitly
    # use the 4x parser and evaluator.
    #
    Puppet[:parser] = 'future'

    # Puppetx cannot be loaded until the correct parser has been set (injector is turned off otherwise)
    require 'puppetx'

    # Tests needs a known configuration of node/scope/compiler since it parses and evaluates
    # snippets as the compiler will evaluate them, butwithout the overhead of compiling a complete
    # catalog for each tested expression.
    #
    @parser  = Puppet::Pops::Parser::EvaluatingParser.new
    @node = Puppet::Node.new('node.example.com')
    @node.environment = Puppet::Node::Environment.create(:testing, [])
    @compiler = Puppet::Parser::Compiler.new(@node)
    @scope = Puppet::Parser::Scope.new(@compiler)
    @scope.source = Puppet::Resource::Type.new(:node, 'node.example.com')
    @scope.parent = @compiler.topscope
  end

  let(:scope) { @scope }

  it "warns about ambiguous octal integers" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, " 0666", __FILE__)).to eql(438)
      expected_warning = "This octal value evaluates to the decimal value '438': Quote if the String '0666' was intended. at line 1:2"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
    end
  end

  it "warns about ambiguous hex integers" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, " 0x10", __FILE__)).to eql(16)
      expected_warning = "This hex value evaluates to the decimal value '16': Quote if the String '0x10' was intended. at line 1:2"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
    end
  end

  it "does not warn about decimal integers" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, " 1", __FILE__)).to eql(1)
      expect(migration_checker.acceptor.warnings).to be_empty
    end
  end

  it "only warns once per source position" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      source = "Integer[1,3].reduce |$memo, $x| {$memo + $x + 01}"
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(8)
      expected_warning = "This octal value evaluates to the decimal value '1': Quote if the String '01' was intended. at line 1:47"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
      expect(migration_checker.acceptor.warnings.size).to eql(1)
    end
  end

  it "warns about ambiguous floating point" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, " 0.0000005", __FILE__)).to eql(5.0e-07)
      expected_warning = "This value evaluates to the imprecise floating point number 5.0e-07: Quote if a String value was intended at line 1:2"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
    end
  end

  def formatted_warnings(acceptor)
    formatter = Puppet::Pops::Validation::DiagnosticFormatterPuppetStyle.new
    acceptor.warnings.map { |w| formatter.format(w) }
  end
end