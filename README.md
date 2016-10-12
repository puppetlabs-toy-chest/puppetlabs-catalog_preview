[parser_config_38]: https://docs.puppetlabs.com/puppet/3.8/reference/config_file_environment.html#parser
[pe_migration]: https://docs.puppetlabs.com/pe/latest/migrate_pe_catalog_preview.html

#catalog_preview

#### Table of Contents

1. [Overview](#overview)
2. [Module Description - What the module does and why it is useful](#module-description)
3. [Setup - The basics of getting started with catalog_preview](#setup)
    * [Requirements](#requirements)
    * [Installation](#installation)
4. [Usage - Functionality](#usage)
    * [Prerequisites](#prerequisites)
    * [Evaluating environments with `puppet_preview`](#evaluating-environments-with-puppetpreview)
      * [Compare environments](#compare-environments)
      * [Validate a migration](#validate-a-migration)
      * [Check backwards-compatible changes](#check-backwardscompatible-changes)
      * [View reports](#view-reports)
      * [Work with multiple nodes](#work-with-multiple-nodes)
    * [Usage Examples - Running catalog_preview](#usage-examples)
    * [Understanding results](#understanding-results)
      * [Process output](#process-output)
      * [Migration warnings](#migration-warnings)
5. [Options - Command line options for catalog_preview](#options)
6. [Help](#help)
7. [Limitations](#limitations)
8. [License and Copyright](#license-and-copyright)

##Overview

The catalog_preview module is a module that provides catalog preview and migration features.

##Module Description

The primary purpose of the module is to serve as an aid for migration from the Puppet 3 language parser to the Puppet 4 language parser. The catalog_preview module compiles two catalogs, one in a *baseline environment*, using the current or Puppet 3 parser, and one in a *preview environment*, using the Puppet 4 or "future" parser. The latter can be omitted in which case both compilations will compile the same environment. The module computes a diff between the two catalogs, and then saves them, the diff, and the log output from each compilation for inspection. 

You'll point your preview environment at a branch of the environment you want to migrate, and then [configure][parser_config_38] the preview environment to use the Puppet 4 ("future") parser. This way, backwards-incompatible changes can be made in the preview environment without affecting production. You can then use the diff, overview, catalog, and log outputs provided by preview to make changes to the preview environment until you feel it is ready to move into production.

Other scenarios are supported in the same way. For example, the module's `puppet preview` command can help in various change management and refactoring scenarios. The baseline and preview environments can be any mix of future and current parser, allowing you to compare configurations even if you're not performing a migration to the Puppet 4 language.

However, the `--migrate 3.8/4.0` option---which provides the specific migration checking that is the primary purpose of this module---can be used only when this module is used with a Puppet FOSS version < 4.0.0 or Puppet Enterprise < 2015.2 version, **and** when the baseline environment uses current parser (Puppet 3) and the preview environment uses future parser (Puppet 4). When no preview environment is given, the baseline environment will instead be compiled twice and the future parser will be enforced during the second compilation.

For a quick start guide on using this module to get ready to move from PE 3.8.1 to PE 2015.2, see [Preparing for Migration with catalog_preview][pe_migration] in the Puppet Enterprise docs.

##Setup

###Requirements

To get started, you'll need:

* Puppet Enterprise or Open-Source Puppet, version 3.8.1 or greater, but less than version PE2015.2 (if you are performing migration checking). If you are using Puppet FOSS, it must be version 3.8.1 or greater, but less than version 4.0.0 (for migration checking).
* (Either) Two environments (if you want to avoid modifying the production environment while fixing problems):
  * Your current production environment, using the current (or Puppet 3 language) parser.
  * A preview environment, using the future (or Puppet 4 language) parser.
* (Or) One environment (if you just want a quick preview, or is working in an environment where changes are ok):
  * Your current production environment, using the current (or Puppet 3 language) parser
  * Running preview commands with `--migrate38/4.0` without specifying `--preview-environment` 

As mentioned above, if you're performing a migration check, your current production environment should be configured to use the current, or Puppet 3, parser. Your preview environment should be pointed at a branch of your current environment and configured to use the future, or Puppet 4, parser. Configure which parser each environment uses via the [`parser`][parser_config_38] setting in each environment's `environment.conf`.

Note that your PE version must be **less than** PE 2015.2 to use this tool for previewing a migration. Because starting with 2015.2, PE contains only the "future" parser, if you are running 2015.2 or later, no migration-specific check can be made. If you are using the FOSS version, it must be less than 4.0.0.

For a quick start it is possible to use the same environment for the baseline and preview compilations by letting the
catalog preview tool do the switching to future parser for the preview compilation.

###Installation

Install the catalog_preview module with `puppet module install puppetlabs-catalog_preview`.

##Usage

###Prerequisites

Before you perform a migration preview, you should:

* Address all deprecations in the production environment.
* Ensure that `stringify_facts` in puppet.conf is 'false' on your agents. (In PE/FOSS 3.8 and greater, `stringify_facts` defaults to 'false'.)

###Evaluating environments with `puppet preview`

####Compare environments

The `puppet preview` command compiles, compares, and asserts a baseline catalog and a preview catalog for one or several nodes. This agent must have checked in with the master at least one time prior to running `preview`, so that the node's facts are available to the master. If this is a new agent, you can run `puppet agent -t` on the agent to have it check in with the master before you use `puppet preview`.

The compilation of the baseline catalog takes place in the environment configured for the node (unless overridden with the option `--baseline-environment`). The compilation of the preview catalog takes place in the environment designated by `--preview-environment`. The following code will generate a preview for the preview environment named 'future_production' on the node 'mynode':

~~~
puppet preview --preview-environment future_production mynode
~~~

####Validate a migration

When you run the preview compilation, you can turn on extra migration validation using `--migrate 3.8/4.0`. This turns on extra validations of future compatibility, flagging Puppet code that needs to be reviewed. This feature was introduced to help with the migration from the Puppet 3 parser to the Puppet 4 parser. The baseline environment must be configured to use the current (Puppet 3) parser and the `--preview-environment` must either reference an environment configured to use the future parser in its `environment.conf`, or it should not be given at all in which case the baseline environment will be compiled twice. Once with the Puppet 3 parser and once with the Puppet 4 parser.

Note that the `--migrate 3.8/4.0` option is not available when using PE >= 2015.2 or FOSS >= 4.0.0.

~~~
puppet preview --preview-environment future_production --migrate 3.8/4.0 mynode
~~~

When you perform a migration check with `--migration 3.8/4.0`, you might get some **issue codes**, such as these: 

~~~
Preview Warnings (by issue)
  MIGRATE4_EQUALITY_TYPE_MISMATCH (1)
    /opt/puppet/share/puppet/modules/puppet_enterprise/manifests/params.pp:158:26
  MIGRATE4_REVIEW_IN_EXPRESSION (1)
    /opt/puppet/share/puppet/modules/pe_concat/manifests/fragment.pp:93:20

~~~

These issue codes, which start with `MIGRATE4_`, are described in the [Migration Warnings](#migration-warnings) section below.

####Check backwards-compatible changes

By default, the compilation of the baseline catalog takes place in the environment configured for the node (usually this is "production"). Optionally, you can override the default baseline and set a specific baseline environment with `--baseline-environment`. If `--baseline-environment` is set, the node is first configured as directed by an external node classifier (ENC), and then the environment is switched to the `--baseline-environment`.

~~~
puppet preview --preview-environment future_production --baseline-environment my_baseline --migrate 3.8/4.0 mynode
~~~

The `--baseline-environment` and `--preview-environment` options aids you when you're changing code in the preview environment for the purpose of making it work with the future parser, while the original environment is unchanged and configured with the Puppet 3 current parser.

If you want to make backwards-compatible changes in the preview environment (that is, changes that work in **both** parsers), it's valuable to have a third environment configured. 

This third environment should have the same code as the preview environment, but it should be configured for the current parser. You can then diff between compilations in any two of the environments without having to modify the environment assigned by the ENC. This allows you to check your preview environment changes against the current production parser to make sure that they work. All other assignments made by the ENC are unchanged.

####View reports

By default, the `puppet preview` command outputs a report of the compilation/differences between the two catalogs on 'stdout'. If compiling for a single node, the summary report is of the differences; when compiling for multiple nodes, the summary is an aggregate status report of catalog diff status per node.

This can be changed with [`--view`](#--view). For a single node, you can view one of the catalogs, the diff, or one of the compilation logs; for multiple nodes, you can view the `overview` report, which correlates differences and issues across all nodes.

Use the [`--last`](#--last) option with `--view` to view a result from the previous run obtained for one or several nodes instead of performing new compilations and diffs. Using `--last` without a list of nodes uses the results from all previous compilations.

**View the log of one node:**

`puppet preview --last mynode --view baseline-log`

**View the aggregate/correlated overview for three nodes:**

`puppet preview --last mynode1 mynode2 mynode3 --view overview`

####Work with multiple nodes

The `puppet preview` command can work with one or multiple nodes given on the command line. When more than one node is given, the operation is applied to all the given nodes. It is also possible to provide the list of nodes in a file by using the `--nodes filename` option. If the filename is `-` the input is read from preview's `stdin` (to enable piping them from some other command). Nodes can be given both on the command line and in a file---the combined set of nodes will be used. The file containing node names (or the content of stdout when using `-`) should be formatted with whitespace separating the node names.

`puppet preview --nodes nodesfile mynode`

Performs the operation on the nodes listed in 'nodesfile' and the given mynode.

###Usage Examples

To perform a full migration preview that exits with failure if catalogs are not equal:

~~~
puppet preview --preview-environment future_production --migrate 3.8/4.0 --assert=equal mynode
~~~
    
To perform a preview that exits with failure if preview catalog is not compliant:

~~~
puppet preview --preview-environment future_production --assert=compliant mynode
~~~

To perform a preview focusing on if code changes resulted in conflicts in resources of `File` type using 'jq' to filter the output (the command is given as one line):

~~~
puppet preview --preview-environment future_production --view diff mynode | jq -f '.conflicting_resources | map(select(.type == "File"))'
~~~

To perform a full migration preview for multiple nodes using only one environment:

~~~
puppet preview --migrate 3.8/4.0 --view overview mynode1 mynode2 mynode3
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
puppet preview --preview-environment future_production mynode

puppet preview --preview-environment future_production mynode --view preview-log --last
~~~

The node name can be placed anywhere:

~~~
puppet preview mynode --preview-environment future_production
puppet preview --preview-environment future_production mynode 
~~~

Removing the data for all nodes that have equal or compliant catalogs:

~~~
puppet preview --last --view compliant-nodes | puppet preview --clean --nodes -
~~~

Removing all the data for all nodes:

~~~
puppet preview --clean --last
~~~

Running a compile, then focusing on compilation failures:

~~~
puppet preview --preview-environment future_production --nodes node_file --view failed-nodes > failed_nodes
puppet preview --last --view overview --nodes failed_nodes
~~~

Running a compile, then focusing on catalog diffs:

~~~
puppet preview --preview-environment future_production --nodes node_file --view diff-nodes > diff_nodes
puppet preview --last --view overview --nodes diff_nodes
~~~

###Understanding output and results

####Process output

All output (except reports intended for human use) is written in JSON format to allow further processing with tools like 'jq' (JSON query). The output is written to a subdirectory named after the node of the directory appointed
by the setting `preview_outputdir` (defaults to `$vardir/preview`):

~~~
|- "$preview_output_dir"
|  |
|  |- <NODE-NAME-1>
|  |  |- preview_catalog.json
|  |  |- baseline_catalog.json
|  |  |- preview_log.json
|  |  |- baseline_log.json
|  |  |- catalog_diff.json
|  |  |- compilation_info.json
|  |  
|  |- <NODE-NAME-2>
|  |  |- ...
~~~

Each new invocation of the command for a given node overwrites the information already produced for that node.

The two catalogs are written in JSON compliant with a json-schema
('catalog.json', the format used by Puppet to represent catalogs in JSON) viewable on stdout using `--schema catalog`.

The 'catalog_diff.json' file is written in JSON compliant with a json-schema viewable on stdout using `--schema catalog_delta`.

The two '*<type>*_log.json' files are written in JSON compliant with a json-schema viewable on stdout using `--schema log`.

The `compilation_info.json` is a catalog preview internal file.

####Migration Warnings

The catalog_preview `--migration 3.8/4.0` option performs a number of migration checks
that might result as warnings with *issue codes*. These issue codes starting with `MIGRATE4_` are described below. You will see these and other issue codes both in logs and in the overview report. (There are more than 120 other issue codes currently in use in Puppet---many of these are generic and require inspection of the associated message text to be meaningful. Such general Puppet issue codes are currently not described anywhere.)

#####MIGRATE4_EMPTY_STRING_TRUE

In Puppet 4, an empty `String` is considered to be `true`, while it was `false` in Puppet 3. This migration check logs a warning with the issue code `MIGRATE4_EMPTY_STRING_TRUE` whenever an empty string is evaluated in a context where it matters if it is `true` or `false`. This means that you will not see warnings for all empty strings, just those that are used to make decisions.

To fix these warnings, review the logic and consider the case of `undef` not being the same as an empty string, and that empty strings are `true`.

For a detailed description of this issue, see [PUP-4124](https://tickets.puppetlabs.com/browse/PUP-4124).

#####MIGRATE4_UC_BAREWORD_IS_TYPE

In Puppet 4, all bare words that start with an upper case letter are a reference to
a *Type* (a Data Type such as `Integer`, `String`, or `Array`, or a *Resource Type* such as `File` or `User`). In Puppet 3, such upper case bare words were considered to be string
values, and only in certain locations would they be interpreted as
a reference to a type. The migration checker issues a warning for all upper case
bare words that are used in comparisons `==`, `>`, `<`, `>=`, `<=`, matches `=~` and `!~`, and when used as `case` or selector `?{}` options.

To fix these warnings, quote the upper case bare word if a string is intended. 

In the unlikely event that the Puppet 3 code did something in relation to resource type name processing, alter the logic to use the type system.

For a detailed description of this issue, see [PUP-4125](https://tickets.puppetlabs.com/browse/PUP-4125).

#####MIGRATE4_EQUALITY_TYPE_MISMATCH

In Puppet 4, comparison of `String` and `Number` is different than it was in Puppet 3.

~~~
'1' == 1 # 4x. false, 3x. true
'1' <= 1 # 4x. error, 3x. true
~~~

The migration checker logs a warning with the issue code `MIGRATE4_EQUALITY_TYPE_MISMATCH`
when a `String` and a `Numeric` are checked for equality.

To fix this, decide if values are best represented as strings or numbers. To convert a
string to a number simply add a leading `0` to it. To convert a number to a string, either
interpolate it; `"$x"` (to convert it to a decimal number), or use the `sprintf`
function to convert it to octal, hex or a floating point notation. The `sprintf` function
has many options that control the string representation, upper/lower case letters in
hex numbers, prefix 0x, 0X, the precision of a floating point representation, etc.

Also consider whether input (fact or parameter) should be a string or a number---that is a better fix than sprinkling data type conversions all over the code.

For a detailed description of this issue, see [PUP-4126](https://tickets.puppetlabs.com/browse/PUP-4126).

#####MIGRATE4_OPTION_TYPE_MISMATCH

In Puppet 4, `case` and selector `?{}` options are matched differently than in Puppet 3. In Puppet 3, if the match was not `true`, the match was made with the operands converted to strings. This means that Puppet 4 logic can select a different option (or none) given the same input.

The migration checker logs a warning with the issue code `MIGRATE4_OPTION_TYPE_MISMATCH`
for every evaluated option that did not match because of a difference in type.

The fix for this depends on what the types of the test and option expressions
are. The most likely issue is a number vs. string mismatch, and then the fix is the same as for `MIGRATE4_EQUALITY_TYPE_MISMATCH`. For other type mismatches, review the logic for what was intended and make adjustments accordingly.

For a detailed description of this issue, see [PUP-4127](https://tickets.puppetlabs.com/browse/PUP-4127).

#####MIGRATE4_AMBIGUOUS_NUMBER

This migration check helps with unquoted numbers where strings are intended.

A common construct is to use values like `'01'`, `'02'` for ordering of resources. It is
also a common mistake to enter them as bare word numbers, e.g. `01`, `02`. The difference
between Puppet 3 and Puppet 4 is that 3 treats all bare word numbers as strings (unless arithmetic that produces numbers is performed), whereas Puppet 4 treats numbers as numbers from the start. The consequence in manifests using ordering is that 1, 100, 1000 comes
before 2, 200, and 2000 because the ordering converts the numbers back to strings without
leading zeros.

In Puppet 4, the leading zero means that the value is an octal number.

The migration checker logs a warning for every occurrence of octal, and hex numbers with
the issue code `MIGRATE4_AMBIGUOUS_NUMBER` in order to be able to find all places where the value is used for ordering.

To fix these issues, review each occurrence and quote the values that represent "ordering", or file mode (since file mode is a string value in Puppet 4).

For a detailed description of this issue, see [PUP-4129](https://tickets.puppetlabs.com/browse/PUP-4129).

#####MIGRATE4_AMBIGUOUS_FLOAT

This migration check helps with unquoted floating point numbers where strings are
intended.

Floating point values for arithmetic are not very commonly used in Puppet. When seeing
something like `3.14`, it is most likely a version number string, not someone doing
calculations with PI.

The migration checker logs a warning for every occurrence of floating point numbers with
the issue code `MIGRATE4_AMBIGUOUS_FLOAT` in order to find all places where a string might be intended.

For a detailed description of this issue, see [PUP-4129](https://tickets.puppetlabs.com/browse/PUP-4129).

#####Significant White Space/ MIGRATE4_ARRAY_LAST_IN_BLOCK

In Puppet 4, a white space between a value and a `[` means that the `[` signals the start
of an `Array`, instead of being the start of an "at-index/key" operation. In Puppet 3, white space is not significant. Most such places will lead to errors, but there are corner
cases, such as in the example below:

~~~
if true {
  $a = File ['foo']
}
~~~

Here, Puppet 4 will assign `File` (a resource type) to `$a` and then produce an array containing the string `'foo'`.

The migration checker logs a warning with the issue code `MIGRATE4_ARRAY_LAST_IN_BLOCK` for such occurrences.

To fix this, remove the white space.

For a detailed description of this issue, see [PUP-4128](https://tickets.puppetlabs.com/browse/PUP-4128).

#####MIGRATE4_REVIEW_IN_EXPRESSION

In Puppet 3, the `in` operator was not well specified and there were several undefined behaviors. This relates to, but is not limited to:

* String / numeric automatic conversions.
* Applying regular expressions to non string values causing auto conversion.
* Confusion over comparisons between empty string/undef/nil (internal) values.
* In-operator not using case independent comparisons in Puppet 3.

To fix, review the expectations against the Puppet language specification.

For a detailed description of this issue, see [PUP-4130](https://tickets.puppetlabs.com/browse/PUP-4130).

###Options

The following command-line options are available for the `puppet preview` command.

#####`--assert`

Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview catalog is not compliant, instead of an exit with 0 to indicate that the preview run was successful in itself. Accepts the arguments `equal`, `compliant`.

#####`--baseline-environment 'ENV-NAME'`

Specifies the environment for the baseline compilation. This overrides the environment set for the node via an ENC. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from Puppet 3.x to Puppet 4.x, this environment's puppet.conf should be configured to use the current (3.x) parser. Note that the Puppet setting `--environment` **cannot** be used to achieve the same effect.

Also available in short form `--be ENV-NAME`.

#####`--excludes 'FILE'`

Adds resource diff exclusion of specified attributes to prevent them from being included in the diff. The excisions are specified in the given file in JSON as defined by the schema viewable with `--schema excludes`.

Preview always excludes one PE-specific File resource that has random content; otherwise, it would always show up as different.

This option can be used to exclude additional resources that are expected to change in each compilation (e.g. if they have random or time-based content). Exclusions can be
per resource type, type and title, or combined with one or more attributes.

An exclusion that isn't combined with any attributes will exclude matching resources completely together with all edges where the resource is either the source or the target.

Note that `--excludes` is in effect when compiling and cannot be combined with
`--last`.

#####`--preview-environment 'ENV-NAME'`

Specifies the environment for the preview compilation. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from the Puppet 3 language to the Puppet 4 language, and using PE <= 2015.2, this environment's `puppet.conf` should be configured to use the future (Puppet 4) parser.

Also available in short form `--pe ENV-NAME`.

#####`--debug`

Enables full debugging. Debugging output is sent to the respective log outputs for baseline and preview compilation. This option is for both compilations. Note that debugging information for the startup and end of the application itself is sent to the console.

#####`--[no-]diff-string-numeric`

Makes a difference in type between a string and a numeric value (that are equal numerically) be a conflicting diff. A type difference for the `mode` attribute in `File` will always be reported since this is a significant change. If the option is prefixed with `no-`, then a difference in type will be ignored. This option can only be combined with `--migrate 3.8/4.0` and will then default to `--no-diff-string-numeric`. The behavior for other types of conversions is always equivalent to `--diff-string-numeric`

#####`--[no-]diff-array-value`

A value in the baseline catalog that is compared to a one element array containing that value in the preview catalog is normally considered a conflict. Using `--no-diff-array-value` will prevent this conflict from being reported. This option can only be combined with `--migrate 3.8/4.0` and will default to `--diff-array-value`. The behavior for other types of conversions is always equivalent to `--diff-array-value`.

#####`--help`

Prints a help message listing the options for the `puppet preview` command.

#####`--last`

Use the last result obtained for a node instead of performing new compilations and diff. Must be used along with the [`--view`](#--view) option. The command will operate on nodes given on the command line plus those given via [`--nodes`](#--nodes). If used without any given nodes, this option will load information about all nodes for which there is preview output.

#####`--migrate 3.8/4.0`

Turns on migration validation for the preview compilation. Validation result is produced to the preview log file. When compiling for a single node (or using `--last` for a single node), the logs can optionally also be viewed on stdout with `--view preview-log`.

If no `--preview-environment` is specified the baseline environment will be used also for the preview compilation but with the
`--parser` setting automatically set to `future`.

When `--migrate 3.8/4.0` is on, values where one value is a string and the other numeric are considered equal if they represent the same number. This can be turned off with `--diff-string-numeric`, but turning this off might result in many conflicts being reported that need no action.

Migration of multiple nodes at the same time is best presented with `--view overview` as that correlates and aggregates found issues and presents information in a more actionable format.

For details about the migration specific warnings, see the DIAGNOSTICS section in the command's `--help` output.

#####`NODE-NAME`

This specifies for which node the preview should produce output. The node must have previously requested a catalog from the master to make its facts available. It is possible to give multiple node names on the command line, via a file, or piping them to the command by using the [`--nodes`](#--nodes) option.

#####`--preview-outputdir 'DIR'`

Defines the directory to which output is produced. This is a Puppet setting that can be overridden on the command line (defaults to `$vardir/preview`).

#####`--schema`

Outputs the json-schema for the Puppet catalog, catalog_delta, excludes, or log. The option `help` will display the semantics of the catalog-diff schema. Can not be combined with any other option. Accepts arguments `catalog`, `catalog_delta`, `excludes`, `log`, `help`.

#####`--[no-]skip-tags`

Ignores (skips) comparison of tags, catalogs are considered equal/compliant if they only differ in tags. If the option is prefixed with `no-`, then tags will be included in the comparison. The default is `--no-skip-tags`.

#####`--version`

Prints the Puppet version number.

#####`--view` 

Specifies what will be output on stdout. Must be used with one of the following arguments:

* `summary`: The summary report of one catalog diff, or a summary per node if multiple are given.S
* `overview`: The correlated and aggregated report of issues/diffs for multiple nodes.
* `overview-json`: The correlated and aggregated report of issues/diffs for multiple nodes in json format (experimental feature, the schema may change).
* `diff`: The catalog diff.
* `baseline`: The baseline catalog.
* `preview`: The preview catalog.
* `baseline-log`: Outputs the baseline log.
* `preview-log`: Outputs the preview log.
* `status`: Compliance status.
* `failed-nodes`: Outputs a list of nodes for which compilation failed.
* `diff-nodes`: Outputs a list of nodes for which catalog diff found a difference.
* `equal-nodes`: Outputs a list of nodes where catalogs had no diff.
* `compliant-nodes`: Outputs a list of nodes where catalogs where equal or compliant.
* `none`: No output.

The outputs `diff`, `baseline`, `preview`, `baseline-log`, `preview-log` only works for a single node.
The output `overview` can be combined with the option [`--[no-]report-all`](#--[no-]report-all) option.
All `--view` options may be combined with the [`--last`](#--last) option (to avoid recompilation).

#####`--[no-]report-all`
Controls if the `overview` report will contain a list of nodes that is limited to the ten nodes with the highest number of issues or if all nodes are included in the list. The default is to only include the top ten nodes. This option can only be used together with with `--view overview`.

#####`--[no-]verbose-diff`

Includes more information in the catalog diff such as attribute values in missing and added resources. Does not affect whether catalogs are considered equal or compliant. The default is `--no-verbose-diff`.

#####`--clean`

Removes the generated files under the directory specified by the setting `preview-outputdir` for one or more given nodes from the filesystem. See [Processing output](#processing-output).

###Glossary

#####Baseline

The environment/catalog that is the stable base of the diff. This is what you compare your changed environment against.

#####Preview

The environment/catalog that you compare against the baseline. This is where you make changes until your catalogs are either [Equal](#equal-catalogs) or [Compliant](#compliant-catalogs).

#####Compliant (catalogs)

When comparing two catalogs, [Baseline](#baseline) vs. [Preview](#preview), the
preview catalog is considered to be **compliant** if it is a superset of the baseline.

That is, your preview catalog can contain additions, but no removals or conflicting changes, compared to the baseline.


#####Equal (catalogs)

When comparing two catalogs, [Baseline](#baseline) vs. [Preview](#preview), the
preview catalog is considered to be **equal** if it contains the same set of resources, the same set of edges/dependencies, and all attributes have the same (functionally equal) values. 

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

The preview module requires a version of Puppet or Puppet Enterprise version >= 3.8.1.
The `--migrate 3.8/4.0` option only works with Puppet Enterprise versions >= 3.8.1 < 2015.2, or Open Source Puppet >= 3.8.1 and < 4.0.

###License and Copyright

The content of this module is:

*Copyright (c) 2015-2016 Puppet, LLC Licensed under Apache 2.0.*

## MAINTAINERS

* Thomas Hallgren
* Henrik Lindberg
