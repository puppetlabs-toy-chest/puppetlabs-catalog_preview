Catalog Delta
=============

A catalog-delta describes a delta between a *baseline* and a *preview* catalog compiled
for the same node. The baseline is the expected content, and the preview is the actual.

The catalog delta output format is expressed in JSON and is specified in [catalog-delta.json][1]
using Json-schema `'http://json-schema.org/draft-04/schema#`'. The catalog-delta schema can
be viewed directly on the command line with 'puppet preview --schema catalog_delta'.

[1]: ../schemas/catalog-delta.json

This document serves as an overview of the content in a catalog diff and how it can
be used.

The root object
---------------
The root object describes the following attributes:

* `node_name`
  the name of the node (by definition the same for both baseline and preview)

* `time`
  the timestamp when the delta was produced (start time)

* `produced_by`
  the name and version of the tool that produced the diff (e.g. "Puppet Preview 3.8")

* `preview_compliant`
  `true` if the preview catalog has all content in the baseline (may contain more)

* `preview_equal`
  `true` if the preview catalog is equal to the baseline catalog

* `version_equal`
  `true` if the the versions of the two catalogs are the same (this is the internal version

* `tags_ignored`
  `true` if tags are ignored when comparing resources

* `baseline_env`
  the name of the baseline environment

* `preview_env`
  the name of the preview environment

* `baseline_catalog`
  the file name of the baseline catalog (if produced)

* `preview_catalog`
  the file name of the preview catalog (if produced)

* `baseline_resource_count`
  number of resources in the baseline catalog

* `preview_resource_count`
  number of resources in the preview catalog

* `baseline_edge_count`
  number of edges in the baseline catalog

* `preview_edge_count`
  number of edges in the preview catalog

* `added_resource_count`
  number of resources found in the preview catalog but not in the baseline catalog

* `missing_resource_count`
  number of resources found in the baseline catalog but not in the preview catalog

* `conflicting_resource_count` - number of resources that are conflicting (i.e.
  resources in both baseline  and preview where their contents is different).

* `added_edge_count`
  number of edges found in the preview catalog but not in the baseline catalog

* `missing_edge_count`
  number of edges found in the baseline catalog but not in the preview catalog

* `added_attribute_count`
  total number of resource attributes found in the preview catalog but not in the
  baseline catalog

* `missing_attribute_count`
  total number of resource attributes found in the baseline catalog but not in the
  preview catalog

* `conflicting_attribute_count`
  total number of resource attributes that are conflicting (i.e. resource attributes
  in both baseline and preview with different values).

* `added_resources`
  an array of information about added resources (i.e. a resource found
  in preview, but not in baseline)

* `missing_resources`
  an array of information about missing resources (i.e. a resource not found in preview).

* `conflicting_resources`
  an array of information about resources that are conflicting (i.e. resources in
  both baseline and preview where their contents is different).

* `added_edges`
  array of edges not in baseline but in preview

* `missing_edges`
  array of edges in baseline not in preview


Summary Information
-------------------
The attributes `preview_equal`, and `preview_compliant` signals if the two catalogs are
equal, or if the preview catalog contains all of the baseline but has additional "compliant"
content. The `preview_equals` is useful when upgrading the version of Puppet as it is an
assertion that an identical catalog is produced.

The `preview_compliant` is useful when refactoring and an assertion is wanted that the catalog
contains at least the baseline content. This can also be used to assert that a catalog contains
a minimum set of resources as dictated by organization policy.

Note that `preview_compliant` relaxes rules regarding the order of content in array
attributes; if baseline has the values `[1,2,3]` in an attribute, and the preview has
`[a, 2, 3, 1]`, this is still considered compliant. The difference is reported as a
conflicting value with the "compliant" entry set to true.

By default the summary information is displayed to the user. The `--view` option makes it
possible to instead write one of the other produced artifacts to `stdout`; baseline_catalog,
baseline_log, preview_catalog, preview_log, or catalog_diff. This allows the user to pipe
the output to a JSON query to select/transform the output for the purpose of focusing on
a particular part of the output.

If the baseline or preview compilation fails, the log for the failing compilation
is displayed in abbreviated form on stderr. If the full log is required to understand the
nature of the problem it can be obtained by running again with the options '--last' and
'--view xxx_log' where 'xxx' is either 'baseline' or 'preview' depending on wanted log.

Exit Status
-----------
The application exits with the following exit codes and reasons:

| exit | description
| ---  | -----------
| 0    | if it was possible to compile both catalogs (there were no hard compilation errors)
| 1    | if the preview application failed in general
| 2    | if baseline compilation failed
| 3    | if preview compilation failed
| 4    | if '--assert equal' is used and catalogs are not equal
| 5    | if '--assert compliant' is used and preview is not compliant

Missing Resources
-----------------
Resources are reported as missing if they exist in the baseline but there is no resource
with the same type and title in the preview.

    missing_resources: [
        {
            "location" : {  "file" : "/.../abc.pp", "line" : 10 },
            "type" : "File",
            "title": "tmp/foo"
        },
        { ... }
    ]

Note that the attributes of missing resources are not included by default in the diff to
reduce clutter. These values can be found in the produced catalog if they are needed
for identification. Alternatively, the option `--verbose_diff' can be used to include
these.

Added Resources
---------------
Resources are reported as added if they exist in the preview but there is no resource
with the same type and title in the baseline.

    added_resources: [
        {
            "location" : {  "file" : "/.../abc.pp", "line" : 10 }
            "type" : "File",
            "title": "tmp/foo2"
        },
        { ... }
    ]

Note that the attributes of added resources are not included in the diff to
reduce clutter. These values can be found in the produced catalog if they are needed
for identification. Alternatively, the option `--verbose_diff' can be used to include
these.

Conflicting Resources
---------------------
Resources are reported as conflicting if they exist in both the preview and baseline but
there is a difference in the number of attributes and/or their values.

    conflicting_resources: [
        {
            "baseline_location" : {  "file" : "/.../abc.pp", "line" : 10 }
            "preview_location" :  {  "file" : "/.../abc.pp", "line" : 11 }
            "type" : "File",
            "title": "tmp/foo2",
            "equal_attributes_count": 8,
            "missing_attributes_count": 2,
            "added_attributes_count": 3,
            "conflicting_attributes_count": 1,

            "missing_attributes" : [
              // two entries here
            ],
            "added_attributes": [
              // three entries here
            ],
            "conflicting_attributes": [
              // one entry here
            ]
        },
        { ... }
    ]


### Attributes

A resource contains different kinds of attributes; resource properties, parameters, and
information encoded directly in the resource (i.e. `exported`, and `tags`).
The `tags` are reported as a regular parameter `{ "name" : "tags" }`, but `exported`
is also valid as a parameter name value, and it is therefore reported with the attribute
name `"@@"` (since this is the syntax for an exported resource in the puppet language).

The following attributes are treated as sets:

* `before`
* `after`
* `subscribe`
* `notify`
* `tags`

That is, the order of elements never matters, and duplicate entries are ignored. When
one of these attributes have a single value, it will be treated as a set containing that
value.

For other array attributes, the exact content must be present for the parameter to
be considered equal. For compliance, the preview array must contain the same
non unique values, but the order may be different.

    [1, 2, 2, 3] equals        [1, 2, 2, 3]
    [1, 2, 2, 3] compliant     [3, 4, 2, 5, 2, 1, 1]
    [1, 2, 2, 3] not compliant [1, 2, 3, 4, 5, 1, 1]

Hash attributes are equal if the keys and values are equal (order is insignificant).
Hashes are compliant if they have at least the same set of keys, and values
are compliant.

When refactoring, the tag values can be quite different and the `--skip_tags`
options can be used to ignore tag differences.

The versions of the catalogs are compared. If different this is noted in the
output but this difference has no effect on the outcome of catalogs being
equal or compliant. (A difference in version may explain why catalogs are
different; data changed, etc.).

#### Format of differences

Added, missing and conflicting attributes are output in JSON format. For large values
and complex structures it may be difficult to spot differences by just reading the
delta output in JSON. In such situations the values can be extracted with a
json tool (e.g. 'jq', or 'jgrep') and compared using a diff tool such as the
system `diff`, one of the many json-diff tools freely available; such as `jsondiffpath.js`.

### Missing Attributes

Attributes in the resource in baseline that does not have a value in the preview are
reported as missing attributes:

    "missing_attributes" : [
        {
           "location" : {  "file" : "/.../abc.pp", "line" : 11 }
            "name" : "mode",
            "value": "0777"
        },
        { ... }
   ],

### Added Attributes

Attributes in the resource in preview that does not have a value in the baseline are
reported as added attributes:

    "added_attributes" : [
        {
            "location" : {  "file" : "/.../abc.pp", "line" : 15 }
            "name" : "owner",
            "value": "mothra"
        },
        { ... }
    ],

### Conflicting Attributes

Attributes in the resource in both preview and baseline where the value is not equal
are reported as added attributes:

    "conflicting_attributes" : [
        {
            "baseline_location" : {  "file" : "/.../abc.pp", "line" : 18 },
            "preview_location" : {  "file" : "/.../abc.pp", "line" : 19 },
            "name" : "owner",
            "baseline_value": "herp-derp",
            "preview_value": "godzilla",
            "compliant": false
        },
        { ... }
    ],

    "conflicting_attributes" : [
        {
            "baseline_location" : {  "file" : "/.../abc.pp", "line" : 42 },
            "preview_location" : {  "file" : "/.../abc.pp", "line" : 48 },
            "name" : "colors",
            "baseline_value": ["red", "blue"],
            "preview_value": ["green", "blue", "red"],
            "compliant": true
        },
        { ... }
    ],


Edges
-----

Edges describe containment. An edge is considered equal if the source and target strings
are equal. Edges are never reported as being in conflict.

There is  no attempt to find pathological cases that the runtime will
later flag as errors (circularities, multiple sources in containment, etc).

### Missing Edges

An edge in baseline that is not equal to any edge in preview is considered missing.

    "missing_edges" : [
        { "source": "Class[main]", "target" : "File[foo]" },
        { ... }
    ]

### Added Edges

An edge in preview that is not equal to any edge in baseline is considered added.

    "added_edges" : [
        { "source": "Class[main]", "target" : "File[fool]" },
        { ... }
    ]


Diff Id
-------

All diff entries have a `diff_id` integer value. The id values serves as way of finding a
specific entry in the 'catalog_diff.json' output after having filtered the output and looking
at a small portion - having a unique value helps as output from a json query cannot produce
references to line numbers in the json source file.
