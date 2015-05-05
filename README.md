[parser_config]: https://docs.puppetlabs.com/puppet/latest/reference/config_file_environment.html#parser

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

You'll point your preview environment at a branch of the environment you want to migrate, and then [configure][parser_config] the preview environment to use the 4.x ("future") parser. This way, backwards-incompatible changes can be made in the preview environment without affecting production. You can then use the diff, catalog, and log outputs provided by preview to make changes to the preview environment until you feel it is ready to move into production.

Other scenarios are supported in the same way. For example, the module's `puppet preview` command can help in various change management and refactoring scenarios. The baseline and preview environments can be any mix of future and current parser, allowing you to compare configurations even if you're not performing a 3.x to 4.x migration.

However, the `--migrate` option---which provides the specific migration checking that is the primary purpose of this module---can only be used when the baseline environment is using current parser (3.x), and the preview environment is using future parser (4.x).

##Setup

###Requirements

To get started, you'll need:

* Puppet Enterprise, version 3.8.0 or greater, but less than version 4.0.0.
* Two environments:
  * Your current production environment, using the 3.x (current) parser.
  * A preview environment, using the 4.x (future) parser.

As mentioned above, your current production environment should be configured to use the 3.x or current parser. Your preview environment should be pointed at a branch of your current environment and configured to use the future, or 4.x, parser. Configure which parser each environment uses via the [`parser`][parser_config] setting in each environment's `environment.conf`.

Note that your PE version must be less than version 4.0.0, because the future parser is the only parser available in 4.0.0, so no migration can be made.
 
###Installation

Install the catalog_preview module with `puppet module install puppetlabs-catalog_preview`.

##Usage

###Prerequisites

Before you perform a migration preview, you should:

* Address all deprecations in the production environment.
* Ensure that `stringify_facts` in puppet.conf is `false` on your agents. (In PE 3.8 and greater, `stringify_facts` defaults to 'false'.)

###Evaluating environments with the `puppet preview` command

####Comparing environments

The `puppet preview` command compiles, compares, and asserts a baseline catalog and a preview catalog for a node. This node must have checked in with the master at least one time prior to running `preview`, so that the node's facts are available to the master. The compilation of the baseline catalog takes place in the environment configured for the node. The compilation of the preview catalog takes place in the environment designated by `--preview_env`. The following code will generate a preview for the preview environment named 'future_production' on the node 'mynode'.

~~~
puppet preview --preview_env future_production mynode
~~~

####Validating a migration

When you run the preview compilation, you can turn on extra migration validation using `--migrate`. This turns on extra validations of future compatibility, flagging Puppet code that needs to be reviewed. This feature was introduced to help with the migration from the 3.x parser to the 4.x parser. To use this feature, `--preview_env` must reference an environment configured to use the future parser in its `environment.conf`, while the baseline environment must be configured to use the current (3.x) parser.

~~~
puppet preview --preview_env future_production --migrate mynode
~~~

####Checking backwards-compatible changes

By default, the compilation of the baseline catalog takes place in the environment configured for the node. Optionally, you can override the default baseline and set a specific baseline environment with `--baseline_environment`. If `--baseline_environment` is set, the node is first configured as directed by an external node classifier (ENC), and then the environment is switched to the `--baseline_environment`.

~~~
puppet preview --preview_env future_production --baseline_environment my_baseline --migrate mynode
~~~

The `--baseline_environment` option aids you when you're changing code in the preview environment for the purpose of making it work with the future parser, while the original environment is unchanged and configured with the 3.x current parser.

If you want to make backwards-compatible changes in the preview
environment (i.e., changes that work for both parsers), it's valuable to have a third environment configured. This third environment should have the same code as the preview environment, but should be configured for the current parser. You can then diff between compilations in any two of the environments without having to modify the environment assigned by the ENC. This allows you to check your preview environment changes against the current production parser to make sure that they work. All other assignments made by the ENC are unchanged.

####Viewing reports

By default, the `puppet preview` command outputs a summary report of the difference between the two catalogs on 'stdout'. This can be changed with [`--view`](#--view) to instead view one of the catalogs, the diff, or one of the compilation logs. Use the `--last` option with `--view` to view a result from the previous run obtained for the node instead of performing new compilations and diff. Note that `--last` does not reload the information and can therefore not display a summary.

`puppet preview --last --view baseline_log`

####Processing output

All output (except the summary report intended for human use) is written in JSON format to allow further processing with tools like 'jq' (JSON query). The output is written to a subdirectory named after the node of the directory appointed
by the setting `preview_outputdir` (defaults to `$vardir/preview`):

    |- "$preview_output-dir"
    |  |
    |  |- <NODE-NAME-1>
    |  |  |- preview_catalog_.json
    |  |  |- baseline_catalog.json
    |  |  |- preview_log.json
    |  |  |- baseline_log.json
    |  |  |- catalog_diff.json
    |  |  
    |  |- <NODE-NAME-2>
    |  |  |- ...

Each new invocation of the command for a given node overwrites the information already produced for that node.

The two catalogs are written in JSON compliant with a json-schema
('catalog.json'; the format used by Puppet to represent catalogs in JSON) viewable on stdout using `--schema catalog`.

The 'catalog_diff.json' file is written in JSON compliant with a json-schema viewable on stdout using `--schema catalog_delta`.

The two '*<type>*_log.json' files are written in JSON compliant with a json-schema viewable on stdout using `--schema log`.

###Usage Examples

To perform a full migration preview that exits with failure if catalogs are not equal:

~~~
puppet preview --preview_env future_production --migrate --assert=equal mynode
~~~
    
To perform a preview that exits with failure if preview catalog is not compliant:

~~~
puppet preview --preview_env future_production --assert=compliant mynode
~~~

To perform a preview focusing on if code changes resulted in conflicts in resources of `File` type using 'jq' to filter the output (the command is given as one line):

~~~
puppet preview --preview_env future_production --view diff mynode | jq -f '.conflicting_resources | map(select(.type == "File"))'
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
puppet preview --preview_env future_production mynode

puppet preview --preview_env future_production mynode --view preview_log --last
~~~

The node name can be placed anywhere:

~~~
puppet preview mynode --preview_env future_production
puppet preview --preview_env future_production mynode 
~~~


###Options

The following command-line options are available for the `puppet preview` command.

#####`--assert`

Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview catalog is not compliant, instead of an exit with 0 to indicate that the preview run was successful in itself. Accepts the arguments `equal`, `compliant`.

#####`--baseline_environment 'ENV-NAME'`

Specifies the environment for the baseline compilation. This overrides the environment set for the node via an ENC. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from Puppet 3.x to Puppet 4.x, this environment's puppet.conf should be configured to use the current (3.x) parser. Note that the Puppet setting `--environment` **cannot** be used to achieve the same effect.

#####`--preview_env 'ENV-NAME'`

Specifies the environment for the preview compilation. Uses facts obtained from the configured facts terminus to compile the catalog. If you're evaluating for migration from Puppet 3.x to Puppet 4.x, this environment's puppet.conf should be configured to use the future (4.x) parser.

#####`--debug`

Enables full debugging. Debugging output is sent to the respective log outputs for baseline and preview compilation. This option is for both compilations. Note that debugging information for the startup and end of the application itself is sent to the console.


#####`--diff_string_numeric`

Makes a difference in type between a string and a numeric value (that are equal numerically) be a conflicting diff. Can only be combined with `--migrate`. When `--migrate` is not specified, differences in type are always considered a conflicting diff.

#####`--help`

Prints a help message listing the options for the `puppet preview` command.

#####`--last`

Use the last result obtained for the node instead of performing new compilations and diff. Must be used along with the [`--view`](#--view) option. (Cannot be combined with `--view none` or `--view summary`).

#####`--migrate`

Turns on migration validation for the preview compilation. Validation result is produced to the preview log file or optionally to stdout with `--view preview_log`. 

When `--migrate` is on, values where one value is a string and the other numeric are considered equal if they represent the same number. This can be turned off with `--diff_string_numeric`, but turning this off might result in many conflicts being reported that need no action.

For details about the migration specific warnings, see [the catalog_preview wiki page](https://github.com/puppetlabs/puppetlabs-catalog_preview/wiki).

#####`NODE-NAME`

This specifies for which node the preview should produce output. The node must have previously requested a catalog from the master to make its facts available.


#####`--preview_outputdir 'DIR'`

Defines the directory to which output is produced. This is a Puppet setting that can be overridden on the command line (defaults to `$vardir/preview`).

#####`--schema`

Outputs the json-schema for the Puppet catalog, catalog_delta, or log. The option `help` will display the semantics of the catalog-diff schema. Can not be combined with any other option. Accepts arguments `catalog`, `catalog_delta`, `log`, `help`.

#####`--skip_tags`

Ignores comparison of tags, catalogs are considered equal/compliant if they only differ in tags.

#####`--trusted`

Makes trusted node data obtained from a fact terminus retain its authentication status of `"remote"`, `"local"`, or `false` (i.e., the authentication status the facts write request had). If this option is **not** in effect, any trusted node information is kept, and the authenticated key is set to false. The `--trusted` option is only available when running as root and should only be turned on when also trusting the fact-store.

#####`--version`

Prints the Puppet version number.

#####`--view` 

Specifies what will be output on stdout. Must be used with one of the following arguments:

* `summary`: The summary report
* `diff`: The catalog diff
* `baseline`: The baseline catalog
* `preview`: The preview catalog
* `baseline_log`: Outputs the baseline log
* `preview_log`: Outputs the preview log
* `status`: Compliance status
* `none`: No output

#####`--verbose_diff`

Includes more information in the catalog diff such as attribute values in missing and added resources. Does not affect whether catalogs are considered equal or compliant.

##Help

You can get help on the command line with:

~~~
puppet preview --help
~~~

You can also get help for the catalog-delta with:

~~~
puppet preview --schema help
~~~

If you need additional guidance beyond this README, please see
[preview-help](lib/puppet_x/puppetlabs/preview/api/documentation/preview-help.md) and
[catalog-diff](lib/puppet_x/puppetlabs/preview/api/documentation/catalog-delta.md) for more details.

##Limitations

The preview module requires a version of Puppet Enterprise version >= 3.8.0 < 4.0.0.

###License and Copyright

The content of this module is:

*Copyright (c) 2015 Puppet Labs, LLC Licensed under Puppet Labs Enterprise.*

