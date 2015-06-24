puppet-preview(8) -- Puppet catalog preview compiler
========

SYNOPSIS
--------
Compiles two catalogs for one or more nodes: one catalog in the baseline environment and one in a preview environment and computes a diff between the two. Produces the two catalogs, the diff, and
the logs from each compilation for each node and then summaries/aggregates and correlates found issues in various views of the produced information.

USAGE
-----
```
puppet preview [
    [--assert equal|compliant]
    [-d|--debug]
    [-l|--last]
    [--clean]
    [-m <MIGRATION>|--migrate <MIGRATION> [--diff_string_numeric]]
    [--preview_outputdir <PATH-TO-OUTPUT-DIR>]
    [--skip_tags]
    |--excludes <PATH-TO-EXCLUSIONS-FILE>]
    [--view summary|overview|overview_json|baseline|preview|diff|baseline_log|preview_log|none|
    failed_nodes|diff_nodes|compliant_nodes|equal_nodes]
    [-vd|--verbose_diff]
    [--trusted]
    [--baseline_environment <ENV-NAME> | --be <ENV-NAME>]
    --preview_environment <ENV-NAME> | --pe <ENV-NAME>
    <NODE-NAME>+ | --nodes <FILE> <NODE_NAME>*
  ]|[--schema catalog|catalog_delta|excludes|log|help]
   |[-h|--help]
   |[-V|--version]
```

DESCRIPTION
-----------
This command compiles, compares, and asserts a baseline catalog and a preview catalog
for one or several node(s) that has previously requested a catalog from a puppet master
(thereby making the node's facts available). The compilation of the baseline catalog takes
place in the environment configured for each given node (optionally overridden
with '--baseline_environment'). The compilation of the preview takes place in the environment
designated by '--preview_environment'.

If '--baseline_environment' is set, a node will first be configured as directed by
an ENC, the environment is then switched to the '--baseline_environment'.
The '--baseline_environment' option is intended to aid when changing code in the
preview environment (for the purpose of making it work with the future parser) while
the original environment is unchanged and is configured with the 3.x current parser
(i.e. what is in 'production').
If the intent is to make backwards compatible changes in the preview
environment (i.e. changes that work for both parsers) it is of value to have yet another
environment configured for current (3.x) parser where the same code as in the preview
environment is checked out. It is then simple to diff between compilations in any two
environments without having to modify the environment assigned by the ENC. All other
assignments made by the ENC are unchanged.

By default the command outputs a summary report of the difference between the two catalogs on 'stdout' if the command operates on a single node, and outputs an summary per node when the
command operates on multiple nodes. The output for a single node can be changed with '--view'
to instead view one of the catalogs, the diff, or one of the compilation logs. For
multiple nodes --view overview produces and overview of aggregated and correlated
differences and issues. 

Use the '--last' option to view one of the results from the last preview compilation
instead of again compiling and computing a diff. Note that '--last' reload the information
produced for a given set of nodes in earlier runs.

When the preview compilation is performed, it is possible to turn on extra
migration validation using '--migrate 3.8/4.0'. This will turn on extra validations
of future compatibility flagging puppet code that needs to be reviewed. This
feature was introduced to help with the migration from puppet 3.x to puppet 4.x.
and requires that the '--preview_envenvironment' references an environment configured
to use the future parser in its environment.conf.

The wanted kind of migration checks to perform must be given with the '--migrate' option.
This version of preview support the migration kind '3.8/4.0'. The version of Puppet used
with this version of preview must also support this migration kind (which Puppet does between the versions >= 3.8.0 and < 4.0.0 does). Newer versions of Puppet may contain additional
new migration strategies.

All output (except the summary/status and overview reports intended for human use) is written in
JSON format to allow further processing with tools like 'jq' (JSON query).

The output is written to a subdirectory named after the node of the directory appointed
by the setting 'preview_outputdir' (defaults to '$vardir/preview'):

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

Each new invocation of the command for a given node overwrites the information
already produced for that node.

The two catalogs are written in JSON compliant with a json-schema
('catalog.json'; the format used by puppet to represent catalogs in JSON)
viewable on stdout using '--schema catalog'

The 'catalog_diff.json' file is written in JSON compliant with a json-schema
viewable on stdout using '--schema catalog_delta'.

The two '<type>_log.json' files are written in JSON compliant with a json-schema
viewable on stdout using '--schema log'.

The 'compilation_info.json' is a catalog preview internal file.

SETUP
-----
* Include this (the catalog-preview) module in the puppet configuration
* Create an environment in which the preview compilation should take place (the version
  of the source and the version of the environment configuration you want to diff against
  your baseline) and checkout the this code in the preview environment.
  (The same version as for the baseline if doing a migration check preview).
* When using preview to migrate from 3.8 to 4.0 configure the baseline environment to use
  the current parser, and the preview to use the future environment. (This is specific to
  puppet versions >= 3.8 <= 4.0.0), see:
    https://docs.puppetlabs.com/puppet/3.8/reference/config_file_environment.html#parser
  for information about the parser setting).
* Run preview for one or multiple nodes that have already checked in with the master
* Slice and dice the information to find problems

OPTIONS
-------

Note that all settings (such as 'log_level') affect both compilations.

* --debug:
  Enables full debugging. Debugging output is sent to the respective log outputs
  for baseline and preview compilation. This option is for both compilations.
  Note that debugging information for the startup and end of the application
  itself is sent to the console.

* --help:
  Prints this help message.

* --version:
  Prints the puppet version number and exit.

* --preview_environment <ENV-NAME> | --pe <ENV-NAME>
  Makes the preview compilation take place in the given <ENV-NAME>.
  Uses facts obtained from the configured facts terminus to compile the catalog.

* --baseline_environment <ENV-NAME> | --be <ENV-NAME>
  Makes the baseline compilation take place in the given <ENV-NAME>. This overrides
  the environment set for the node via an ENC.
  Uses facts obtained from the configured facts terminus to compile the catalog.
  Note that the puppet setting '-environment' cannot be used to achieve the same effect.

* --view <REPORT>
  Specifies what will be output on stdout;

  | REPORT          | Output
  | --------------- | ----------------------------------------------------------------------
  | summary         | A single node diff summary, or the status per node  
  | diff            | The catalog diff for one node in json format  
  | baseline        | The baseline catalog for one node in json
  | preview         | The preview catalog for one node in json
  | baseline_log    | The baseline log for one node in json
  | preview_log     | The preview log for one node in json
  | status          | Short compliance status output for one or multiple nodes
  | none            | No output, useful when using preview as a test of exit code in a script
  | overview        | Aggregated & correlated report of errors/warnings/diffs across nodes
  | overview_json   | (Experimental) The overview output in json format
  | failed_nodes    | A list of nodes where compilation of the two catalogs failed
  | diff_nodes      | A list of nodes where there are diffs in the two catalogs
  | compliant_nodes | A list of nodes that have catalogs that are equal, or with compliant diffs
  | equal_nodes     | A list of nodes where catalogs where equal


  The 'overview' report is intended to be the most informative in terms of answering "what
  problems do I have in my catalogs, and where does the problem originate/where can I fix it"?

  The reports 'status' and 'summary' are intended to be brief information for human consumption
  to understand the outcome of running a preview command.

  The 'xxx_nodes' reports are intended to be used for saving to a file and using it
  to selectively clean information or focus the next run on those nodes (i.e. the file is
  given as an argument to --nodes in the next run of the command).

  The 'diff', 'baseline', 'preview', 'baseline_log', and 'preview_log' reports are intended
  to provide drill down into the details and for being able to pipe the information to custom
  commands that further process the output.

  The 'overview_json' is "all the data" and it is used as the basis for the 'overview' report.
  The fact that it contains "all the data" means it can be used to produce other views of the 
  results across a set of nodes without having to load and interpret the output for each node
  from the file system.
  It is marked as experimental, and its schema is not documented in this version of catalog preview 
  as it may need adjustments in minor version updates. The intent is to document this in a
  subsequent release and that this report can be piped to custom commands, or to visualizers
  that can slice and dice the information.

* --migrate <MIGRATION>
  Turns on migration validation for the preview compilation. Validation result
  is produced to the preview log file or optionally to stdout with '--view preview_log'.
  When --migrate is on, values where one value is a string and the other numeric
  are considered equal if they represent the same number. This can be turned off
  with --diff_string_numeric, but turning this off may result in many conflicts
  being reported that need no action. The <MIGRATION> value is required. Currently only
  '3.8/4.0' which requires a Puppet version between >= 3.8.0 and < 4.0.0. The preview module
  may be used with versions >= 4.0.0, but can then not accept the '3.8/4.0' migration.

* --diff_string_numeric
  Makes a difference in type between a string and a numeric value (that are equal numerically)
  be a conflicting diff. Can only be combined with '--migrate 3.8/4.0'. A type difference
  for the `mode` attribute in `File` will always be reported since this is a significant change.

* --assert equal | compliant
  Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview
  catalog is not compliant instead of an exit with 0 to indicate that the preview run
  was successful in itself. 

* --preview_outputdir <DIR>
  Defines the directory to which output is produced.
  This is a puppet setting that can be overridden on the command line.

* <NODE-NAME>+
  This specifies for which node the preview should produce output. The node must
  have previously requested a catalog from the master to make its facts available.
  At least one node name must be specified (unless '--last' is used to load all available
  already produced information), either given on the command line or
  via the '--nodes' option.

* --schema catalog | catalog_delta | excludes | log | help
  Outputs the json-schema for the puppet catalog, catalog_delta, exclusions, or log. The option
  'help' will display the semantics of the catalog-diff schema. Can not be combined with
  any other option.

* --skip_tags
  Ignores comparison of tags, catalogs are considered equal/compliant if they only
  differ in tags.

* --excludes <FILE>
  Adds resource diff exclusion of specified attributes (resource type and title specific) to
  prevent them from being included in the diff. The excusions are specified in the given
  file in JSON as defined by the schmea viewable with '--schema excludes'.

  Preview will always exclude one PE specific File resource that has random content as it
  would otherwise always show up as different.
  This option can be used to exclude additional resources that are expected to change in each
  compilation (e.g. if they have random or time based content).

  Note that '--excludes' is in effect when compiling and cannot be combined with
  '--last'.

* --trusted
  Makes trusted node data obtained from a fact terminus retain its authentication
  status of "remote", "local", or false (the authentication status the write request had).
  If this option is not in effect, any trusted node information is kept, and the
  authenticated key is set to false. The --trusted option is only available when running
  as root, and should only be turned on when also trusting the facts store.

* --verbose_diff
  Includes more information in the catalog diff such as attribute values in
  missing and added resources. Does not affect if catalogs are considered equal or
  compliant.

* --last
  Uses the already produced catalogs/diffs and logs for the given node(s) instead
  of performing new compilations and diff. If used without any given nodes, all
  already produced information will be loaded.
  (Also see '--clean' for how to remove produced information).

* --nodes <FILE>
  Specifies a file to read node-names from. If the file name is '-' file names are read
  from standard in. Each white-space separated sequence of characters is taken as a node name.
  This may be combined with additional nodes given on the command line. Duplicate entries (in given  
  file, or on command line) are skipped.


EXAMPLE
-------
To perform a full migration preview for multiple nodes:

    puppet preview --pe future_production --migrate 3.8/4.0 --view overview mynode1 mynode2 mynode3

To perform a full migration preview that exits with failure if catalogs are not equal:

    puppet preview --pe future_production --migrate 3.8/4.0 --assert=equal mynode
    
To perform a preview that exits with failure if preview catalog is not compliant:

    puppet preview --pe future_production --assert=compliant mynode

To perform a preview focusing on if code changes resulted in conflicts in
resources of File type using 'jq' to filter the output (the command is given as one line):

    puppet preview --pe future_production --view diff mynode 
    | jq -f '.conflicting_resources | map(select(.type == "File"))'

View the catalog schema:

    puppet preview --schema catalog

View the catalog-diff schema:

    puppet preview --schema catalog_diff

Run a diff (with the default summary view) then view the preview log:

    puppet preview --pe future_production mynode
    puppet preview --pe future_production mynode --view preview_log --last

Node name can be placed anywhere:

    puppet preview mynode --pe future_production
    puppet preview --pe future_production mynode

Run a migration check, then view a report that only includes failed nodes:

    puppet preview --pe future_production --migrate 3.8/4.0 --view none mynode1 mynode2 mynode3
    puppet preview --view failed_nodes --last > tmpfile
    puppet preview --view overview --last --nodes tmpfile

DIAGNOSTICS
-----------
The '--assert' option controls the exit code of the command.

If '--assert' is not specified the command will exit with 0 if the two compilations
succeeded, 2 if the baseline compilation failed (a catalog could not be produced), 
and 3 if the preview compilation did not produce a catalog. Files not produced may
either not exist, or be empty.

If '--assert' is set to 'equal', the command will exit with 4 if the two catalogs
are not equal.

If '--assert' is set to 'compliant' it will exit with 5 if the content of the
baseline catalog is not a subset of the content of the preview catalog.

The different assert values do not alter what is produced - only the exit value is
different as both equality and compliance is checked in every preview.

The command exits with 1 if there is a general error.

MIGRATION WARNINGS
------------------

The Catalog Preview --migration 3.8/4.0 options performs the following migration checks
(see the related ticket numbers for additional details/examples). The labels MIGRATE4_...
are the issue codes that are found in the preview_log.json for reported migration warnings.

** MIGRATE4_EMPTY_STRING_TRUE (PUP-4124) **:

  In Puppet 4.x. an empty String is considered to be true, while it was false in Puppet 3.x.
  This migration check logs a warning with the issue code MIGRATE4_EMPTY_STRING_TRUE whenever
  an empty string is evaluated in a context where it matters if it is true or false.
  This means that you will not see warnings for all empty strings, just those that are used to
  make decisions.

  To fix these warnings, review the logic and consider the case of undef not being the same as
  an empty string, and that empty strings are true.

** MIGRATE4_UC_BAREWORD_IS_TYPE (PUP-4125) **:

  In Puppet 4.x all bare words that start with an upper case letter is a reference to
  a Type (Data Type such as Integer, String, or Array, or a Resource Type such as File,
  or User). In Puppet 3.x such upper case bare words were considered to be string
  values, and only when appearing in certain locations would they be interpreted as
  a reference to a type. The migration checker issues a warning for all upper case
  bare words that are used in comparisons ==, >, <, >=, <=, matches =~ and !~, and when
  used as case or selector options.

  To fix these warnings, quote the upper case bare word if a string is intended, (or alter
  the logic to use the type system in the unlikely event that the .3x. code did something in
  relation to resource type name processing).

** MIGRATE4_EQUALITY_TYPE_MISMATCH (PUP-4126) **:

  In 4.x, comparison of String and Number is different than in 3.x.

    '1' == 1 # 4x. false, 3x. true
    '1' <= 1 # 4x. error, 3x. true


  The migration checker logs a warning with the issue code MIGRATE4_EQUALITY_TYPE_MISMATCH
  when a String and a Number are checked for equality.

  To fix this, decide if values are best represented as strings or numbers. To convert a
  string to a number simply add `0` to it. To convert a number to a string, either
  interpolate it; `"$x"` (to convert it to a decimal number), or use the `sprintf`
  function to convert it to octal, hex or a floating point notation. The `sprintf` function
  has many options that control the string representation, upper/lower case letters in
  hex numbers, prefix 0x, 0X, the precision of a floating point representation etc.

  Also consider if input should be a string or a number - that is a better fix than sprinkling
  data type conversions all over the code.

** MIGRATE4_OPTION_TYPE_MISMATCH (PUP-4127) **:

  In 4.x, case and selector options are matched differently than in 3.x. In 3.x if the
  match was not true, the match would be made with the operands converted to strings.
  This means that 4.x logic can select a different (or no option) given the same input.

  The migration checker logs a warning with the issue code MIGRATE4_OPTION_TYPE_MISMATCH
  for every evaluated option that did not match because of a difference in type.

  The fix for this depends on what the types of the test and option expressions
  are - most likely number vs. string mismatch, and then the fix is the same as for
  MIGRATE4_EQUALITY_TYPE_MISMATCH. For other type mismatches review the logic for what
  was intended and make adjustments accordingly.

** MIGRATE4_AMBIGUOUS_NUMBER (PUP-4129) **:

  This migration check helps with unquoted numbers where strings are intended.

  A common construct is to use values like `'01'`, `'02'` for ordering of resources. It is
  also a common mistake to enter them as bare word numbers e.g. `01`, `02`. The difference
  between 3.x and 4.x is that 3.x treats all bare word numbers as strings (unless arithmetic
  is performed on them which produces numbers), whereas 4.x treats numbers as numbers from
  the start.  The consequence in manifests using ordering is that 1, 100, 1000 comes
  before 2, 200, and 2000 because the ordering converts the numbers back to strings without
  the leading zero.

  In 4.x. the leading zero means that the value is an octal number.

  The migration checker logs a warning for every occurrence of octal, and hex numbers with
  the issue code MIGRATE4_AMBIGUOUS_NUMBER in order to be able to find all places where the
  value is used for ordering.

  To fix these issues, review each occurrence and quote the values that represent "ordering", or
  file mode (since file mode is a string value in 4.x).

** MIGRATE4_AMBIGUOUS_FLOAT (PUP-4129) **

  This migration check helps with unquoted floating point numbers where strings are
  intended.

  Floating point values for arithmetic are not very commonly used in puppet. When seing
  something like `3.14`, it is most likely a version number string, and not someone doing
  calculations with PI.

  The migration checker logs a warning for every occurrence of floating point numbers with
  the issue code MIGRATE4_AMBIGUOUS_FLOAT in order to be able to find all places where a
  string may be intended.

** Significant White Space/ MIGRATE4_ARRAY_LAST_IN_BLOCK (PUP-4128) **:

  In 4.x. a white space between a value and a `[´ means that the ´[´ signals the start
  of an Array instead of being the start of an "at-index/key" operation. In 3.x. white
  space is not significant. Most such places will lead to errors, but there are corner
  cases - like in the example below:

    if true {
      $a = File ['foo']
    }

  Here 4.x will assign `File` (a resource type) to `$a` and then produce an array
  containing the string `'foo'`.

  The migration checker logs a warning with the issue code MIGRATE4_ARRAY_LAST_IN_BLOCK
  for such occurrences.

  To fix this, simply remove the white space.

** MIGRATE4_REVIEW_IN_EXPRESSION (PUP-4130) **:

  In 3.x the `in` operator was not well specified and there were several undefined behaviors.
  This relates to, but is not limited to:

  * string / numeric automatic conversions
  * applying regular expressions to non string values causing auto conversion
  * confusion over comparisons between empty string/undef/nil (internal) values
  * in-operator not using case independent comparisons

  To fix, review the expectations against the puppet language specification.

COPYRIGHT
---------
Copyright (c) 2015 Puppet Labs, LLC Licensed under Puppet Labs Enterprise.

