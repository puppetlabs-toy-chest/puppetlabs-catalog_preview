Catalog Delta
===
A catalog-delta describes a delta between a *baseline* and a *preview* catalog compiled
for the same node. The baseline is the expected content, and the preview is the actual.

The catalog delta output format is expressed in JSON and is specified in [catalog-delta.json][1]
using Json-schema `'http://json-schema.org/draft-04/schema#`'.

[1]: ../schemas/catalog-delta.json

This document serves as an overview of the content in a catalog diff and how it can
be used.

The root object
---
The root object describes the following attributes:

* `node_name` - the name of the node (by definition the same for both baseline and preview)
* `time` - the timestamp when the delta was produced (start time)
* `produced_by` - the name and version of the tool that produced the diff (e.g. "Puppet Preview 1.0")

* `baseline_env` - the name of the baseline environment
* `preview_env` - the name of the preview environment

* `baseline_catalog` - the file name of the baseline catalog (if produced)
* `preview_catalog` - the file name of the preview catalog (if produced)

* `baseline_resource_count` -number of resources in the baseline catalog
* `preview_resource_count` - number of resources in the preview catalog
  
* `preview_compliant` - `true` if the preview catalog has all content in the baseline (may contain more)
* `preview_equal` - `true` if the preview catalog is equal to the baseline catalog

* `assertion_count` - the total number of assertions made (number of checks)
* `passed_assertion_count` - the number of assertions that passed
* `failed_assertion_count` - the number of assertions that did not pass

* `missing_resources` - an array of information about missing resources (i.e. a resource
  not found in preview).
* `added_resources` - an array of information about added resources (i.e. a resource found
  in preview, but not in baseline)
* `conflicting_resources` - an array of information about resources that are conflicting (i.e.
  resources in both baseline and preview where their contents is different).

* `missing_edges` - array of edges in baseline not in preview
* `added_edges` - array of edges not in baseline but in preview

* `version_equal` - `true` if the versions of the two catalogs are the same


Summary Information
---
The attributes `preview_equal`, and `preview_compliant` signals if the two catalogs are
equal, or if the preview catalog contains all of the baseline but has additional content.

The assertion counts are intended to help quickly decide the extent of the delta, and if
there were any errors when computing the delta.

The relationship between the counts are:

    assertion_count = passed_assertion_count + failed_assertion_count
    
The `preview_compliant` is true if

    assertion_count == passed_assertion_count

The `preview_equal` is true if 

    preview_compliant  &&
    baseline_resource_count == preview_resource_count &&
    added_edges.size == 0 &&
    version_equal == true

> TODO: There should be counts for the edges as well
>
The `preview_equals` is useful when upgrading the version of Puppet as it is an assertion that an identical catalog is produced.

The `preview_compliant` is useful when refactoring and an assertion is wanted that the catalog
contains at least the baseline content. This can also be used to assert that a catalog contains
a minimum set of resources as dictated by organization policy.

Note that `preview_compliant` relaxes rules regarding the order of content in array
attributes; if baseline has the values `[1,2,3]` in an attribute, and the preview has
`[a, 2, 3, 1]`, this is still considered compliant. The difference is still reported as a
conflicting value. The reported conflicts should be reviewed to assert the degree of compliance.

By default the summary information is displayed to the user. The `--view` option makes it 
possible to instead write one of the other 5 artifacts to `stdout`; baseline_catalog, baseline_log,
preview_catalog, preview_log, or catalog_diff. This allows the user to pipe the output to a
JSON query to select/transform the output for the purpose of focusing on a particular part of
the output.

Exit Status
----
The exit status is difficult to use as there are many possible outcomes that do not constitute
a failure on the application's part and requires interpretation. By default the application
should exit with 0 if it was possible to compile both catalogs (no hard compilation errors),
-2 if baseline compilation failed, -3 if preview compilation failed, -§ if the application
failed in general (could not write a file etc.).

The option `--assert=equal` makes the command exit with -4 if catalogs are not equal, and
the option `--assert=compliant` makes the command exit with -5 if catalogs are not compliant.

Missing Resources
---
Resources are reported as missing if they exist in the baseline but there is no resource
with the same type and title in the preview.

    missing_resources: [ 
        {
            "baseline_location" : {  "file" : "/.../abc.pp", "line" : 10 }
            "type" : "File",
            "title": "tmp/foo"
        },
        { ... }
    ]
    
Note that the attributes of missing resources are not included in the diff to
reduce clutter. These values can be found in the produced catalog if they are needed
for identification.

> A flag for '-- verbose-missing' may be added to the command later.         

Added Resources
---
Resources are reported as added if they exist in the preview but there is no resource
with the same type and title in the baseline.

    added_resources: [ 
        {
            "preview_location" : {  "file" : "/.../abc.pp", "line" : 10 }
            "type" : "File",
            "title": "tmp/foo2"
        },
        { ... }
    ]

Note that the attributes of added resources are not included in the diff to
reduce clutter. These values can be found in the produced catalog if they are needed
for identification.

> A flag for '--verbose-added' may be added to the command later.         

Conflicting Resources
---
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
            "added_attributes_count": 3
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

> A flag for '--verbose-conflicting' may be added to the command later.         

### Attributes

A resource contains different kinds of attributes; parameters, and information encoded
directly in the resource (i.e. `exported`, and `tags`). The `tags` are reported as a regular parameter `{ "name" : "tags" }`, but `exported` may also be a parameter value
(albeit esoteric), and it is reported with the attribute name `"@@"` (since this is the syntax for an exported resource).

The following attributes are treated as sets:

* `before`
* `after`
* `subscribe`
* `notify`
* `tags`

That is, the order of elements never matters, and duplicate entries are ignored.

For other array attributes, the exact content must be present for the parameter to
be considered equal. For compliance, the preview array must contain the same
non unique values, but the order may be different.

    [1, 2, 2, 3] equals        [1, 2, 2, 3]
    [1, 2, 2, 3] compliant     [3, 4, 2, 5, 2, 1, 1]
    [1, 2, 2, 3] not compliant [1, 2, 3, 4, 5, 1, 1]

Hash attributes are equal if the keys and values are equal (order is insignificant).
Hashes are compliant if they have at least the same set of keys, and values
are compliant.

> DISCUSS: Are these rules helpful? They should squelch compliance noise, but
> are they correct? (Note that they are still reported as conflicting)

When refactoring, the tag values can be quite different and the `--ignore_tags` options can
be used to ignore tag differences.


#### Format of differences

Added, missing and conflicting attributes are output in JSON format. For large values
and complex structures it may be difficult to spot differences by just reading the
delta output in JSON. In such situations the values can be extracted with a json tool (e.g. jq,
or jgrep) and compared using a diff tool such as the system `diff`, one of the many json-diff tools such as `jsondiffpath.js`.


### Missing Attributes

Attributes in the resource in baseline that does not have a value in the preview are
reported as missing attributes:

    "missing_attributes" : [
        {
           "baseline_location" : {  "file" : "/.../abc.pp", "line" : 11 }
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
            "preview_location" : {  "file" : "/.../abc.pp", "line" : 15 }
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
---
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
---
All diff entries have a `diff_id` integer value. The id values serves as way of finding a
specific entry in the catalog_diff.json output after having filtered the output and looking at a small portion - having a unique value helps as output from a json query cannot produce references
to line numbers in the json source file.
