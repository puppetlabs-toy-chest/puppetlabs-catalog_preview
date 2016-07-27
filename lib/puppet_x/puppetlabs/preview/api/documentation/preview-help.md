puppet-preview(8) -- Puppet catalog preview compiler
========

SYNOPSIS
--------
Compiles two catalogs for one or more nodes and computes a diff between the two. The catalogs may
reflect different environments, be compiled with different compilers, or both. Produces the two
catalogs, the diff, and the logs from each compilation for each node and then summaries/aggregates
and correlates found issues in various views of the produced information.

USAGE
-----
```
puppet preview [
    [--assert equal|compliant]
    [-d|--debug]
    [-l|--last]
    [--clean]
    [-m <MIGRATION>|--migrate <MIGRATION> [--[no-]diff-string-numeric] [--[no-]diff-array-value]]
    [--preview-outputdir <PATH-TO-OUTPUT-DIR>]
    [--[no-]skip-tags]
    |--excludes <PATH-TO-EXCLUSIONS-FILE>]
    [--view summary|overview|overview-json|baseline|preview|diff|baseline-log|preview-log|none|
      failed-nodes|diff-nodes|compliant-nodes|equal-nodes]
    [--[no-]report-all]
    [-vd|--[no-]verbose-diff]
    [--baseline-environment <ENV-NAME> | --be <ENV-NAME>]
    [--preview-environment <ENV-NAME> | --pe <ENV-NAME>]
    <NODE-NAME>+ | --nodes <FILE> <NODE_NAME>*
  ]|[--schema catalog|catalog-delta|excludes|log|help]
   |[-h|--help]
   |[-V|--version]
```

OPTIONS
-------

Note that all settings (such as 'log_level') affect both compilations.


* --assert equal | compliant
  Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview
  catalog is not compliant instead of an exit with 0 to indicate that the preview run
  was successful in itself.

* --baseline-environment <ENV-NAME> | --be <ENV-NAME>
  Makes the baseline compilation take place in the given <ENV-NAME>. This overrides
  the environment set for the node via an ENC.
  Uses facts obtained from the configured facts terminus to compile the catalog.
  Note that the puppet setting '-environment' cannot be used to achieve the same effect.

* --debug:
  Enables full debugging. Debugging output is sent to the respective log outputs
  for baseline and preview compilation. This option is for both compilations.
  Note that debugging information for the startup and end of the application
  itself is sent to the console.

* --\[no-\]diff-string-numeric
  Makes a difference in type between a string and a numeric value (that are equal numerically)
  be a conflicting diff. A type difference for the `mode` attribute in `File` will always be
  reported since this is a significant change. If the option is prefixed with `no-`, then a
  difference in type will be ignored. This option can only be combined with `--migrate 3.8/4.0` and
  will then default to `--no-diff-string-numeric`. The behavior for other types of conversions is
  always equivalent to `--diff-string-numeric`

* --\[no-\]diff-array-value
  A value in the baseline catalog that is compared to a one element array containing that value in
  the preview catalog is normally considered a conflict. Using `--no-diff-array-value` will prevent
  this conflict from being reported. This option can only be combined with `--migrate 3.8/4.0` and
  will default to `--diff-array-value`. The behavior for other types of conversions is always
  equivalent to `--diff-array-value`.

* --excludes <FILE>
  Adds resource diff exclusion of specified attributes to prevent them from being included
  in the diff. The excusions are specified in the given file in JSON as defined by the
  schema viewable with `--schema excludes`.

  Preview will always exclude one PE specific File resource that has random content
  as it would otherwise always show up as different.

  This option can be used to exclude additional resources that are expected to change in each
  compilation (e.g. if they have random or time based content). Exclusions can be
  per resource type, type and title, or combined with one or more attributes.

  An exclusion that isn't combined with any attributes will exclude matching resources completely
  together with all edges where the resource is either the source or the target.

  Note that '--excludes' is in effect when compiling and cannot be combined with
  '--last'.

* --help:
  Prints this help message.


* --last
  Uses the already produced catalogs/diffs and logs for the given node(s) instead
  of performing new compilations and diff. If used without any given nodes, all
  already produced information will be loaded.
  (Also see '--clean' for how to remove produced information).

* --migrate <MIGRATION>
  Turns on migration validation for the preview compilation. Validation result
  is produced to the preview log file or optionally to stdout with '--view preview-log'.
  When --migrate is on, values where one value is a string and the other numeric
  are considered equal if they represent the same number. This can be turned off
  with --diff-string-numeric, but turning this off may result in many conflicts
  being reported that need no action. The <MIGRATION> value is required. Currently only
  '3.8/4.0' which requires a Puppet version between >= 3.8.0 and < 4.0.0. The preview module
  may be used with versions >= 4.0.0, but can then not accept the '3.8/4.0' migration.

* --nodes <FILE>
  Specifies a file to read node-names from. If the file name is '-' file names are read
  from standard in. Each white-space separated sequence of characters is taken as a node name.
  This can be combined with additional nodes given on the command line. Duplicated entries,
  deactivated nodes, and nodes with no facts available are skipped.

* --preview-environment <ENV-NAME> | --pe <ENV-NAME>
  Makes the preview compilation take place in the given <ENV-NAME>.
  Uses facts obtained from the configured facts terminus to compile the catalog.

* --preview-outputdir <DIR>
  Defines the directory to which output is produced.
  This is a puppet setting that can be overridden on the command line.

* --schema catalog | catalog-delta | excludes | log | help
  Outputs the json-schema for the puppet catalog, catalog-delta, exclusions, or log. The option
  'help' will display the semantics of the catalog-diff schema. Can not be combined with
  any other option.

* --\[no-\]skip-tags
  Ignores (skips) comparison of tags, catalogs are considered equal/compliant if they only
  differ in tags. If the option is prefixed with `no-`, then tags will be included in the
  comparison. The default is `--no-skip-tags`.

* --\[no-\]verbose-diff
  Includes more information in the catalog diff such as attribute values in
  missing and added resources. Does not affect if catalogs are considered equal or
  compliant. The default is `--no-verbose-diff`.

* --version
  Prints the puppet version number and exit.

* --view <REPORT>
  Specifies what will be output on stdout;

  | REPORT          | Output
  | --------------- | ----------------------------------------------------------------------
  | summary         | A single node diff summary, or the status per node
  | diff            | The catalog diff for one node in json format
  | baseline        | The baseline catalog for one node in json
  | preview         | The preview catalog for one node in json
  | baseline-log    | The baseline log for one node in json
  | preview-log     | The preview log for one node in json
  | status          | Short compliance status output for one or multiple nodes
  | none            | No output, useful when using preview as a test of exit code in a script
  | overview        | Aggregated & correlated report of errors/warnings/diffs across nodes
  | overview-json   | (Experimental) The overview output in json format
  | failed-nodes    | A list of nodes where compilation of the two catalogs failed
  | diff-nodes      | A list of nodes where there are diffs in the two catalogs
  | compliant-nodes | A list of nodes that have catalogs that are equal, or with compliant diffs
  | equal-nodes     | A list of nodes where catalogs where equal


  The 'overview' report is intended to be the most informative in terms of answering "what
  problems do I have in my catalogs, and where does the problem originate/where can I fix it"?

  The reports 'status' and 'summary' are intended to be brief information for human consumption
  to understand the outcome of running a preview command.

  The 'xxx-nodes' reports are intended to be used for saving to a file and using it
  to selectively clean information or focus the next run on those nodes (i.e. the file is
  given as an argument to --nodes in the next run of the command).

  The 'diff', 'baseline', 'preview', 'baseline-log', and 'preview-log' reports are intended
  to provide drill down into the details and for being able to pipe the information to custom
  commands that further process the output.

  The 'overview-json' is "all the data" and it is used as the basis for the 'overview' report.
  The fact that it contains "all the data" means it can be used to produce other views of the
  results across a set of nodes without having to load and interpret the output for each node
  from the file system.
  It is marked as experimental, and its schema is not documented in this version of catalog preview
  as it may need adjustments in minor version updates. The intent is to document this in a
  subsequent release and that this report can be piped to custom commands, or to visualizers
  that can slice and dice the information.

* --\[no-\]report-all
  Controls if the 'overview' report will contain a list of nodes that is limited to the
  ten nodes with the highest number of issues or if all nodes are included in the list. The default
  is to only show the top ten nodes. This option can only be used together with with '--view overview'.
  The generated data file on which the command line output is based will always contain information
  about all nodes.

* <NODE-NAME>+
  This specifies for which node the preview should produce output. The node must
  have previously requested a catalog from the master to make its facts available.
  At least one node name must be specified (unless '--last' is used to load all available
  already produced information), either given on the command line or
  via the '--nodes' option.
