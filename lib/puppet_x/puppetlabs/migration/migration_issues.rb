# Migration issues produced by a MigrationChecker
#
module PuppetX::Puppetlabs::Migration::MigrationIssues

  # (see Puppet::Pops::Issues#issue)
  def self.issue (issue_code, *args, &block)
    Puppet::Pops::Issues.issue(issue_code, *args, &block)
  end

  MIGRATE4_AMBIGUOUS_INTEGER = issue :MIGRATE4_AMBIGUOUS_INTEGER, :value, :radix do
    formatted = sprintf("'%##{radix == 8 ? 'o' : 'x'}'", value)
    "This #{radix == 8 ? 'octal' : 'hex'} value evaluates to the decimal value '#{value}': Quote if the String #{formatted} was intended."
  end

  MIGRATE4_AMBIGUOUS_FLOAT = issue :MIGRATE4_AMBIGUOUS_FLOAT, :value do
    "This value evaluates to the imprecise floating point number #{value}: Quote if a String value was intended"
  end

  MIGRATE4_REVIEW_IN_EXPRESSION = issue :MIGRATE4_REVIEW_IN_EXPRESSION do
    'Please review the expectations of using this in-expression against the 4.x specification (3.x. evaluation is undefined for many corner cases)'
  end

  MIGRATE4_EMPTY_STRING_TRUE = issue :MIGRATE4_EMPTY_STRING_TRUE do
    'Empty string evaluated to true (3.x evaluates to false)'
  end

  MIGRATE4_UC_BAREWORD_IS_TYPE = issue :MIGRATE4_UC_BAREWORD_IS_TYPE, :type do
    "Upper cased non quoted word evaluates to the type '#{type}' (3.x evaluates to a String)"
  end

  MIGRATE4_EQUALITY_TYPE_MISMATCH = issue :MIGRATE4_EQUALITY_TYPE_MISMATCH, :left, :right do
    result = (semantic.operator == :'=='  ? 'false' : 'true')
    "#{label.the_uc(semantic)} evaluates to #{result} due to type mismatch between #{left.class} and #{right.class} (3.x. may evaluate differently)"
  end

  MIGRATE4_OPTION_TYPE_MISMATCH = issue :MIGRATE4_OPTION_TYPE_MISMATCH, :option_expr, :left, :right do
    # option_expr label results in Case Option, or Selector Option, the semantic is the match_expr (which is one of the value entries)
    # since that gives the line/pos for the match value as opposed for the entire option
    #
    "#{label.the_uc(option_expr)} was not selected due to type mismatch between '#{left.class}' and '#{right.class}' (3.x. may match if values in string form match)"
  end

  MIGRATE4_ARRAY_LAST_IN_BLOCK = issue :MIGRATE4_ARRAY_LAST_IN_BLOCK, :type do
    'The expression parsed to an Array (3.x parses this as an [] operation on the preceding value even if [] is preceded by white-space)'
  end
end
