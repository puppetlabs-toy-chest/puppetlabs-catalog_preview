preview
===
#### Table of Contents

1. [Overview](#overview)
2. [Module Description - What the module does and why it is useful](#module-description)
3. [Setup - The basics of getting started with preview](#setup)
4. [Usage - Configuration options and additional functionality](#usage)
    * [Options - Command line options for preview](#options)
    * [Examples - Running preview](#examples)
6. [Limitations](#limitations)
7. [License and Copyright](#license-and-copyright)

Overview
---
A PE only module providing catalog preview and migration features.

If you need additional guidance beyond this README, please see
[preview-help](lib/puppet_x/puppetlabs/preview/api/documentation/preview-help.md) and
[catalog-diff](lib/puppet_x/puppetlabs/preview/api/documentation/catalog-delta.md) for more details.

The help is viewable on the command line with:

    puppet preview --help

The help for the catalog-delta is viewable on the command line with:

    puppet preview --schema help

Module Description
---
The preview module compiles two catalogs, one in an *baseline environment*, and one in a *preview environment*.
It then computes a diff between the two. Preview produces the two catalogs, the diff, and the log 
output from each compilation for inspection. The primary purpose of the preview module is to serve
as an aid for migration from the current 3.x parser to the 4.x (or "future") parser, but
the preview command can also help in various change management and refactoring scenarios.

The idea is to have the original "baseline" environment unchanged and configured with the 3.x parser
(what is currently in production) in addition to a "preview" environment. The preview environment
should be pointed at a branch of the original environment but be configured via `environment.conf`
to use the future parser. This way, backwards incompatible changes can be made in the preview environment without affecting production. The user can use the diff, catalog, and log outputs
provided by preview to make changes to the preview environment until they feel it is ready to
move into production, thus aiding with migration to the 4.x parser.

Other scenarios are supported the same way, the baseline and preview environments can be any
mix of future and current parser, but the `--migrate` option (providing specific migration checking)
can only be used when the baseline environment is using current parser (3.x), and the preview
environment is using future parser (4.x).

Setup
---
Prior to using preview, you must ensure you are running a version of puppet that is 3.8.0 or greater, but less than 4.0.0 (since the 3.x parser no longer exists in 4.0). As mentioned above, you will need to have two environments: your current production environment (configured with the 3.x) and a preview environment, which is pointed at a branch of your current environment and configured to use the future parser via the `environment.conf`.

Prior to performing a migration preview, you should have:

* Addressed all deprecations in the production environment
* Ensure that stringified facts is `false` on your agents

Usage
---
The preview command compiles, compares, and asserts a baseline catalog and a preview catalog
for a node that has previously requested a catalog from a puppet master (thereby making
its facts available). The compilation of the baseline catalog takes place in the
environment configured for the node (optionally overridden with `--baseline_environment`).
The compilation of the preview takes place in the environment designated by `--preview_env`.

If `--baseline_environment` is set, the node will first be configured as directed by
an ENC, the environment is then switched to the `--baseline_environment`.
The `--baseline_environment` option is intended to aid when changing code in the
preview environment (for the purpose of making it work with the future parser) while
the original environment is unchanged and is configured with the 3.x current parser
(i.e. what is in 'production').
If the intent is to make backwards compatible changes in the preview
environment (i.e. changes that work for both parsers) it is of value to have yet another
environment configured for current parser where the same code as in the preview environment
is checked out. It is then simple to diff between compilations in any two environments
without having to modify the environment assigned by the ENC. All other assignments
made by the ENC are unchanged.

By default the command outputs a summary report of the difference between the two
catalogs on 'stdout'. This can be changed with `--view` to instead view
one of the catalogs, the diff, or one of the compilation logs. Use the `--last` option
to view one of the results from the last preview compilation instead of again compiling
and computing a diff. Note that `--last` does not reload the information and can
therefore not display a summary.

When the preview compilation is performed, it is possible to turn on extra
migration validation using `--migrate`. This will turn on extra validations
of future compatibility flagging puppet code that needs to be reviewed. This
feature was introduced to help with the migration from puppet 3.x to puppet 4.x.
and requires that the `--preview_env` references an environment configured
to use the future parser in its `environment.conf` and that the baseline environment
is configured to use the current (3.x) parser.

All output (except the summary report intended for human use) is written in
JSON format to allow further processing with tools like 'jq' (JSON query).

The output is written to a subdirectory named after the node of the directory appointed
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

Each new invocation of the command for a given node overwrites the information
already produced for that node.

The two catalogs are written in JSON compliant with a json-schema
('catalog.json'; the format used by puppet to represent catalogs in JSON)
viewable on stdout using `--schema catalog`.

The 'catalog_diff.json' file is written in JSON compliant with a json-schema
viewable on stdout using `--schema catalog_delta`.

The two '*<type>*_log.json' files are written in JSON compliant with a json-schema
viewable on stdout using `--schema log`.

Options
---

The following options are available for the `puppet preview` command

* **--debug:**
  Enable full debugging. Debugging output is sent to the respective log outputs
  for baseline and preview compilation. This option is for both compilations.
  Note that debugging information for the startup and end of the application
  itself is sent to the console.

* **--help:**
  Print this help message.

* **--version:**
  Print the puppet version number and exit.

* **--preview_environment `ENV-NAME`:**
  Makes the preview compilation take place in the given <ENV-NAME>.
  Uses facts obtained from the configured facts terminus to compile the catalog.

* **--baseline_environment `ENV-NAME`:**
  Makes the baseline compilation take place in the given <ENV-NAME>. This overrides
  the environment set for the node via an ENC.
  Uses facts obtained from the configured facts terminus to compile the catalog.
  Note that the puppet setting `--environment` **cannot** be used to achieve the same effect.

* **--view summary | diff | baseline | preview | baseline_log | preview_log | status | none:**
  Specifies what will be output on stdout; the catalog diff, one of the two
  catalogs, or one of the two logs. The option 'status' displays a one line status of compliance.
  The option 'none' turns off output to stdout.

* **--migrate:**
  Turns on migration validation for the preview compilation. Validation result
  is produced to the preview log file or optionally to stdout with `--view preview_log`.
  When `--migrate` is on, values where one value is a string and the other numeric
  are considered equal if they represent the same number. This can be turned off
  with `--diff_string_numeric`, but turning this off may result in many conflicts
  being reported that need no action.

* **--diff_string_numeric:**
  Makes a difference in type between a string and a numeric value (that are equal numerically)
  be a conflicting diff. Can only be combined with `--migrate`. When `--migrate` is not specified,
  differences in type are always considered a conflicting diff.

* **--assert equal | compliant:**
  Modifies the exit code to be 4 if catalogs are not equal and 5 if the preview
  catalog is not compliant instead of an exit with 0 to indicate that the preview run
  was successful in itself.
  
* **--preview_outputdir `DIR`:**
  Defines the directory to which output is produced.
  This is a puppet setting that can be overridden on the command line (defaults
  to `$vardir/preview`).

* **`NODE-NAME`:**
  This specifies for which node the preview should produce output. The node must
  have previously requested a catalog from the master to make its facts available.

* **--schema catalog | catalog_delta | log | help:**
  Outputs the json-schema for the puppet catalog, catalog_delta, or log. The option
  `help` will display the semantics of the catalog-diff schema. Can not be combined with
  any other option.

* **--skip_tags:**
  Ignores comparison of tags, catalogs are considered equal/compliant if they only
  differ in tags.

* **--trusted:**
  Makes trusted node data obtained from a fact terminus retain its authentication
  status of `"remote"`, `"local"`, or `false` (i.e. the authentication status the facts
  write request had).
  If this option is not in effect, any trusted node information is kept, and the
  authenticated key is set to false. The `--trusted` option is only available when running
  as root, and should only be turned on when also trusting the fact-store.

* **--verbose_diff:**
  Includes more information in the catalog diff such as attribute values in
  missing and added resources. Does not affect if catalogs are considered equal or
  compliant.

* **--last:**
  Use the last result obtained for the node instead of performing new compilations
  and diff. (Cannot be combined with `--view none` or `--view summary`).

Examples
---

To perform a full migration preview that exists with failure if catalogs are not equal:

    puppet preview --preview_env future_production --migrate --assert=equal mynode
    
To perform a preview that exits with failure if preview catalog is not compliant:

    puppet preview --preview_env future_production --assert=compliant mynode

To perform a preview focusing on if code changes resulted in conflicts in
resources of `File` type using 'jq' to filter the output (the command is given as one line):

    puppet preview --preview_env future_production --view diff mynode 
    | jq -f '.conflicting_resources | map(select(.type == "File"))'
    
View the catalog schema:

    puppet preview --schema catalog
    
View the catalog-diff schema:

    puppet preview --schema catalog_diff
    
Run a diff (with the default summary view) then view the preview log:

    puppet preview --preview_env future_production mynode
    puppet preview --preview_env future_production mynode --view preview_log --last

Node name can be placed anywhere:

    puppet preview mynode --preview_env future_production
    puppet preview --preview_env future_production mynode 

Limitations
---

The preview module requires a version of Puppet or Puppet Enterprise version >= 3.8.0 < 4.0.0

License and Copyright
---
The content of this module is:

*Copyright (c) 2015 Puppet Labs, LLC Licensed under Puppet Labs Enterprise.*

