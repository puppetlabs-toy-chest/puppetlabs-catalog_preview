require 'spec_helper'
require 'puppet'
require 'puppet/pops'
require 'puppet_x/puppetlabs/preview'

describe 'PuppetX::Puppetlabs::MigrationChecker', :if => Puppet.version =~ /^3\./ do

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

  it "warns that all in-expressions should be reviewed" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, " 5 in ['0x1f']", __FILE__)).to eql(false)
      expected_warning = "Please review the expectations of using this in-expression against the 4.x specification (3.x. evaluation is undefined for many corner cases) at line 1:4"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
    end
  end

  it "warns that evaluation of empty string is true" do
    migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
    Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
      expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, "$a='' $a and true", __FILE__)).to eql(true)
      expected_warning = "Empty string evaluated to true (3.x evaluates to false) at line 1:7"
      expect(formatted_warnings(migration_checker.acceptor)[0]).to eql(expected_warning)
    end
  end

  { # source                          => expected position(s)
    # ------                             --------------------
    "'Integer' == Integer"            => "1:14",
    "Integer < Integer"               => ["1:1", "1:11"],
    "Integer > Integer"               => ["1:1", "1:11"],
    "Integer <= Integer and false"    => ["1:1", "1:12"],
    "Integer == Integer and false"    => ["1:1", "1:12"],
    "Integer != Integer and false"    => ["1:1", "1:12"],
    "Integer >= Integer and false"    => ["1:1", "1:12"],
    "Integer =~ Integer"              => "1:1",
    "Integer !~ Integer and false"    => "1:1",

    "Integer ? { default => false }"                                => "1:1",
    "'Integer' ? { Integer => false, default => false}"             => "1:15",

    "case 'Integer' { Integer: {true} default: {false}}"            => "1:18",
    "case 'Integer' { Integer, Integer: {true} default: {false}}"   => ["1:18", "1:27"],
    "case Integer { 'Integer': {true} default: {false}}"            => "1:6",

    "Integer in ['Integer'] and false"                              => "1:1",

  }.each do |source, position|

    it "warns that uc bare word is a type, not a string in #{source} at #{position}" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(false)
        position = [position] unless position.is_a?(Array)
        position.each_with_index do |p, index|
          expected_warning = "Upper cased non quoted word evaluates to the type 'Integer' (3.x evaluates to a String) at line #{p}"
          expect(formatted_warnings(migration_checker.acceptor)).to include(expected_warning)
        end
      end
    end
  end

  { # source                          => expected result
    # ------                             --------------------
    "'1' == 1"                        => {:pos => "1:5", :left => 'String', :right => 'Fixnum', :op => '==', :result => false },
    "'1' != 1"                        => {:pos => "1:5", :left => 'String', :right => 'Fixnum', :op => '!=', :result => true },
    "1 == '1'"                        => {:pos => "1:3", :left => 'Fixnum', :right => 'String', :op => '==', :result => false },
    "1 != '1'"                        => {:pos => "1:3", :left => 'Fixnum', :right => 'String', :op => '!=', :result => true },
    "undef == ''"                     => {:pos => "1:7", :left => 'NilClass', :right => 'String', :op => '==', :result => false },
    "undef != ''"                     => {:pos => "1:7", :left => 'NilClass', :right => 'String', :op => '!=', :result => true },
  }.each do |source, expected|

    it "warns that equality check may be different because of type mismatch for #{source} at #{expected[:pos]}" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(expected[:result])
        expected_warning = "The '#{expected[:op]}' expression evaluates to #{expected[:result]} due to type mismatch between #{expected[:left]} and #{expected[:right]} (3.x. may evaluate differently) at line #{expected[:pos]}"
        expect(formatted_warnings(migration_checker.acceptor)).to include(expected_warning)
      end
    end
  end

  { # source                          => expected result
    # ------                             --------------------
    "[1] == '1'"                        => {:result => false },
    "'1' != []"                         => {:result => true },
    "{a=>1} == [[a, 1]]"                => {:result => false },
    "true == 'true'"                    => {:result => false },
    "undef == false"                    => {:result => false },
    "undef != false"                    => {:result => true },
    "1 == 2"                            => {:result => false },

  }.each do |source, expected|

    it "does not warn that equality check may be different for '#{source}' (since 3.x does it right)" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(expected[:result])
        expect(formatted_warnings(migration_checker.acceptor)).to be_empty
      end
    end
  end

  { # source                          => expected result
    # ------                             --------------------
    "case '1' { 1: {} }"              => {:pos => "1:12", :op => 'Case Option', :left => 'String', :right => 'Fixnum', :result => nil },
    "case '1' { '2', 1: {} }"         => {:pos => "1:17", :op => 'Case Option', :left => 'String', :right => 'Fixnum', :result => nil },
    "case [1,2] { /2/: {} }"          => {:pos => "1:14", :op => 'Case Option', :left => 'Array', :right => 'Regexp', :result => nil },
    "case /2/ { 2: {} }"              => {:pos => "1:12", :op => 'Case Option', :left => 'Regexp', :right => 'Fixnum', :result => nil },

    "'1' ? { 1  => true, default => undef }"    => {:pos => "1:9", :op => 'Selector Option', :left => 'String', :right => 'Fixnum', :result => nil },
    "[1,2] ? { /2/ => true, default => undef }" => {:pos => "1:11", :op => 'Selector Option', :left => 'Array', :right => 'Regexp', :result => nil },
    "/2/ ? { 2  => true, default => undef }"    => {:pos => "1:9", :op => 'Selector Option', :left => 'Regexp', :right => 'Fixnum', :result => nil },

  }.each do |source, expected|

    it "warns that case option may be different because of type mismatch for #{source} at #{expected[:pos]}" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(expected[:result])
        expected_warning = "The #{expected[:op]} was not selected due to type mismatch between '#{expected[:left]}' and '#{expected[:right]}' (3.x. may match if values in string form match) at line #{expected[:pos]}"
        expect(formatted_warnings(migration_checker.acceptor)).to include(expected_warning)
      end
    end
  end

  { # source                          => expected result
    # ------                             --------------------
    "case '1' { '1': {} }"            => { :result => nil },
    "case 1 { 2, 1: {} }"             => { :result => nil },
    "case [1,2] { [1,2]: {} }"        => { :result => nil },
    "case /2/ { '2': {} }"            => { :result => nil },

    "'1' ? { '1'  => true, default => undef }"    => { :result => true },
    "[1,2] ? { [1,2] => true, default => undef }" => { :result => true },
    "'2' ? { /2/  => true, default => undef }"    => { :result => true },

  }.each do |source, expected|

    it "does not warn about case options that work the same way in 3.x and 4.x such as #{source}" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(expected[:result])
        expect(formatted_warnings(migration_checker.acceptor)).to be_empty
      end
    end
  end

  { # source                                                  => expected result
    # ------                                                  --------------------
    "$a = [1,2,3] $b = $a [1]"                                => {:pos => "1:22", :result => [1] },
    "if true { $a = [1,2,3] $b = $a [1]}"                     => {:pos => "1:32", :result => [1] },
    "if false {} else {$a = [1,2,3] $b = $a [1]}"             => {:pos => "1:40", :result => [1] },
    "unless false { $a = [1,2,3] $b = $a [1]}"                => {:pos => "1:37", :result => [1] },
    "unless true {bug4278} else { $a = [1,2,3] $b = $a [1]}"  => {:pos => "1:51", :result => [1] },
  }.each do |source, expected|

    it "warns that WS before [] is Array instead of indexed access #{source} at #{expected[:pos]}" do
      migration_checker = PuppetX::Puppetlabs::Migration::MigrationChecker.new
      Puppet.override({:migration_checker => migration_checker}, "test-preview-migration-checker") do
        expect(Puppet::Pops::Parser::EvaluatingParser.new.evaluate_string(scope, source, __FILE__)).to eql(expected[:result])
        expected_warning = "The expression parsed to an Array (3.x parses this as an [] operation on the preceding value even if [] is preceded by white-space) at line #{expected[:pos]}"
        expect(formatted_warnings(migration_checker.acceptor)).to include(expected_warning)
      end
    end
  end

  def formatted_warnings(acceptor)
    formatter = Puppet::Pops::Validation::DiagnosticFormatterPuppetStyle.new
    acceptor.warnings.map { |w| formatter.format(w) }
  end
end