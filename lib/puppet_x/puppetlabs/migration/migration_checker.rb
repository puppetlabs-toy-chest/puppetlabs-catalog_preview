# An implementation of the MigrationChecker API
# This class should be added in the puppet context under the key :migration_Checker
# when the future parser and evaluator is operating in order to get callbacks to the methods
# of this class.
#
# When the transaction using the MigrationChecker has finished, the collected
# diagnostics can be obtained by getting the Acceptor and asking it for all diagnostics,
# errors, warnings etc.
#
class PuppetX::Puppetlabs::Migration::MigrationChecker < Puppet::Pops::Migration::MigrationChecker
  Issues = PuppetX::Puppetlabs::Migration::MigrationIssues

  # The MigrationChecker's severity producer makes all issues have
  # warning severity by default.
  #
  class SeverityProducer < Puppet::Pops::Validation::SeverityProducer

    def initialize
      super(:warning)

      # TODO: TEMPLATE CODE - REMOVE BEFORE RELEASE
      # Example of configuring issues to not be a warning
      # p = self
      # p[Issues::EMPTY_RESOURCE_SPECIALIZATION] = :deprecation
    end
  end

  # An acceptor of migration issues that only accepts diagnostics
  # for a given [file, line, pos, issue, severity] once in its lifetime
  #
  class MigrationIssueAcceptor < Puppet::Pops::Validation::Acceptor
    attr_reader :diagnostics

    def initialize
      @reported = Set.new
      super
    end

    def accept(diagnostic)
      # Only accept unique diagnostics (unique == same issue, file, line, pos and severity)
      return unless @reported.add?(diagnostic)
      # Collect the diagnostic per severity and remember
      super diagnostic
    end
  end

  attr_reader :diagnostic_producer
  attr_reader :acceptor

  def initialize
    @acceptor = MigrationIssueAcceptor.new
    @diagnostic_producer = Puppet::Pops::Validation::DiagnosticProducer.new(
      @acceptor,
      SeverityProducer.new,
      Puppet::Pops::Model::ModelLabelProvider.new)
  end

  # @param issue [Puppet::Pops::Issue] the issue to report
  # @param semantic [Puppet::Pops::ModelPopsObject] the object for which evaluation failed in some way. Used to determine origin.
  # @param options [Hash] hash of optional named data elements for the given issue
  # @return [nil] this method does not return a meaningful value
  # @raise [Puppet::ParseError] an evaluation error initialized from the arguments (TODO: Change to EvaluationError?)
  #
  def report(issue, semantic, options={}, except=nil)
    diagnostic_producer.accept(issue, semantic, options, except)
  end
  private :report

  def report_ambiguous_integer(o)
    radix = o.radix
    return unless radix == 8 || radix == 16
    report(Issues::MIGRATE4_AMBIGUOUS_INTEGER, o, {:value => o.value, :radix => radix})
  end

  def report_ambiguous_float(o)
    report(Issues::MIGRATE4_AMBIGUOUS_FLOAT, o, {:value => o.value })
  end

  def report_empty_string_true(value, o)
    return unless value == ''
    report(Issues::MIGRATE4_EMPTY_STRING_TRUE, o)
  end

  def report_uc_bareword_type(value, o)
    return unless value.is_a?(Puppet::Pops::Types::PAnyType)
    return unless o.is_a?(Puppet::Pops::Model::QualifiedReference)
    report(Issues::MIGRATE4_UC_BAREWORD_IS_TYPE, o, {:type => value.to_s })
  end

  def report_equality_type_mismatch(left, right, o)
    return unless is_type_diff?(left, right)
    report(Issues::MIGRATE4_EQUALITY_TYPE_MISMATCH, o, {:left => left, :right => right })
  end

  def report_option_type_mismatch(test_value, option_value, option_expr, matching_expr)
    return unless is_type_diff?(test_value, option_value) || is_match_diff?(test_value, option_value)
    report(Issues::MIGRATE4_OPTION_TYPE_MISMATCH, matching_expr, {:left => test_value, :right => option_value, :option_expr => option_expr})
  end

  # Helper method used by equality and case option to determine if a diff in type may cause difference between 3.x and 4.x
  # @return [Boolean] true if diff should be reported
  #
  def is_type_diff?(left, right)
    l_class = left.class
    r_class = right.class

    if left.nil? && r_class == String && right.empty? || right.nil? && l_class == String && left.empty?
      # undef vs. ''
      true
    elsif l_class <= Puppet::Pops::Types::PAnyType && r_class <= String || r_class <= Puppet::Pops::Types::PAnyType && l_class <= String
      # Type vs. Numeric (caused by uc bare word being a type and not a string)
      true
    elsif l_class <= Numeric && r_class <= String || r_class <= Numeric && l_class <= String
      # String vs. Numeric
      true
    else
      # hash, array, booleans and regexp, etc are only true if compared against same type - no difference between 3x. and 4.x
      # or this is a same type comparison (also the same in 3.x. and 4.x)
      false
    end
  end
  private :is_type_diff?

  def is_match_diff?(left, right)
    l_class = left.class
    r_class = right.class
    return l_class == Regexp && r_class != String || r_class == Regexp && l_class != String
  end
  private :is_match_diff?

  def report_in_expression(o)
    report(Issues::MIGRATE4_REVIEW_IN_EXPRESSION, o)
  end

  def report_array_last_in_block(o)
    return unless o.is_a?(Puppet::Pops::Model::LiteralList)
    report(Issues::MIGRATE4_ARRAY_LAST_IN_BLOCK, o)
  end
end