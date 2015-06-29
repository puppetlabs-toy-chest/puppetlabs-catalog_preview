[parser_config_38]: https://docs.puppetlabs.com/puppet/3.8/reference/config_file_environment.html#parser

#catalog_preview

#### Table of Contents

1. [Overview](#overview)
2. [Module Description - What the module does and why it is useful](#module-description)
3. [Setup - The basics of getting started with catalog_preview](#setup)
4. [Usage - Configuration options and additional functionality](#usage)
    * [Prerequisites](#prerequisites)
    * [puppet_preview command](#puppetpreview-command)
      * [Comparing environments](#comparing-environments)
      * [Validating a migration](#validating-a-migration)
      * [Checking backwards-compatible changes](#checking-backwardscompatible-changes)
      * [Viewing reports](#viewing-reports)
      * [Processing output](#processing-output)
    * [Usage Examples - Running catalog_preview](#examples)
5. [Options - Command line options for catalog_preview](#options)
6. [Help](#help)
7. [Limitations](#limitations)
8. [License and Copyright](#license-and-copyright)

##Overview

The catalog_preview module is a Puppet Enterprise-only module that provides catalog preview and migration features.

##Module Description

The primary purpose of the module is to serve as an aid for migration from the Puppet 3.x parser to the Puppet 4.x parser. The catalog_preview module compiles two catalogs, one in a *baseline environment*, using the current or 3.x parser, and one in a *preview environment*, using the 4.x or "future" parser. The module computes a diff between the two environments, and then saves the two catalogs, the diff, and the log output from each compilation for inspection. 

You'll point your preview environment at a branch of the environment you want to migrate, and then [configure][parser_config_38] the preview environment to use the 4.x ("future") parser. This way, backwards-incompatible changes can be made in the preview environment without affecting production. You can then use the diff, catalog, and log outputs provided by preview to make changes to the preview environment until you feel it is ready to move into production.

Other scenarios are supported in the same way. For example, the module's `puppet preview` command can help in various change management and refactoring scenarios. The baseline and preview environments can be any mix of future and current parser, allowing you to compare configurations even if you're not performing a 3.x to 4.x migration.

However, the `--migrate 3.8/4.0` option---which provides the specific migration checking that is the primary purpose of this module---can only be used when this module is used with a puppet <= 4.0.0 version and when the baseline environment is using current parser (3.x), and the preview environment is using future parser (4.x).

##Setup

###Requirements

To get started, you'll need:

* Puppet Enterprise, version 3.8.1 or greater, but less than version PE 2015.2 (if you are performing migration checking).
* Two environments:
  * Your current production environment, using the current (or Puppet 3 language) parser.
  * A preview environment, using the future (or Puppet 4 language) parser.

As mentioned above, when doing migration checking, your current production environment should be configured to use the current, or Puppet 3, parser. Your preview environment should be pointed at a branch of your current environment and configured to use the future, or Puppet 4, parser. Configure which parser each environment uses via the [`parser`][parser_config] setting in each environment's `environment.conf`.

Note that your PE version must be less than PE 2015.2 to use this tool. Because the future parser is the only parser available in PE 2015.2, no migration-specific check can be made.
 
###Installation

Install the catalog_preview module with `puppet module install puppetlabs-catalog_preview`.

##Usage

###Prerequisites

Before you perform a migration preview, you should:

* Address all deprecations in the production environment.
* Ensure that `stringify_facts` in puppet.conf is `false` on your agents. (In PE 3.8 and greater, `stringify_facts` defaults to 'false'.)

###Evaluating environments with the `puppet preview` command

####Comparing environments

The `puppet preview` command compiles, compares, and asserts a baseline catalog and a preview catalog for one or several node. This node must have checked in with the master at least one time prior to running `preview`, so that the node's facts are available to the master. The compilation of the baseline catalog takes place in the environment configured for the node (unless overridden with the option `--baseline_environment`). The compilation of the preview catalog takes place in the environment designated by `--preview_environment`. The following code will generate a preview for the preview environment named 'future_production' on the node 'mynode'.

~~~
puppet preview --preview_environment future_production mynode
~~~

####Validating a migration

When you run the preview compilation, you can turn on extra migration validation using `--migrate`. This turns on extra validations of future compatibility, flagging Puppet code that needs to be reviewed. This feature was introduced to help with the migration from the Puppet 3 parser to the Puppet 4 parser. To use this feature, `--preview_environment` must reference an environment configured to use the future parser in its `environment.conf`, while the baseline environment must be configured to use the current (Puppet 3) parser.

Note that the `--migrate 3.8/4.0` option is not available when using PE >= 4.0.0.

~~~
puppet preview --preview_environment future_production --migrate 3.8/4.0 mynode
~~~

####Checking backwards-compatible changes

By default, the compilation of the baseline catalog takes place in the environment configured for the node (usually this is "production"). Optionally, you can override the default baseline and set a specific baseline environment with `--baseline_environment`. If `--baseline_environment` is set, the node is first configured as directed by an external node classifier (ENC), and then the environment is switched to the `--baseline_environment`.

~~~
puppet preview --preview_environment future_production --baseline_environment my_baseline --migrate 3.8/4.0 mynode
~~~

The `--baseline_environment` option aids you when you're changing code in the preview environment for the purpose of making it work with the future parser, while the original environment is unchanged and configured with the Puppet 3 current parser.

If you want to make backwards-compatible changes in the preview environment (i.e., changes that work for **both** parsers), it's valuable to have a third environment configured. 

This third environment should have the same code as the preview environment, but it should be configured for the current parser. You can then diff between compilations in any two of the environments without having to modify the environment assigned by the ENC. This allows you to check your preview environment changes against the current production parser to make sure that they work. All other assignments made by the ENC are unchanged.

####Viewing reports

By default, the `puppet preview` command outputs a report of the compilation/differences between the two catalogs on 'stdout'. If compiling for a single node a summary report of the differences is displayed, and when compiling for multiple node the summary is an aggregate status report of catalog diff status per node.

This can be changed with [`--view`](#--view) to instead (for a single node) view one of the catalogs, the diff, or one of the compilation logs, or when compiling for multiple nodes, the `overview` report which correlates differences and issues across all nodes. Use the `--last` option with `--view` to view a result from the previous run obtained for one or several nodes instead of performing new compilations and diffs. Using `--last` without a list of nodes, uses the result obtain from all previous compilations.

View the log of one node:

`puppet preview --last mynode --view baseline_log`

View the aggregate/correlated overview for three nodes:

`puppet preview --last mynode1 mynode2 mynode3 --view overview`


####Processing output

All output (except reports intended for human use) is written in JSON format to allow further processing with tools like 'jq' (JSON query). The output is written to a subdirectory named after the node of the directory appointed
by the setting `preview_outputdir` (defaults to `$vardir/preview`):

|- "$preview_output-dir"
|  |
|  |- <NODE-NAME-1>
|  |  |- preview_catalog_.json
|  |  |- baseline_catalog.json
|  |  |- preview_log.json
|  |  |- baseline_log.json
|  |  |- catalog_diff.json
|  |  |- compilation_info.json
|  |  
|  |- <NODE-NAME-2>
|  |  |- ...

Each new invocation of the command for a given node overwrites the information already produced for that node.

The two catalogs are written in JSON compliant with a json-schema
('catalog.json'; the format used by Puppet to represent catalogs in JSON) viewable on stdout using `--schema catalog`.

The 'catalog_diff.json' file is written in JSON compliant with a json-schema viewable on stdout using `--schema catalog_delta`.

The two '*<type>*_log.json' files are written in JSON compliant with a json-schema viewable on stdout using `--schema log`.

The `compilation_info.json` is a catalog preview internal file.

####Understanding Migration Warnings

The Catalog Preview `--migration 3.8/4.0` options performs a number of migration checks
that may result as warnings with *issue codes*. These issue codes starting with `MIGRATE4_` are described in the following subsections. You will see these and other issue codes in logs and in the the overview report. (There are > 120 other issue codes currently in use in puppet - many that are
quite generic and requiring inspection of the associated message text to be meaningful. Such general puppet issue codes are currently not described anywhere).

#####MIGRATE4_EMPTY_STRING_TRUE (PUP-4124)

In Puppet 4.x. an empty `String` is considered to be `true`, while it was `false` in Puppet 3.x.
This migration check logs a warning with the issue code `MIGRATE4_EMPTY_STRING_TRUE` whenever
an empty string is evaluated in a context where it matters if it is `true` or `false`.
This means that you will not see warnings for all empty strings, just those that are used to
make decisions.

To fix these warnings, review the logic and consider the case of `undef` not being the same as
an empty string, and that empty strings are `true`.

#####MIGRATE4_UC_BAREWORD_IS_TYPE (PUP-4125)

In Puppet 4.x all bare words that start with an upper case letter is a reference to
a *Type* (a Data Type such as `Integer`, `String`, or `Array`, or a *Resource Type* such as `File`,
or `User`). In Puppet 3.x such upper case bare words were considered to be string
values, and only when appearing in certain locations would they be interpreted as
a reference to a type. The migration checker issues a warning for all upper case
bare words that are used in comparisons `==`, `>`, `<`, `>=`, `<=`, matches `=~` and `!~`, and when
used as `case` or selector `?{}` options.

To fix these warnings, quote the upper case bare word if a string is intended, (or alter
the logic to use the type system in the unlikely event that the 3.x. code did something in
relation to resource type name processing).

#####MIGRATE4_EQUALITY_TYPE_MISMATCH (PUP-4126)

In 4.x, comparison of `String` and `Number` is different than in 3.x.

~~~
'1' == 1 # 4x. false, 3x. true
'1' <= 1 # 4x. error, 3x. true
~~~

The migration checker logs a warning with the issue code `MIGRATE4_EQUALITY_TYPE_MISMATCH`
when a `String` and a `Numeric` are checked for equality.

To fix this, decide if values are best represented as strings or numbers. To convert a
string to a number simply add `0` to it. To convert a number to a string, either
interpolate it; `"$x"` (to convert it to a decimal number), or use the `sprintf`
function to convert it to octal, hex or a floating point notation. The `sprintf` function
has many options that control the string representation, upper/lower case letters in
hex numbers, prefix 0x, 0X, the precision of a floating point representation etc.

Also consider if input (fact, or parameter) should be a string or a number - that is a better fix than sprinkling data type conversions all over the code.

#####MIGRATE4_OPTION_TYPE_MISMATCH (PUP-4127)

In 4.x, `case` and selector `?{}` options are matched differently than in 3.x. In 3.x if the
match was not `true`, the match would be made with the operands converted to strings.
This means that 4.x logic can select a different (or no option) given the same input.

The migration checker logs a warning with the issue code `MIGRATE4_OPTION_TYPE_MISMATCH`
for every evaluated option that did not match because of a difference in type.

The fix for this depends on what the types of the test and option expressions
are - most likely number vs. string mismatch, and then the fix is the same as for
`MIGRATE4_EQUALITY_TYPE_MISMATCH`. For other type mismatches review the logic for what
was intended and make adjustments accordingly.

#####MIGRATE4_AMBIGUOUS_NUMBER (PUP-4129)

This migration check helps with unquoted numbers where strings are intended.

A common construct is to use values like `'01'`, `'02'` for ordering of resources. It is
also a common mistake to enter them as bare word numbers e.g. `01`, `02`. The difference
between 3.x and 4.x is that 3.x treats all bare word numbers as strings (unless arithmetic
is performed on them which produces numbers), whereas 4.x treats numbers as numbers from
the start.  The consequence in manifests using ordering is that 1, 100, 1000 comes
before 2, 200, and 2000 because the ordering converts the numbers back to strings without
leading zeros.

In 4.x. the leading zero means that the value is an octal number.

The migration checker logs a warning for every occurrence of octal, and hex numbers with
the issue code `MIGRATE4_AMBIGUOUS_NUMBER` in order to be able to find all places where the
value is used for ordering.

To fix these issues, review each occurrence and quote the values that represent "ordering", or
file mode (since file mode is a string value in 4.x).

#####MIGRATE4_AMBIGUOUS_FLOAT (PUP-4129)

This migration check helps with unquoted floating point numbers where strings are
intended.

Floating point values for arithmetic are not very commonly used in puppet. When seeing
something like `3.14`, it is most likely a version number string, and not someone doing
calculations with PI.

The migration checker logs a warning for every occurrence of floating point numbers with
the issue code `MIGRATE4_AMBIGUOUS_FLOAT` in order to be able to find all places where a
string may be intended.

#####Significant White Space/ MIGRATE4_ARRAY_LAST_IN_BLOCK (PUP-4128)

In 4.x. a white space between a value and a `[` means that the `[` signals the start
of an `Array` instead of being the start of an "at-index/key" operation. In 3.x. white
space is not significant. Most such places will lead to errors, but there are corner
cases - like in the example below:

~~~
if true {
  $a = File ['foo']
}
~~~

  Here 4.x will assign `File` (a resource type) to `$a` and then produce an array
  containing the string `'foo'`.

  The migration checker logs a warning with the issue code `MIGRATE4_ARRAY_LAST_IN_BLOCK`
  for such occurrences.

  To fix this, simply remove the white space.

#####MIGRATE4_REVIEW_IN_EXPRESSION (PUP-4130)

In 3.x the `in` operator was not well specified and there were several undefined behaviors.
This relates to, but is not limited to:

* string / numeric automatic conversions
* applying regular expressions to non string values causing auto conversion
* confusion over comparisons between empty string/undef/nil (internal) values
* in-operator not using case independent comparisons in 3.x

To fix, review the expectations against the puppet language specification.


####Working with multiple nodes

The `puppet preview` command can work with one or multiple nodes given on the command line. When more than one node is given, the operation is applied to all the given nodes. It is also possible to provide the list of nodes in a file by using the `--nodes filename` option. If the filename is `-` the input is read from preview's `stdin` (to enable piping them from some other command). Nodes can be given both on the command line and in a file - the combined set of nodes will be used. The file containing node names (or the content of stdout when using `-`) should be formatted with whitespace separating the node names.

`puppet preview --nodes nodesfile mynode`

Performs the operation on the nodes listed in 'nodesfile' and the given mynode.

###Usage Examples

To perform a full migration preview that exits with failure if catalogs are not equal:

~~~
puppet preview --preview_environment future_production --migrate 3.8/4.0 --assert=equal mynode
~~~
    
To perform a preview that exits with failure if preview catalog is not compliant:

~~~
puppet preview --preview_environment future_production --assert=compliant mynode
~~~

To perform a preview focusing on if code changes resulted in conflicts in resources of `File` type using 'jq' to filter the output (the command is given as one line):

~~~
puppet preview --preview_environment future_production --view diff mynode | jq -f '.conflicting_resources | map(select(.type == "File"))'
~~~

View the catalog schema:

~~~
puppet preview --schema catalog
~~~
  
View the catalog-diff schema:

~~~
puppet preview --schema catalog_diff
~~~
    
Run a diff (with the default summary view) then view the preview log:

~~~
puppet preview --preview_environment future_production mynode

puppet preview --preview_environment future_production mynode --view preview_log --last
~~~

The node name can be placed anywhere:

~~~
puppet preview mynode --preview_environment future_production
puppet preview --preview_environment future_production mynode 
~~~

Removing the data for all nodes that have equal or compliant catalogs:

~~~
puppet preview --last --view compliant_nodes | puppet preview --clean --nodes -
~~~

Removing all the data for all nodes:

~~~
puppet preview --clean --last
~~~

Running a compile, then focusing on compilation failures:

~~~
puppet preview --preview_environment future_production --nodes node_file --view failed_nodes > failed_nodes
puppet preview --last --view overview --nodes failed_nodes
~~~

Running a compile, then focusing on catalog diffs:

~~~
puppet preview --preview_environment future_production --nodes node_file --view diff_nodes > diff_nodes
puppet preview --last --view overview --nodes diff_nodes
~~~


###Options

The following command-line options are available for the `puppet preview` command.

#####`--assert`

Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview catalog is not compliant, instead of an exit with 0 to indicate that the preview run was successful in itself. Accepts the arguments `equal`, `compliant`.

#####`--baseline_environment 'ENV-NAME'`

Specifies the environment for the baseline compilation. This overrides the environment set for the node via an ENC. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from Puppet 3.x to Puppet 4.x, this environment's puppet.conf should be configured to use the current (3.x) parser. Note that the Puppet setting `--environment` **cannot** be used to achieve the same effect.

Also available in short form `--be ENV-NAME`.

#####`--excludes 'FILE'`

Adds resource diff exclusion of specified attributes to prevent them from being included in the diff. The excisions are specified in the given file in JSON as defined by the schema viewable with `--schema excludes`.

Preview will always exclude one PE specific File resource that has random content as it would otherwise always show up as different.

This option can be used to exclude additional resources that are expected to change in each
compilation (e.g. if they have random or time based content). Exclusions can be
per resource type, type and title, or combined with one or more attributes.

Note that `--excludes` is in effect when compiling and cannot be combined with
`--last`.


#####`--preview_environment 'ENV-NAME'`

Specifies the environment for the preview compilation. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from Puppet 3.x to Puppet 4.x, and using PE <= 4.0.0 this environment's `puppet.conf` should be configured to use the future (4.x) parser.

Also available in short form `--be ENV-NAME`.

#####`--debug`

Enables full debugging. Debugging output is sent to the respective log outputs for baseline and preview compilation. This option is for both compilations. Note that debugging information for the startup and end of the application itself is sent to the console.


#####`--diff_string_numeric`

Makes a difference in type between a string and a numeric value (that are equal numerically) be a conflicting diff. Can only be combined with `--migrate 3.8/4.0`. When `--migrate 3.8/4.0` is not specified, differences in type are always considered a conflicting diff. A type difference for the `mode` attribute in `File` will always be reported since this is a significant change.

#####`--help`

Prints a help message listing the options for the `puppet preview` command.

#####`--last`

Use the last result obtained for a node instead of performing new compilations and diff. Must be used along with the [`--view`](#--view) option. The command will operate on nodes given on the command line plus those given via [`--nodes`][#--nodes]. If used without any given nodes, this option will load information about all nodes for which there is preview output.


#####`--migrate 3.8/4.0`

Turns on migration validation for the preview compilation. Validation result is produced to the preview log file. When compiling for a single node (or using `--last` for a single node), the logs can optionally also be viewed on stdout with `--view preview_log`. 

When `--migrate 3.8/4.0` is on, values where one value is a string and the other numeric are considered equal if they represent the same number. This can be turned off with `--diff_string_numeric`, but turning this off might result in many conflicts being reported that need no action.

Migration of multiple nodes at the same time is best presented with `--view overview` as that correlates and aggregates found issues and presents information in a more actionable format.

For details about the migration specific warnings, see the DIAGNOSTICS section in the command's
`--help` output.

#####`NODE-NAME`

This specifies for which node the preview should produce output. The node must have previously requested a catalog from the master to make its facts available. It is possible to give multiple node names on the command line, via a file, or piping them to the command by using the [`--nodes`][#--nodes] option.

#####`--preview_outputdir 'DIR'`

Defines the directory to which output is produced. This is a Puppet setting that can be overridden on the command line (defaults to `$vardir/preview`).

#####`--schema`

Outputs the json-schema for the Puppet catalog, catalog_delta, excludes, or log. The option `help` will display the semantics of the catalog-diff schema. Can not be combined with any other option. Accepts arguments `catalog`, `catalog_delta`, `excludes`, `log`, `help`.

#####`--skip_tags`

Ignores comparison of tags, catalogs are considered equal/compliant if they only differ in tags.

#####`--trusted`

Makes trusted node data obtained from a fact terminus retain its authentication status of `"remote"`, `"local"`, or `false` (i.e., the authentication status the facts write request had). If this option is **not** in effect, any trusted node information is kept, and the authenticated key is set to false. The `--trusted` option is only available when running as root and should only be turned on when also trusting the fact-store.

#####`--version`

Prints the Puppet version number.

#####`--view` 

Specifies what will be output on stdout. Must be used with one of the following arguments:

* `summary`: The summary report of one catalog diff, or a summary per node if multiple are given
* `overview`: The correlated and aggregated report of issues/diffs for multiple nodes
* `overview_json`: The correlated and aggregated report of issues/diffs for multiple nodes in json format (experimental feature, the schema may change)
* `diff`: The catalog diff
* `baseline`: The baseline catalog
* `preview`: The preview catalog
* `baseline_log`: Outputs the baseline log
* `preview_log`: Outputs the preview log
* `status`: Compliance status
* `failed_nodes`: Outputs a list of nodes for which compilation failed
* `diff_nodes`: Outputs a list of nodes for which catalog diff found a difference
* `equal_nodes`: Outputs a list of nodes where catalogs had no diff
* `compliant_nodes`: Outputs a list of nodes where catalogs where equal or compliant
* `none`: No output

The outputs `diff`, `baseline`, `preview`, `baseline_log`, `preview_log` only works for a single node. All `--view` options may be combined with the [`--last`][#--last] option (to avoid recompilation).

#####`--verbose_diff`

Includes more information in the catalog diff such as attribute values in missing and added resources. Does not affect whether catalogs are considered equal or compliant.

#####`--clean`

Removes the generated files under the directory specified by the setting `preview_outputdir` for one or more given nodes from the filesystem. See [Processing output](#processing-output).

###Glossary

#####Baseline

The environment/catalog that is the stable base of the diff - what you compare against.

#####Preview

The environment/catalog that you compare against the baseline - i.e. where you make changes
until your catalogs are either [Equal](#equal-catalogs) or [Compliant](#compliant-catalogs).

#####Compliant (catalogs)

When comparing two catalogs, [Baseline](#baseline) vs. [Preview](#preview) the
preview catalog is considered to be **compliant** if it is a superset of the baseline.

That is; your preview catalog may contain additions, but neither removals nor conflicting changes, compared to the baseline.


#####Equal (catalogs)

When comparing two catalogs, [Baseline](#baseline) vs. [Preview](#preview) the
preview catalog is considered to be **equal** if it contains the same set of resources,
all attributes have the same (functionally equal) values, and the same set of edges/dependencies.

##Help

You can get help on the command line with:

~~~
puppet preview --help
~~~

You can also get help for the catalog-delta with:

~~~
puppet preview --schema help
~~~

##Limitations

The preview module requires a version of Puppet Enterprise version >= 3.8.0 < 5.0.0.
The `--migrate 3.8/4.0` option only works with Puppet Enterprise versions >= 3.8.0 < 4.0.0.

###License and Copyright

The content of this module is:

*Copyright (c) 2015 Puppet Labs, LLC Licensed under Puppet Labs Enterprise.*

