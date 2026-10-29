# NetGraph DSL Reference

The scenario YAML and the workflow steps, copied from NetGraph's reference pages (Scenario YAML
and Workflow Steps of https://networmix.github.io/NetGraph/). Every result field is described in
the [Results reference](https://networmix.github.io/NetGraph/reference/results/).

> For a quick start and common patterns, see [SKILL.md](../SKILL.md).
> For complete working examples, see [EXAMPLES.md](EXAMPLES.md).

## Scenario YAML

A scenario is a YAML file describing the network topology (nodes, links, risk groups), the analysis configuration (traffic demands, failure policies, workflow) and reusable parts (blueprints, hardware components). Every structure can be written out directly or generated from templates and parameters.

### Units and input validation

```yaml
units:
  resolution: auto
  precision: 0.001
```

| Key | Default | Meaning |
|-----|---------|---------|
| `resolution` | `auto` | The bandwidth unit `q`: `auto`, or one power of two from 2^-32 through 2^32 |
| `precision` | `0.001` | The input/count precision target `p`, greater than zero and at most 0.5 |

Capacities, demand volumes, finite offers and designs and minimum unreserved bandwidth are physical amounts, converted to whole units of `q` at preparation ([Units and the resolution q](https://networmix.github.io/NetGraph/concepts/#units-and-the-resolution-q)); [Precision and the choice of q](https://networmix.github.io/NetGraph/concepts/#precision-and-the-choice-of-q) says how `q` is chosen and what the units report records. Costs are positive integers ([link keys](#direct-node-and-link-definitions)); counts and weights are integers.

Conversion rounds the binary64 amount to the nearest whole unit, half up, with physical error at most `q/2`. A scaled volume is first multiplied in binary64; the conversion bound applies to that product. Preparation chooses `q` once for the run and all later library questions; analyses do not recompute the precision bounds.

With `resolution: auto`, `q` is the largest legal power of two satisfying `q ≤ 2p·v_min` and `q·Γ ≤ p·c_min`. Here `v_min` is the smallest positive prepared bandwidth input, `c_min` the smallest positive link capacity, and `Γ` a static count from network nodes and links, expanded lossless equal-split leaves and tunnel counts. A bound without a positive amount is omitted. A demand set used only by simultaneous placement steps adds nothing to the count; a set named by any other workflow step or requested in `prepare(..., demand_sets=...)` counts its leaves by their declared models. The full count formula and the delivery bound's conditions are in [Precision and the choice of q](https://networmix.github.io/NetGraph/concepts/#precision-and-the-choice-of-q).

If a bound needs a unit below `2^-32`, preparation starts at that floor. If converted inputs or the augmented graph's capacity sum reach `2^62` units, it chooses the finest coarser unit that fits, or refuses if none fits. Declared `resolution` sets `q` directly and is checked for range.

The units report gives `limited_by` (`input`, `split_count`, `range`, `resolution_floor`, `declared` or `unbounded`), `input_bound`, `split_bound` and `range_limit`. The first two bounds have `met` flags and are null without their positive input or capacity; `range_limit` is the next finer unit's range failure only when range forced a coarser unit, otherwise null. `achieved_precision = max(q/(2·v_min), q·Γ/c_min)` over present terms, or null without a positive denominator. `target_met` says whether this scalar input/count budget is null or at most `p`; it certifies no arbitrary answer. A declared unit, the resolution floor or range limits can leave a bound unmet.

YAML reads a number written with an exponent only when it has a decimal point and a signed exponent: `1.0e+6` and `1.0e-12` are numbers, while `1e6`, `1.0e6` and `1E+6` are text, and a numeric field refuses them:

<!-- example: refusal '1e6' is not of type 'number' -->

```yaml
network:
  nodes: {A: {}, B: {}}
  links: [{source: A, target: B, capacity: 1e6}]
```

Unknown keys are refused; your own metadata belongs under `attrs`. Every load refusal is a `ValueError` naming its field and raw value; a schema error is retained as the cause. An optional field accepts explicit `null` wherever its Python constructor accepts `None`.

### Template Syntaxes

Three template syntaxes, each valid only in its own context:

| Syntax | Example | Where | Effect |
|--------|---------|-------|--------|
| `[1-3]` | `dc[1-3]/rack[a,b]` | Node and risk group names | One definition per expansion, created at parse time |
| `$var` / `${var}` | `pod${p}/leaf` | Links, rules, demands | Substituted from the `vars` of an `expand` block |
| `{n}` | `srv-{n}` | `template` field | 1-indexed counter up to `count` |

### Selecting nodes

The DSL has two ways of selecting entities. Which one applies is fixed by the operation, not chosen by the author.

**1. Path-Based Node Selection** (link rules, traffic demands, workflow steps)

- Regex patterns on hierarchical node names; capture groups define the groups
- `group_by` regroups the selection by an attribute
- `match` filters by attribute conditions
- `active_only` drops disabled nodes

**2. Condition-Based Entity Selection** (failure rules, membership rules, risk group generation)

- `scope` picks nodes, links or risk groups
- `conditions` filter by attribute
- An optional `path` regex filters by name (before conditions for membership and generate rules, after them for failure rules)

Both build on the same primitives (condition evaluation, match specification), but they are not interchangeable.

#### Selector forms

Selectors can be specified as:

1. **String pattern**: A regular expression matched against node names from the start (Python `re.match`)
2. **Selector object**: A dict with `path`, `group_by`, and/or `match` fields

At least one of `path`, `group_by`, or `match` must be specified in a selector object.

#### String patterns

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
# Exact match
- source: "spine-1"

# Prefix match
- source: "dc1/spine/"

# Wildcard patterns
- source: "dc1/leaf.*"

# Anchored patterns
- source: "^dc1/spine/switch-[1-3]$"

# Alternation
- source: "^dc1/(spine|leaf)/.*$"
```

#### Capturing groups

Regex capturing groups create node groupings for analysis:

```text
# Single group: (dc\d+)
# Creates groups: "dc1", "dc2", etc.

# Multiple groups: (dc\d+)/(spine|leaf)/switch-(\d+)
# Creates groups: "dc1|spine|1", "dc1|leaf|2", etc.
```

**Group Behavior:**

- Single capturing group: Group by captured value
- Multiple capturing groups: Join with `|` separator
- No capturing groups: one group of every matched node, labelled by the pattern string

#### Attribute-based grouping

Use the `group_by` field to group nodes by an attribute value:

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
# Group by metro attribute
- source:
    group_by: "metro"

# Combine with path filtering
- source:
    path: "^dc1/.*"
    group_by: "role"
```

Notes:

- `group_by` refers to a top-level field (`name`, `disabled`, `risk_groups`) or a key in `node.attrs`. Nested (dot-notation) keys are not supported.
- Nodes without the specified attribute are omitted.
- Group labels are the string form of the attribute value.

#### Attribute-based filtering

Use the `match` field to filter nodes by attribute conditions:

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
source:
  path: "^dc1/.*"
  match:
    logic: "and"           # "and" or "or" (default: "or")
    conditions:
      - attr: "role"
        op: "=="
        value: "leaf"
      - attr: "tier"
        op: ">="
        value: 2
```

See [Conditions](#conditions) for the operators and the condition syntax.

#### Conditions

Every selection mechanism evaluates conditions the same way.

**1. Condition Structure**

Each condition has three fields:

<!-- example: fragment #/$defs/matchSpec -->

```yaml
conditions:
  - attr: "role"           # Attribute name (supports dot-notation)
    op: "=="               # Operator
    value: "leaf"          # Expected value
```

**2. Condition Operators**

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equals | `{attr: "role", op: "==", value: "leaf"}` |
| `!=` | Not equals | `{attr: "tier", op: "!=", value: 1}` |
| `<` | Less than (numeric) | `{attr: "cost", op: "<", value: 100}` |
| `<=` | Less than or equal | `{attr: "priority", op: "<=", value: 5}` |
| `>` | Greater than (numeric) | `{attr: "capacity", op: ">", value: 1000}` |
| `>=` | Greater than or equal | `{attr: "tier", op: ">=", value: 2}` |
| `contains` | String contains or collection includes | `{attr: "name", op: "contains", value: "spine"}` |
| `not_contains` | String/collection does not include | `{attr: "tags", op: "not_contains", value: "deprecated"}` |
| `in` | Value is in provided list | `{attr: "role", op: "in", value: ["leaf", "spine"]}` |
| `not_in` | Value is not in provided list | `{attr: "dc", op: "not_in", value: ["dc3", "dc4"]}` |
| `exists` | Attribute exists and is not null | `{attr: "hardware.vendor", op: "exists"}` |
| `not_exists` | Attribute missing or null | `{attr: "deprecated", op: "not_exists"}` |

Operator semantics:

- Ordering operators (`<`, `<=`, `>`, `>=`) compare integer and finite float operands exactly, including integers too large for a float. Other operands are coerced to float when possible, so `"10" > 5` is true; equality (`==`, `!=`) does **not** coerce, so `"10" == 10` is false. Keep attribute and condition value types consistent.
- For a missing or null attribute, every operator except `not_exists` returns false, including the negative ones (`!=`, `not_contains`, `not_in`). Use `not_exists` to match absent attributes.
- `in`/`not_in` require a list value; a scalar is refused where the condition is given (YAML at load, Python when the `Condition` is built).

**3. Condition Combining (`logic`)**

- `"or"` (default in most contexts): Any condition must match
- `"and"`: All conditions must match

<!-- example: fragment #/$defs/nodeSelector -->

```yaml
match:
  logic: "and"
  conditions:
    - {attr: "role", op: "==", value: "leaf"}
    - {attr: "tier", op: ">=", value: 2}
```

**4. Attribute Access**

Conditions evaluate against a flattened view of entity attributes:
- Node top-level fields: `name`, `disabled`, `risk_groups`
- Link top-level fields: `id`, `source`, `target`, `capacity`, `cost`, `disabled`, `risk_groups`
- Risk group top-level fields (rules with `scope: risk_group`): `name`, `disabled`, `children` (list of child group names)
- Custom attributes from `attrs` block (top-level fields take precedence on key conflicts)

**5. Dot-Notation for Nested Attributes**

Access nested attributes using dots:

<!-- example: fragment #/$defs/matchSpec -->

```yaml
conditions:
  - attr: "hardware.vendor"      # Resolves to attrs["hardware"]["vendor"]
    op: "=="
    value: "Acme"
```

**6. Variable Expansion**

Template expansion (`$var`, `${var}`) is processed before condition evaluation (see [Variable Expansion](#variable-expansion)).

#### Active-only filtering and context defaults

Use `active_only` to control whether disabled nodes are included:

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
# Override default to include disabled nodes in demands
- source:
    path: "^dc1/.*"
    active_only: false    # Include disabled nodes (overrides demand default of true)

# Override default to exclude disabled nodes in links
- source:
    path: "^dc1/.*"
    active_only: true     # Exclude disabled nodes (overrides link default of false)
```

Defaults differ by context and can be set explicitly per selector:

| Context | Selection | `active_only` default | `match.logic` default |
|---------|-----------|----------------------|----------------------|
| Links | Path-based | `false` (links to disabled nodes are created) | `"or"` |
| Demands | Path-based | `true` (only active nodes take traffic) | `"or"` |
| Node rules | Path-based | `false` | `"or"` |
| Workflow steps | Path-based | `true` (only the active topology is analyzed) | `"or"` |
| Membership rules | Condition-based | N/A | `"and"` |
| Failure rules | Condition-based | N/A | `"or"` |
| Generate blocks | Condition-based | N/A | N/A (no conditions; groups by values) |

Path-based selection supports capture groups, `group_by`, `match` and variable expansion, over nodes only. Condition-based selection scans nodes, links or risk groups with an optional `path` regex and no capture groups or variable expansion; `match` applies to membership and failure rules, and `group_by` to generate blocks.

#### How each context selects

##### Links

A link definition is processed in five steps:

1. **Path Selection**: Regex pattern matches nodes by hierarchical name
   - Capture groups create initial grouping
   - If no path specified, selects all nodes
2. **Attribute Filtering**: Optional `match` conditions filter nodes
   - Uses `logic: "and"` or `"or"` (default: `"or"`)
   - Operators are listed under [Conditions](#conditions)
3. **Active Filtering**: Filters disabled nodes based on context
   - Links default: `active_only=false` (creates links to disabled nodes)
4. **Attribute Grouping**: Optional `group_by` overrides regex capture grouping
5. **Pattern Application**: Creates links between selected node groups
   - `mesh`: Every source to every target
   - `one_to_one`: Pairwise with wrap-around

##### Demands

Traffic demands select nodes the same way as links, with these differences:

1. `active_only` defaults to `true`: only active nodes participate
2. Two selections, source nodes first and then target nodes, each with `path`, `match` and `group_by`
3. `mode` and `group_mode` decide how the selections produce demands ([Traffic Modes](#traffic-modes-mode), [Group Modes](#group-modes-group_mode))

##### Risk groups

Risk groups use the condition-based model and are populated in three ways:

1. **Direct definition**: the group is named and entities reference it
2. **Membership rules**: entities whose attributes match are assigned to the group
3. **Generate blocks**: one group per distinct value of an attribute

Membership rules and generate blocks scan every entity of their `scope`; an optional `path` regex narrows candidates by name (links match against their `source|target` form), `conditions` filter by attribute, and membership `logic` defaults to `and`.

#### Examples

A workflow step's selectors:

<!-- example: unprepared -->

```yaml
workflow:
  - type: MaxFlow
    source:
      group_by: "metro"      # Group by metro attribute
    target: "^metro2/.*"     # String pattern
    mode: "pairwise"
```

A link definition's selectors:

```yaml
network:
  nodes:
    dc1:
      nodes:
        spine: {count: 2, attrs: {role: spine}}
    dc2:
      nodes:
        leaf: {count: 2, attrs: {role: leaf}}
  links:
    - source:
        group_by: "role"
      target:
        path: "^dc2/leaf/.*"
      pattern: mesh
```

### Top-Level Keys

<!-- example: unprepared -->

```yaml
network: {}              # Network topology
blueprints: {}           # Reusable network templates
components: {}           # Hardware component library
risk_groups: []          # Failure correlation groups
vars: {}                 # YAML anchors and variables for reuse
demands: {}              # Traffic demand definitions
failures: {}             # Failure simulation policies
workflow: []             # Analysis execution steps
seed: 42                 # Scenario seed for reproducibility (integer)
units: {resolution: auto, precision: 0.001}  # Bandwidth unit q and input/count target
routes: {}               # Named explicit routes
supports: {}             # Named forwarding supports (DAGs)
weights: {}              # Named edge weights
routing:                 # IGP domain and BGP-edge routers for the WCMP controller
  igp_domain: {path: "^core"}
  bgp_edge: {path: "^edge"}
wcmp_controller: {scope: next_hop}  # WCMP controller scope
forwarding_groups: {}    # Fixed group shares at programmed routers
```

| Key | Required | Description |
|-----|----------|-------------|
| `network` | No | Network topology: nodes, links, and rules |
| `blueprints` | No | Reusable topology templates |
| `components` | No | Hardware component library for cost/power modeling |
| `risk_groups` | No | Failure correlation groups for resilience analysis |
| `vars` | No | YAML anchors for reuse within the scenario |
| `demands` | No | Traffic demand patterns for capacity analysis |
| `failures` | No | Failure policies for simulation |
| `workflow` | No | Analysis workflow steps to execute |
| `seed` | No | Scenario seed (integer) for reproducible random operations |
| `units` | No | Bandwidth unit `q` (`resolution`, `auto` by default) and input/count `precision` target ([Units](#units-and-input-validation)) |
| `routes` | No | Named explicit routes for `pinned` models |
| `supports` | No | Named forwarding supports (DAGs of directed links) |
| `weights` | No | Named edge-weight tables |
| `routing` | With `wcmp_controller` | IGP domain and BGP-edge populations ([WCMP controller](#routing-domains-and-the-wcmp-controller)) |
| `wcmp_controller` | No | Controller scope for `SHORTEST_PATHS_WCMP` demands |
| `forwarding_groups` | No | Declared group trees at routers the controller programs (needs `wcmp_controller`) |

All sections are optional. A scenario that omits `network` entirely, or sets it to an empty mapping (`network: {}`), builds with an empty topology. A bare `network:` with no value is a YAML null and fails schema validation. Any unrecognized top-level key is rejected during JSON Schema validation with a `ValueError` whose cause is the schema's `ValidationError` (the schema sets `additionalProperties: false`).


#### Seeds

A workflow step's failure draws use the step's seed: its own `seed`, or one derived from the scenario seed: the SHA-256 of the UTF-8 string `<seed>:workflow_step:<step-name>`, its first four bytes read as a big-endian integer and masked with `0x7fffffff`. A library `FailureRequest` that names a scenario policy and gives no seed of its own uses the policy's seed, derived the same way from `<seed>:failure_policy:failure_policy:<name>`: scenario seed `42` and policy `random_link` yield `2099469712`. Failure draw `i` creates `random.Random(base_seed + i)`; without a base seed every draw is unseeded and results vary between runs. A random rule fails each matched entity independently with its `probability`: one random number per entity, in sorted identifier order, the same on every supported Python. Results record the seed, where it came from, the runtime, the generator and the draw order.

### `network` - Topology

Nodes and links, written out directly or generated from node groups and link definitions.

**Network metadata fields:**

```yaml
network:
  name: "my-network"       # Optional network name (stored in network.attrs)
  version: "1.0"           # Optional version (stored in network.attrs)
  nodes: {}                # Node definitions (see below)
  links: []                # Link definitions (see below)
```

#### Direct Node and Link Definitions

**Individual Nodes:**

```yaml
network:
  nodes:
    SEA:
      disabled: true
      attrs:
        coords: [47.6062, -122.3321]
        hardware:
          component: "LeafRouter"
          count: 1
    SFO:
      attrs:
        coords: [37.7749, -122.4194]
        hardware:
          component: "SpineRouter"
          count: 1
```

Recognized keys for each node entry:

- `disabled`: boolean (optional)
- `attrs`: mapping of attributes (optional)
- `risk_groups`: list of risk-group names (optional)

**Individual Links:**

```yaml
network:
  nodes: {SEA: {}, SFO: {}}
  links:
    - source: SEA
      target: SFO
      capacity: 200
      cost: 6846
      attrs:
        distance_km: 1369.13
        media_type: "fiber"
        hardware:
          source: {component: "800G-ZR+", count: 1}
          target: {component: "1600G-2xDR4", count: 1}
```

Recognized keys for each link entry:

- `source`, `target`: node names (required)
- `capacity`: link capacity (optional; default 1.0)
- `cost`: link cost (optional; default 1), an integer from 1 to below 2^62; an exactly integral value such as `1.0` is stored as `1`, and any other value is refused where it is given
- `disabled`: boolean (optional)
- `risk_groups`: list of risk-group names (optional)
- `attrs`: mapping of attributes (optional)
- `count`: integer number of parallel links to create (optional; default 1); loading takes time linear in it

A link entry whose source or target matches no node is refused at load, naming its position and endpoints. Node and link rules that match nothing remain silent. Each physical link carries traffic in both directions ([Links, directions and what is enabled](https://networmix.github.io/NetGraph/concepts/#links-directions-and-what-is-enabled)).

#### Node Groups

**Node Groups with Count/Template:**

```yaml
network:
  nodes:
    leaf:
      count: 4
      template: "leaf-{n}"
      attrs:
        role: "leaf"
    spine:
      count: 2
      template: "spine-{n}"
      attrs:
        role: "spine"
```

Creates: `leaf/leaf-1`, `leaf/leaf-2`, `leaf/leaf-3`, `leaf/leaf-4`, `spine/spine-1`, `spine/spine-2`

Loading a node group takes work linear in its `count`. The `{n}` placeholder is replaced with a 1-indexed counter (1, 2, 3, ...) up to `count`. The group name becomes the parent path, and template generates child node names. When `count` is given without `template`, the template defaults to `<group>-{n}` (so `leaf: {count: 2}` creates `leaf/leaf-1` and `leaf/leaf-2`).

**Nested Nodes (Inline Hierarchy):**

Create hierarchical node structures without blueprints using nested `nodes`:

```yaml
network:
  nodes:
    dc1:
      nodes:                    # Inline nested hierarchy
        rack1:
          count: 4
          template: "srv-{n}"
          attrs:
            role: "server"
        rack2:
          count: 4
          template: "srv-{n}"
          attrs:
            role: "server"
        tor:
          count: 2
          template: "tor-{n}"
          attrs:
            role: "switch"
```

Creates: `dc1/rack1/srv-1`, `dc1/rack1/srv-2`, ..., `dc1/tor/tor-1`, `dc1/tor/tor-2`

Use nested nodes for one-off hierarchies. For structures repeated across the scenario, use blueprints.

**Link Definitions:**

```yaml
network:
  nodes:
    leaf: {count: 4}
    spine: {count: 2}
  links:
    - source: /leaf
      target: /spine
      pattern: "mesh"           # Connect every leaf to every spine
      capacity: 3200
      cost: 1
    - source: /spine
      target: /spine
      pattern: "mesh"           # Connect every spine to every other spine
      count: 2                   # Create 2 parallel links per pair (optional)
      capacity: 1600
      cost: 1
      attrs:
        hardware:
          source: {component: "800G-DR4", count: 2}
          target: {component: "800G-DR4", count: 2}
```

#### Attribute-filtered Links (selector objects)

To filter the source or target node sets by attributes, replace a string `source`/`target` with an object that has `path` and optional `match`. The condition syntax is the same as in failure policies:

```yaml
network:
  nodes:
    leaf: {count: 2, attrs: {role: leaf}}
    spine: {count: 2, attrs: {role: spine}}
  links:
    - source:
        path: "/leaf"
        match:
          logic: "and"         # default: "or"
          conditions:
            - attr: "role"
              op: "=="
              value: "leaf"
      target:
        path: "/spine"
        match:
          conditions:
            - attr: "role"
              op: "=="
              value: "spine"
      pattern: "mesh"
      capacity: 100
      cost: 1
```

Notes:

- `path` is a regex pattern matched against node names (anchored at start via Python `re.match`).
- `match.conditions` uses the shared condition operators: `==`, `!=`, `<`, `<=`, `>`, `>=`, `contains`, `not_contains`, `in`, `not_in`, `exists`, `not_exists`.
- Conditions evaluate over a flat view of node attributes combining top-level fields (`name`, `disabled`, `risk_groups`) and `node.attrs`.
- `logic` in the `match` block accepts "and" or "or" (default "or").
- Selectors filter node candidates before the link `pattern` is applied.
- Cross-endpoint predicates (e.g., comparing a source attribute to a target attribute) are not supported.
- Node rules run before link expansion; link rules run after link creation.

Path semantics:

- All paths are relative to the current scope. There is no concept of absolute paths.
- A leading `/` is stripped, so `/leaf` and `leaf` are equivalent.
- Within a blueprint, paths resolve relative to the instantiation path. For example, if a blueprint is used under group `pod1`, then `source: /leaf` resolves to `pod1/leaf`.
- At top-level `network.links`, the parent path is empty, so patterns match against full node names.

Example with OR logic to match multiple roles:

```yaml
network:
  nodes:
    metro1:
      nodes:
        dc1: {attrs: {role: dc}}
        pop1: {attrs: {role: leaf}}
        pop2: {attrs: {role: core}}
  links:
    - source:
        path: "/metro1/dc[1-1]"
        match:
          conditions:
            - attr: "role"
              op: "=="
              value: "dc"
      target:
        path: "/metro1/pop[1-2]"
        match:
          logic: "or"
          conditions:
            - attr: "role"
              op: "=="
              value: "leaf"
            - attr: "role"
              op: "=="
              value: "core"
      pattern: "mesh"
```

**Connectivity Patterns:**

- `mesh`: Full connectivity between all source and target nodes
- `one_to_one`: Pairwise connections. Compatible sizes means max(|S|,|T|) must be an integer multiple of min(|S|,|T|); mapping wraps modulo the smaller set (e.g., 4x2 and 6x3 valid; 3x2 invalid). Self-pairs are skipped, so `one_to_one` between a group and itself creates no links; use `mesh` to interconnect a group with itself.

#### Bracket Expansion

Create multiple similar node groups using bracket notation:

```yaml
network:
  nodes:
    dc[1-3]/rack[a,b]:     # Creates dc1/racka, dc1/rackb, dc2/racka, etc.
      count: 4
      template: "srv-{n}"
```

**Expansion Types:**

- Numeric ranges: `[1-4]` -> 1, 2, 3, 4
- Explicit lists: `[red,blue,green]` -> red, blue, green
- Mixed expressions: `[1,3,5-7]` -> 1, 3, 5, 6, 7
- Multiple brackets: Cartesian product of all brackets

<!-- example: fragment #/properties/network/properties/nodes -->

```yaml
# Multiple brackets produce cartesian product
dc[1-2]/rack[a,b]: {}   # Creates: dc1/racka, dc1/rackb, dc2/racka, dc2/rackb
```

**Scope:** Bracket expansion applies to:

- **Node names** under `network.nodes` and `blueprints.*.nodes`, including direct single-node entries without count/template (`SEA[1-2]: {}` creates nodes `SEA1` and `SEA2`)
- **Risk group names** in top-level `risk_groups` definitions (including children)
- **Risk group membership arrays** on nodes, links, node groups, and in node/link rules

Component names and other string fields treat brackets as literal characters. (Link `source`/`target` strings are regexes, where `[...]` is a character class, not bracket expansion.)

**Risk Group Expansion Examples:**

```yaml
# Definition expansion - creates DC1_Power, DC2_Power, DC3_Power
risk_groups:
  - name: "DC[1-3]_Power"
  - name: "RG[1-3]"        # Defines RG1, RG2, RG3 (referenced below)

# Membership expansion - assigns to RG1, RG2, RG3
network:
  nodes:
    Server:
      risk_groups: ["RG[1-3]"]
```

**Limitations and Workarounds:**

| Pattern | Behavior | Workaround |
|---------|----------|------------|
| `[01-03]` | Produces `1, 2, 3` (no leading zeros) | Use explicit list: `[01,02,03]` |
| `[A-C]` | Error (letter ranges not supported) | Use explicit list: `[A,B,C]` |
| `[1-10]` | Produces `1, 2, ..., 10` | Works correctly |

The range syntax `[start-end]` only supports integers. For letters, mixed sequences, or zero-padded numbers, use comma-separated explicit lists.

#### Variable Expansion

Use `$var` or `${var}` syntax with an `expand` block for template substitution. Variables are recursively substituted in all string fields within the block, including nested `attrs`.

**Type preservation:** A value consisting of exactly one placeholder (e.g. `value: "${t}"`) is replaced by the variable's native value, preserving its type, so `match` conditions compare correctly against numeric node/link attributes. Placeholders embedded in longer strings (e.g. `"dc${dc}_internal"`) interpolate as text and always produce strings. A bare placeholder bound to a non-string variable used where a path selector is required (e.g. `source: "${n}"` with `n: [1, 2]`) raises `ValueError` instead of being silently stringified; use an embedded form such as `"dc${n}/leaf"` for selector strings.

**Supported contexts:**

- Link definitions (`network.links` and `blueprints.*.links`)
- Link rules (`network.link_rules`)
- Node rules (`network.node_rules`)
- Traffic demands (`demands.*`)

**Expansion modes:**

| Mode | Behavior | Example |
|------|----------|---------|
| `cartesian` (default) | All combinations of variable values | `p:[1,2]`, `r:[a,b]` → 4 expansions |
| `zip` | Pair values by index (lists must have equal length) | `a:[1,2]`, `b:[x,y]` → 2 expansions |

**Cartesian expansion and reversed pairs:** Each variable combination of an `expand` block is an independent link definition. Reversed-pair deduplication applies only within one combination, so cartesian expansion over symmetric variable lists (e.g. `vars: {a: [1, 2], b: [1, 2]}` with `source: "dc${a}/gw"`, `target: "dc${b}/gw"`) creates *both* orientations as separate parallel links, doubling capacity. To mesh one node set, prefer a single mesh definition with a regex selector (e.g. `source: "dc[0-9]+/gw"`, `target: "dc[0-9]+/gw"`, `pattern: mesh`), which deduplicates reversed pairs.

**Example in links:**

<!-- example: fragment #/properties/network -->

```yaml
links:
  - source: "plane${p}/rack${r}"
    target: "spine${s}"
    expand:
      vars:
        p: [1, 2]
        r: ["a", "b"]
        s: [1, 2, 3]
      mode: "cartesian"  # 2 × 2 × 3 = 12 link definitions
    pattern: "mesh"

  - source: "server${idx}"
    target: "switch${idx}"
    expand:
      vars:
        idx: [1, 2, 3, 4]
      mode: "zip"        # 4 paired link definitions
    pattern: "one_to_one"
```

**Variables in nested attributes:**

<!-- example: fragment #/properties/network -->

```yaml
links:
  - source: "${dc}/leaf"
    target: "${dc}/spine"
    expand:
      vars:
        dc: ["dc1", "dc2"]
    attrs:
      datacenter: "${dc}"      # Also substituted
      corridor: "${dc}_internal"
    pattern: "mesh"
```

**Limits:** Expansion is capped at 10,000 items per block to prevent accidental combinatorial explosion.

### `blueprints` - Reusable Templates

Templates for network segments, instantiated as many times as needed:

```yaml
blueprints:
  leaf_spine:
    nodes:
      leaf:
        count: 4
        template: "leaf-{n}"
      spine:
        count: 2
        template: "spine-{n}"
    links:
      - source: /leaf
        target: /spine
        pattern: mesh
        capacity: 40
        cost: 1

network:
  nodes:
    pod1:
      blueprint: leaf_spine
    pod2:
      blueprint: leaf_spine
      params:                    # Override blueprint parameters
        leaf.count: 6
        spine.template: "core-{n}"
```

Instance names are prefixed with the group name: `pod1/leaf/leaf-1`, `pod2/spine/core-1`.

**Parameter override rules:**

- Override keys must be of the form `<group>.<field>`, where `<group>` is a literal (unexpanded) subgroup name defined in the blueprint. Unknown group prefixes or bare keys (no dot) raise `ValueError` at scenario build time.
- Override keys are matched against literal blueprint subgroup names by the longest `<group>.` prefix (not by splitting on the first dot), so subgroup names containing dots (e.g. `rack.a`) are addressable as `rack.a.count`. When one subgroup name is a dotted extension of another (e.g. `rack` and `rack.a`), the longest matching name receives the override.
- To override parameters of a nested blueprint, use a dict value under `<group>.params`:

```yaml
blueprints:
  leaf_spine:
    nodes:
      leaf:
        count: 4
      spine:
        count: 2
  two_pod_dc:
    nodes:
      pod1:
        blueprint: leaf_spine
      pod2:
        blueprint: leaf_spine

network:
  nodes:
    dc1:
      blueprint: two_pod_dc
      params:
        pod1.params:             # Dict-valued pass-through to the nested blueprint
          spine.count: 8
```

The dotted form `pod1.params.spine.count` is rejected.

### Node and Link Rules

Modify specific nodes or links after initial creation. Rules run post-expansion and can override properties, add attributes, or disable elements.

#### Node Rules

```yaml
network:
  node_rules:
    # Simple path-based matching
    - path: "^pod1/spine/.*$"
      disabled: true
      attrs:
        maintenance_mode: "active"

    # Path with attribute filtering
    - path: "^dc1/.*"
      match:
        logic: "and"
        conditions:
          - attr: "role"
            op: "=="
            value: "leaf"
          - attr: "tier"
            op: ">="
            value: 2
      attrs:
        priority: "high"

    # Variable expansion for repeated rules
    - path: "^${dc}/rack1/.*"
      expand:
        vars:
          dc: ["dc1", "dc2", "dc3"]
      attrs:
        zone: "${dc}_zone1"
```

**Node rule fields:**

- `path`: Regex pattern matched against node names (optional; defaults to `.*`, matching all nodes)
- `match`: Optional attribute conditions to filter matched nodes
- `disabled`: Set node disabled state
- `attrs`: Attributes to merge into matched nodes
- `risk_groups`: Risk groups for matched nodes; **replaces** the node's existing `risk_groups` set (it does not add to it)
- `expand`: Variable expansion block for templated rules

#### Link Rules

```yaml
network:
  link_rules:
    # Basic endpoint matching
    - source: "^pod1/leaf/.*$"
      target: "^pod1/spine/.*$"
      capacity: 100

    # Bidirectional matching (default: true)
    - source: ".*/spine/.*"
      target: ".*/spine/.*"
      bidirectional: true
      cost: 5
      attrs:
        link_type: "backbone"

    # Filter by link's own attributes using link_match
    - source: "^dc1/.*"
      target: "^dc2/.*"
      link_match:
        logic: "and"
        conditions:
          - attr: "link_type"
            op: "=="
            value: "inter_dc"
          - attr: "capacity"
            op: ">="
            value: 100
      cost: 10
      attrs:
        priority: "high"

    # Variable expansion
    - source: "^${src}/.*"
      target: "^${dst}/.*"
      expand:
        vars:
          src: ["dc1", "dc2"]
          dst: ["dc2", "dc3"]
        mode: "zip"
      attrs:
        corridor: "${src}_to_${dst}"
```

**Link rule fields:**

- `source`, `target`: Regex patterns or selector objects for endpoint matching (both required on every rule)
- `bidirectional`: Match links in both directions (default: `true`)
- `link_match`: Filter by link's own attributes (not endpoint attributes)
- `capacity`, `cost`, `disabled`: Override link properties, by the same rules as a link declaration
- `attrs`: Attributes to merge into matched links
- `risk_groups`: Risk groups for matched links; **replaces** the link's existing `risk_groups` set (it does not add to it)
- `expand`: Variable expansion block for templated rules

**Execution order:**

1. `node_rules` run after node creation but before link expansion
2. `link_rules` run after all links are created

### `components` - Hardware Library

Define hardware components with attributes for cost and power modeling. A component’s `count` is a positive integer whose conversion to float is finite, checked when the component is declared:

```yaml
components:
  SpineRouter:
    component_type: "chassis"
    description: "64-port spine router"
    capex: 50000.0
    power_watts: 2500.0
    power_watts_max: 3000.0
    capacity: 64000.0           # Gbps
    ports: 64
    attrs:
      vendor: "VendorName"
      model: "Model-9000"
    children:
      LineCard400G:
        component_type: "linecard"
        capex: 8000.0
        power_watts: 400.0
        capacity: 12800.0
        ports: 32
        count: 4

  Optic400G:
    component_type: "optic"
    description: "400G pluggable optic"
    capex: 2500.0
    power_watts: 12.0
    capacity: 400.0
    attrs:
      reach: "10km"
      wavelength: "1310nm"
```

**Component Usage:**

```yaml
network:
  nodes:
    spine-1:
      attrs:
        hardware:
          component: "SpineRouter"
          count: 2   # Optional positive multiplier; defaults to 1
    leaf-1: {}
  links:
    - source: spine-1
      target: leaf-1
      attrs:
        hardware:
          source: {component: "Optic400G", count: 4}
          target: {component: "Optic400G", count: 4}
```

`hardware`, and each of a link's `source` and `target`, must be a mapping (`null` counts as absent). `count` (default 1) must be a finite positive number that fits a float, whether or not the node or link is enabled; the `CostPower` step and the network explorer refuse any other value with a `ValueError` naming the node or link end (for example `link a|b|0 source end: ...`), before any capacity or port check. A link end counts only where its endpoint node has hardware. A link end's `exclusive` must be a boolean: `true` marks its hardware as not shared with other links; the explorer's bill of materials then rounds that end's count up to a whole unit, while cost, power and ports use the declared count. Hardware totals too large for a finite float are refused with the entity and field named. Bill-of-materials counts are float sums: integer counts are exact while a total stays at most 2^53.

### `risk_groups` - Risk Modeling

Risk groups model correlated failures as hierarchies: physical infrastructure, geographic regions, vendor dependencies, or custom domains.

Identical repeated inline group declarations resolve once. Conflicting inline attributes, disabled flags, membership declarations or child declarations refuse with both parent paths. A registered top-level declaration takes precedence over inline references of the same name.

#### Hierarchy

Risk groups form parent-child trees that model **cascading failures**:

```yaml
risk_groups:
  - name: "Region_West"
    children:
      - name: "Site_Seattle"
      - name: "Site_Portland"
```

**Cascading semantics:** When a parent fails, all descendants fail with it: a regional outage takes every site in the region.

**Storage model:** Children are nested within parents, not in the top-level dictionary:

```python
from ngraph import Scenario

scenario = Scenario.from_yaml("""
risk_groups:
  - {name: Region_West, children: [{name: Site_Seattle}, {name: Site_Portland}]}
""")
assert list(scenario.network.risk_groups) == ["Region_West"]
region = scenario.network.risk_groups["Region_West"]
assert [child.name for child in region.children] == ["Site_Seattle", "Site_Portland"]
```

**String shorthand:** an entry that is a bare string defines a group with that name and no other fields: `- "Region_West"` is equivalent to `- name: "Region_West"`. The same shorthand works inside `children`.

**Disabled groups:** `disabled: true` on a top-level group disables every member node and link at scenario load, including members of its descendant groups. This runs after membership rules and generate blocks, so entities assigned by those mechanisms are covered.

**Top-level-only keys:** `membership`, `disabled`, and `generate` are honored only on top-level `risk_groups` entries. Nested `children` entries allow only `name`, `attrs`, and `children`; placing any other key on a child is rejected by the JSON schema at scenario load and by the parser with `ValueError`. Define such groups at top level and reference them by name as children.

**Entity references:** a node or link names the risk groups it belongs to. Any declared group can be named: a top-level group, or a child at any depth with no top-level entry of its own. A failed group fails its own members and the members of every group below it:

```yaml
risk_groups:
  - name: Region_West
    children:
      - name: Site_Seattle
      - name: Site_Portland

network:
  nodes:
    Router_SEA: {risk_groups: [Site_Seattle]}
    Router_PDX: {risk_groups: [Site_Portland]}
    Router_SFO: {}
  links:
    - {source: Router_SEA, target: Router_PDX, capacity: 10}
    - {source: Router_PDX, target: Router_SFO, capacity: 10, risk_groups: [Region_West]}
```

Failing `Site_Seattle` fails `Router_SEA`; failing `Region_West` fails `Router_SEA`, `Router_PDX` and the link `Router_PDX|Router_SFO|0`.

#### Example 1: Physical Infrastructure (Fiber Links)

For fiber links, a hierarchy of Path -> Conduit -> Fiber Pair mirrors the physical plant.

```yaml
risk_groups:
  # Each conduit declared once, with its attributes
  - name: "Conduit_NYC_CHI_C[1-2]"
    attrs:
      type: fiber_conduit

  # The hierarchy names them as its children: its failure fails theirs
  - name: "Path_NYC_CHI"
    attrs:
      type: fiber_path
      distance_km: 1200
    children:
      - name: "Conduit_NYC_CHI_C[1-2]"

network:
  nodes:
    NYC: {}
    CHI: {}
  links:
    - source: NYC
      target: CHI
      risk_groups: ["Conduit_NYC_CHI_C1"]
      attrs:
        fiber:
          path_id: "NYC-CHI"
          conduit_id: "NYC-CHI-C1"
```

**Cascading behavior:**

- Fiber pair failure affects only that pair
- Conduit failure affects all pairs in that conduit
- Path failure affects all conduits in that path

#### Example 2: Physical Infrastructure (Data Center Nodes)

For data center nodes, a hierarchy of Building -> Room -> Power Zone mirrors the facility.

```yaml
risk_groups:
  # Each power zone declared once, with its attributes
  - name: "PowerZone_DC1_R1_PZ[A,B]"
    attrs:
      type: power_zone

  # The hierarchy names them under the rooms: a room's or the building's failure
  # fails theirs
  - name: "Building_DC1"
    attrs:
      type: building
      location: "Ashburn, VA"
    children:
      - name: "Room_DC1_R[1-3]"
        attrs:
          type: room
        children:
          - name: "PowerZone_DC1_R1_PZ[A,B]"

network:
  nodes:
    Router_DC1_R1_RK01:
      risk_groups: ["PowerZone_DC1_R1_PZA"]
      attrs:
        facility:
          building_id: "DC1"
          room_id: "DC1-R1"
          power_zone: "DC1-R1-PZ-A"
```

**Cascading behavior:**

- Power zone failure affects equipment in that zone
- Room failure affects all zones in that room
- Building failure affects entire site

#### Example 3: Geographic/Administrative Grouping

For geographic or administrative modeling:

```yaml
risk_groups:
  - name: "Region_West"
    attrs:
      type: geographic
    children:
      - name: "AZ_US_West_1a"
      - name: "AZ_US_West_1b"
  - name: "MaintenanceWindow_Weekend"
    attrs:
      type: operational
      schedule: "Sat-Sun 02:00-06:00 UTC"
```

#### Membership Rules

Assign entities to a risk group by attribute:

```yaml
risk_groups:
  - name: Conduit_NYC_CHI_C1
    membership:
      scope: link
      match:
        logic: and           # "and" or "or" (default: "and")
        conditions:
          - attr: fiber.conduit_id
            op: "=="
            value: "NYC-CHI-C1"

  - name: PowerZone_DC1_R1_PZA
    membership:
      scope: node
      match:
        logic: and
        conditions:
          - attr: facility.power_zone
            op: "=="
            value: "DC1-R1-PZ-A"
```

Membership rules default to `logic: "and"`, stricter than link and demand selectors, which default to `"or"`.

A membership rule requires `scope` plus at least one of `path` or `match`; a `match` block must contain at least one condition. The optional `path` regex pre-filters candidates by name before conditions are evaluated (links match against their `source|target` form).

#### Generated Risk Groups

One risk group per distinct attribute value:

```yaml
risk_groups:
  # Generate risk groups from fiber path attributes on links
  - generate:
      scope: link
      group_by: fiber.path_id
      name: Path_${value}
      attrs:
        type: fiber_path

  # Generate risk groups from facility attributes on nodes
  - generate:
      scope: node
      group_by: facility.building_id
      name: Building_${value}
      attrs:
        type: building
```

A generate block requires `scope` (`node` or `link`), `group_by` (supports dot-notation), and `name`; `name` must contain the `${value}` placeholder. An optional `path` regex pre-filters entities by name (links match against their `source|target` form). Errors raised as `ValueError`: a `group_by` attribute resolving to an unhashable value (e.g. a list), a name template rendering the same group name for two distinct attribute values, and a generated name colliding with an existing risk group. Generate blocks run after membership resolution, so membership rules cannot match generated groups.

#### Validation

Risk group references are validated at scenario load time:

**Undefined Reference Detection:** All risk group names referenced by nodes and links must exist in the `risk_groups` section. This catches typos and missing definitions early:

<!-- example: refusal unknown risk groups 'PowerZone_A' -->

```yaml
# This will fail validation
network:
  nodes:
    Router1:
      risk_groups: ["PowerZone_A"]  # References undefined risk group

risk_groups:
  - name: "PowerZone_B"  # Only PowerZone_B is defined
```

**Circular Hierarchy Detection:** Parent-child relationships cannot form cycles:

<!-- example: refusal risk group cycle: GroupA -> GroupB -> GroupA -->

```yaml
# This will fail validation
risk_groups:
  - name: "GroupA"
    children:
      - name: "GroupB"
  - name: "GroupB"
    children:
      - name: "GroupA"  # Error: circular reference
```

Membership follows nested descendants at any depth, including groups with no top-level entry and parent-child links added by membership rules with `scope: risk_group`, and a cycle among them is refused. A loop through groups declared only inline (A → B → C → B) is refused too, as a conflicting declaration of the repeated name. A group's node members and link members are kept apart, so a node name and a link id that happen to be equal never stand for each other.

Error messages name the affected entities and the undefined groups.

### `vars` - YAML Anchors

Reusable values through YAML anchors (`&name`) and aliases (`*name`):

```yaml
vars:
  default_cap: &cap 10000
  base_attrs: &attrs {cost: 100, region: "dc1"}
  spine_config: &spine_cfg
    hardware:
      component: "SpineRouter"
      count: 1
    power_budget: 2500

network:
  nodes:
    spine-1: {attrs: {<<: *attrs, <<: *spine_cfg, capacity: *cap}}
    spine-2: {attrs: {<<: *attrs, <<: *spine_cfg, capacity: *cap, region: "dc2"}}
```

**Anchor Types:**

- **Scalar**: `&cap 10000` - Reference primitive values
- **Mapping**: `&attrs {cost: 100}` - Reference objects
- **Merge**: `<<: *attrs` - Merge a mapping; explicit keys win

**Processing Behavior:**

- Anchors are resolved during YAML parsing, before schema validation
- The `vars` section itself is ignored by NetGraph runtime logic
- Anchors can be defined in any section, not just `vars`
- Merge semantics (as parsed by PyYAML): explicit keys override merged keys regardless of position; with repeated `<<:` merge keys, later merges override earlier ones, while the sequence form `<<: [*a, *b]` gives earlier entries precedence

### `demands` - Traffic Demands

Named demand sets, each a list of demands:

```yaml
demands:
  production:
    # Simple string pattern selectors
    - source: "^servers/.*"
      target: "^storage/.*"
      volume: 1000
      mode: "combine"
      priority: 1
      preset: "SHORTEST_PATHS_ECMP"

    # Dict selectors with attribute-based grouping
    - source:
        group_by: "dc"           # Group nodes by datacenter attribute
      target:
        group_by: "dc"
      volume: 500
      mode: "pairwise"
      group_mode: "group_pairwise"  # Node pairs between different datacenters
      priority: 2

    # Dict selectors with filtering
    - source:
        path: "^dc1/.*"
        match:
          conditions:
            - attr: "role"
              op: "=="
              value: "leaf"
      target:
        path: "^dc2/.*"
        match:
          conditions:
            - attr: "role"
              op: "=="
              value: "spine"
      volume: 200
      mode: "combine"
```

#### Variable Expansion in Demands

Use an `expand` block to generate multiple demands from a template:

```yaml
demands:
  inter_dc:
    - source: "^${src_dc}/.*"
      target: "^${dst_dc}/.*"
      volume: 100
      mode: "combine"
      expand:
        vars:
          src_dc: ["dc1", "dc2"]
          dst_dc: ["dc3", "dc4"]
        mode: "cartesian"  # All 4 combinations (the default)

    - source: "^${dc}/leaf/.*"
      target: "^${dc}/spine/.*"
      volume: 50
      mode: "pairwise"
      expand:
        vars:
          dc: ["dc1", "dc2", "dc3"]
        mode: "zip"        # 3 demands, paired by index
```

**Expansion Modes:**

- `cartesian`: All combinations of variable values (default)
- `zip`: Pair values by index (lists must have equal length)

#### Demand Fields

| Field | Type | Description |
|-------|------|-------------|
| `source` | string or selector | Source node selector (required) |
| `target` | string or selector | Target node selector (required) |
| `volume` | number | The declaration's total traffic, a physical amount (default: 0): the pairs and groups it expands into share it, and each `expand` combination has the whole total ([Demands: how traffic enters](https://networmix.github.io/NetGraph/concepts/#demands-how-traffic-enters)) |
| `priority` | integer | Priority class; lower = higher priority (default: 0) |
| `mode` | string | Node pairing mode: `combine` or `pairwise` (default: `combine`) |
| `group_mode` | string | How grouped nodes produce demands (default: `flatten`) |
| `id` | string | Optional nonempty run-unique identity |
| `preset` | string | Declared preset name ([Presets](#presets)); omission selects `SHORTEST_PATHS_ECMP`. Exclusive with `model` |
| `model` | object | Explicit routing and admission declaration ([Routing models and admission](https://networmix.github.io/NetGraph/concepts/#routing-models-and-admission)); see below |
| `attrs` | object | Arbitrary metadata |
| `expand` | object | Variable expansion block |

A demand without an `id` gets `<set>|<n>`, where `n` counts the set's declarations before expansion; an `expand` leaf adds `|<its index>`, and each row adds `|<its index in the expansion>`. Ids are unique across the run's demand sets: a collision, declared or generated, is refused naming both.

#### Named routes and explicit models

Named routes are declared once and compiled on the prepared graph. A Pinned model references their names in declaration order, retaining duplicates and route weights.

<!-- example: unprepared -->

```yaml
routes:
  via_b:
    head: A
    nodes: [A, B, C]
    weight: 3
  via_d:
    head: A
    edges:
      - {link: "A|D|0", direction: forward}
      - {link: "D|C|0", direction: forward}
    weight: 2
demands:
  traffic:
    - source: ^A$
      target: ^C$
      volume: 10
      model:
        admission: lossless
        routing: {type: pinned, routes: [via_b, via_d]}
```

Each route specifies its source `head` and exactly one of `nodes`, directed `edges`, or a named DAG `support`. Node paths and edge paths must be nonempty simple contiguous routes with the declared head and selected destination. A node hop takes the cheapest enabled parallel link between its two nodes, ties to the smaller link id; a disabled link in an edge path, or a node hop with no enabled link, is refused. A route is fixed when it is prepared: failures never move it.

Path routes use their declared nonnegative integer weights, default 1; a route of weight 0 is still checked in full. In `converged` and `repair` states, routes touching failed nodes or links are removed and the head splits its offer over the surviving routes by weight. In `stale`, the baseline program is replayed lossy at the baseline admitted total: its split stays fixed, and traffic reaching a failed element is lost there. A head with no surviving route loses its traffic. The compiled paths themselves stay fixed. Two demands with the same endpoints, model and priority stay distinct when their ids differ. Combine and pairwise are both supported when the route endpoints match the resolved question.

`supports` and `weights` are separate named namespaces:

<!-- example: unprepared -->

```yaml
supports:
  through_b:
    edges:
      - {link: "A|B|0", direction: forward}
      - {link: "B|C|0", direction: forward}
weights:
  explicit_split:
    entries:
      - edge: {link: "A|B|0", direction: forward}
        value: 3
```

A support must be an acyclic directed graph without duplicate edges. Unlisted explicit edge weights are 0. A support route uses `support: through_b`; a Pinned DAG model can declare `allocation: equal` or `weighted`, with `weight_basis: capacity` or `explicit` as applicable and `edge_weights` naming the explicit vector. Named Pinned DAGs refuse `residual_snapshot`. Path-only routes do not accept DAG split controls.

Other routing models use `type: shortest_paths`, `distributed_te` or `centralized_te`. For example:

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
model:
  admission: lossless
  routing:
    type: shortest_paths
    allocation: weighted
    weight_basis: capacity
    tie_break: fewer_hops
    multipath: true
    parallel_edges: true
```

| `routing.type` | Keys |
|----------------|------|
| `shortest_paths` | `allocation` (`equal` by default, `weighted` or `optimized`), `source_allocation` (`equal` or `optimized`), `weight_basis` (`capacity`, `explicit` or `residual_snapshot`), `edge_weights` (a name in `weights`), `tie_break`, `multipath`, `parallel_edges` |
| `distributed_te` | `tunnel_count: {per_head: N}` (required), `min_unreserved_bandwidth` (a physical amount), `cost_ceiling`, `tie_break`, `parallel_edges` |
| `centralized_te` | `source_allocation` (`optimized` or `equal`, required), `tunnel_count: {per_head: N}` with optional `up_to: true`, `prefer_headroom` |
| `pinned` | `routes`, and for a DAG `allocation`, `weight_basis` and `edge_weights` (above) |

`admission` is `lossless` (the default) or `lossy`. `cost_ceiling` is `{type: absolute, value: C}` or `{type: stretch, value: "3/2"}`; stretch values are exact: integers, fraction strings (`"3/2"`) or decimal strings (`"1.16"`), never rounded to a binary64 value, and the ceiling is inclusive. A key the routing type does not have, or a `per_head` outside 1 to 10000, is refused at load; preparation refuses combinations the engine does not accept, such as `weight_basis` without `allocation: weighted`. What each model does: [Routing models and admission](https://networmix.github.io/NetGraph/concepts/#routing-models-and-admission) and [Tunnels and TE ingress pools](https://networmix.github.io/NetGraph/concepts/#tunnels-and-te-ingress-pools).

#### Routing domains and the WCMP controller

A WCMP controller programs every `SHORTEST_PATHS_WCMP` demand toward one BGP-edge router with one destination-wide
weight table per demand set and destination:

<!-- example: unprepared -->

```yaml
routing:
  igp_domain: {path: '^(A|B)[12]$'}
  bgp_edge: {path: '^DC_'}
wcmp_controller: {scope: group}      # next_hop (default) | group | all_routers
forwarding_groups:
  ingress:
    router: DC_A
    groups:
      - children: [{edge: {link: 'DC_A|A1|0', direction: forward}}]
      - share: "1/2"
        children: [{edge: {link: 'DC_A|A2|0', direction: forward}}]
```

Both populations are required, nonempty and disjoint (selected like demand endpoints, so disabled nodes are outside
them). A programmed demand has one destination, in `bgp_edge`, and its sources lie in either population.
`wcmp_controller.scope` is `next_hop` (the default), `group` or `all_routers`. The routes the controller uses and what
each scope programs: [Routing domains and the WCMP controller](https://networmix.github.io/NetGraph/concepts/#routing-domains-and-the-wcmp-controller)
and [Forwarding groups and their caps](https://networmix.github.io/NetGraph/concepts/#forwarding-groups-and-their-caps).

Under `group`, every programmed router needs a tree whose leaves are exactly its members toward t, and every declared
tree must be used, so a tree at a router the controller never programs is refused, while a source with no route (an
empty DAG) is not programmed and needs none; under `next_hop` and `all_routers` trees are validated and unused. Shares
are exact: an integer, a `"p/q"` or decimal string (YAML floats are refused); a positive share whose children all have
share 0 is refused.

Placement and maximum supported demand (MSD) results report the tables under `controller`; a router not listed there splits by ECMP. These are
the tables of the network without failures; in a failure case the converged state computes its own tables, which are
not exported ([Failures: patterns, cases and states](https://networmix.github.io/NetGraph/concepts/#failures-patterns-cases-and-states)).

##### Weight approximation

Weights whose exact reduced integers reach 2^62 are apportioned over 2^62 - 1 (one unit for each positive member, then
highest averages, earlier member on ties) and reported in `units_report.weight_approximations` with the exact largest
relative error: one entry per router (`controller.<set>.<t>.router.<r>`) and, under `all_routers`, one per source
vector, naming the source with the largest error (`controller.<set>.<t>.source.<s>`). Source weights are the volumes'
exact binary values reduced to integers, so volumes 1000 and 0.1 (whose binary value has a 2^55 denominator) are
apportioned and reported, while 1000000 and 1 stay exact.

#### Selector Fields

The `source` and `target` fields accept either:

- A string regex pattern matched against node names
- A selector object with `path`, `group_by`, and/or `match` fields

[Selecting nodes](#selecting-nodes) describes both.

#### Traffic Modes (`mode`)

Controls how source and target node sets are paired:

- `combine`: One source-set/destination-set demand, with one ordered roster of sources ([Demands: how traffic enters](https://networmix.github.io/NetGraph/concepts/#demands-how-traffic-enters)).
- `pairwise`: Create one demand for each distinct selected source/target node pair. Node-to-itself pairs receive no share.

A matrix whose sources and targets share nodes, such as all pairs of four sites, needs each shared node in a group of its own on both sides, for example by capturing each name (`^(A|B|C|D)$`) or with `group_by: name`. The declared volume is split over the pairs:

```yaml
network:
  nodes: {A: {}, B: {}, C: {}, D: {}}
  links:
    - {source: A, target: B, capacity: 10}
    - {source: B, target: C, capacity: 10}
    - {source: C, target: D, capacity: 10}
    - {source: D, target: A, capacity: 10}
demands:
  matrix:
    # 12 ordered pairs of distinct sites, 48 / 12 = 4 each
    - {source: "^(A|B|C|D)$", target: "^(A|B|C|D)$", volume: 48, mode: pairwise}
workflow:
  - {type: TrafficMatrixPlacement, name: matrix, demand_set: matrix}
```

A pattern without a capturing group makes one group of all its nodes, so the same matrix written `source: "^[ABCD]$"`, `target: "^[ABCD]$"` is refused:

<!-- example: refusal non-diagonal source/target overlap: ['A', 'B', 'C', 'D'] -->

```yaml
network:
  nodes: {A: {}, B: {}, C: {}, D: {}}
demands:
  matrix:
    - {source: "^[ABCD]$", target: "^[ABCD]$", volume: 48, mode: pairwise}
workflow:
  - {type: TrafficMatrixPlacement, name: matrix, demand_set: matrix}
```

Overlapping source and target groups are refused in demands, capacity and path questions (no target is silently dropped), except a pair that is one and the same node: a demand gives it no share, and capacity and path questions give it a zero-valued `self` row. A declaration whose every pair is a node-to-itself pair or a same-label group pair is reported whole as discarded, with its reason. If a declaration is excluded for both reasons, the first exclusion in canonical group and node order supplies its reason. A selection that matches no active node keeps its share as an `empty_selection` discard; a group whose nodes are all filtered out is not selected and takes no share ([Demands: how traffic enters](https://networmix.github.io/NetGraph/concepts/#demands-how-traffic-enters)).

#### Group Modes (`group_mode`)

When using `group_by` selectors, controls how grouped nodes produce demands:

- `flatten` (default): Flatten all groups into a single source/target set, then apply `mode`
- `per_group`: Create one branch per source group with combined targets, or pairwise node branches within labels shared by both selectors. Branches whose only pairs are node-to-itself pairs receive no share; non-diagonal overlap refuses, and an empty branch keeps its discarded share.
- `group_pairwise`: Split across ordered source/target group pairs with distinct labels; identical labels receive no share. Apply the selected node mode within each remaining group pair

**Example with `group_mode`:**

```yaml
demands:
  inter_dc_traffic:
    # Each DC pair gets its own demand
    - source:
        group_by: "dc"
      target:
        group_by: "dc"
      volume: 1000
      mode: "combine"
      group_mode: "group_pairwise"    # Creates dc1->dc2, dc2->dc1, dc1->dc3, etc.
```

| `mode` | `group_mode` | Result |
|--------|--------------|--------|
| `combine` | `flatten` | Single aggregated demand across all nodes |
| `combine` | `per_group` | One demand per source group (targets combined) |
| `combine` | `group_pairwise` | One demand per (source_group, target_group) pair with distinct labels |
| `pairwise` | `flatten` | Individual demands for distinct node pairs |
| `pairwise` | `per_group` | Distinct node pairs within each shared label |
| `pairwise` | `group_pairwise` | Distinct node pairs within each distinct-label group pair |

Each declared physical total is converted to units once, then split over its eligible pairs by integer quotient and remainder; declared units equal resolved plus discarded units ([Demands: how traffic enters](https://networmix.github.io/NetGraph/concepts/#demands-how-traffic-enters)).

#### Presets

Demands that omit both `preset` and `model` use `SHORTEST_PATHS_ECMP`. A `MaxFlow` step that omits both asks unrestricted optimized lossless maximum flow (`TE_MAXFLOW_UNLIM`), in YAML and Python. Each preset is one explicit `model`:

| Preset | `model` equivalent | Question |
|--------|--------------------|----------|
| `SHORTEST_PATHS_ECMP` | `{routing: {type: shortest_paths}, admission: lossless}` | IP/IGP routing with equal splits among equal-cost next hops at each router; what does not fit is not admitted, and a filled next hop can block later demands assigned to it |
| `SHORTEST_PATHS_ECMP_LOSSY` | `{routing: {type: shortest_paths}, admission: lossy}` | The same routing with best-effort forwarding: traffic is sent and lost at sources and on edges |
| `SHORTEST_PATHS_WCMP` | `{routing: {type: shortest_paths, allocation: weighted, weight_basis: capacity}}` | Capacity-weighted static shortest-path routing with lossless equal source allocation; with a `wcmp_controller`, the controller's table instead (a MaxFlow step then refuses this preset) |
| `SHORTEST_PATHS_MAXFLOW` | `{routing: {type: shortest_paths, allocation: optimized, source_allocation: optimized}}` | Optimized capacity on the union of the selected shortest-path supports |
| `TE_MAXFLOW_UNLIM` | `{routing: {type: centralized_te, source_allocation: optimized}}` | Unrestricted optimized lossless traffic engineering |
| `TE_ECMP_16_LSP` | `{routing: {type: centralized_te, source_allocation: optimized, tunnel_count: {per_head: 16}, prefer_headroom: true}}` | Controller tunnels (T2), exactly 16 per head |
| `TE_ECMP_UP_TO_256_LSP` | `{routing: {type: centralized_te, source_allocation: optimized, tunnel_count: {per_head: 256, up_to: true}, prefer_headroom: true}}` | Controller tunnels (T2), up to 256 per head |

What each model does: [Routing models and admission](https://networmix.github.io/NetGraph/concepts/#routing-models-and-admission); tunnel counts: [Tunnels and TE ingress pools](https://networmix.github.io/NetGraph/concepts/#tunnels-and-te-ingress-pools).

### `failures` - Failure Policies

Named failure policies:

```yaml
failures:
  single_link_failure:
    modes:                       # Weighted modes; each draw picks exactly one
      - weight: 1.0
        rules:
          - scope: "link"
            mode: "choice"
            count: 1

  weighted_modes:                # Example of weighted multi-mode policy
    modes:
      - weight: 0.30
        rules:
          - scope: "risk_group"
            mode: "choice"
            count: 1
            weight_by: distance_km

      - weight: 0.35
        rules:
          - scope: "link"
            mode: "choice"
            count: 3
            match:                       # Attribute conditions inside match block
              logic: "and"
              conditions:
                - attr: "link_type"
                  op: "=="
                  value: "dc_to_pop"
            weight_by: target_capacity

      - weight: 0.25
        rules:
          - scope: "node"
            path: "^dc[1-3]/.*"          # Path filter (regex)
            mode: "choice"
            count: 1
            match:
              logic: "and"
              conditions:
                - attr: "node_type"
                  op: "!="
                  value: "dc_region"
            weight_by: attached_capacity_gbps

      - weight: 0.10
        rules:
          - scope: "link"
            mode: "choice"
            count: 4
            match:
              logic: "or"                # Any condition matches
              conditions:
                - attr: "link_type"
                  op: "=="
                  value: "leaf_spine"
                - attr: "link_type"
                  op: "=="
                  value: "intra_group"
                - attr: "link_type"
                  op: "=="
                  value: "inter_group"
```

#### Policy-Level Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `modes` | array | required | List of weighted failure modes |
| `attrs` | object | `{}` | Policy metadata (e.g., description) |
| `expand_groups` | boolean | `false` | Also fail every node and link that shares a risk group with a failed one, whether a node, link or risk-group rule failed it (the members of a failed risk group fail with or without this flag) |

A failed risk group always cascades to its child groups recursively.

Each entry of `modes` accepts `weight` (required, non-negative), `rules` (required) and optional `attrs`; mode `attrs` are recorded as `mode_attrs` in failure traces.

**Risk group expansion example:**

```yaml
failures:
  srlg_failures:
    expand_groups: true      # Spread failures across shared risk-group memberships
    attrs:
      description: "Shared-risk link group failure simulation"
    modes:
      - weight: 1.0
        rules:
          - scope: "risk_group"
            mode: "choice"
            count: 1
```

#### Selection Modes

- `all`: Select all matching entities
- `choice`: Select specific count of entities (optionally weighted)
- `random`: Select each entity independently with given probability

#### Rule Fields

| Field | Type | Description |
|-------|------|-------------|
| `scope` | string | Entity type: `node`, `link`, or `risk_group` (required) |
| `mode` | string | Selection mode: `all`, `choice`, or `random` (default: `all`) |
| `count` | integer | Number of entities to select (for `choice` mode), at least 1 |
| `probability` | number | Selection probability 0-1 (for `random` mode) |
| `path` | string | Regex filter on entity name (links match against their `source\|target` form) |
| `match` | object | Attribute conditions block with `logic` and `conditions` |
| `weight_by` | string | Attribute name for weighted sampling in `choice` mode |

#### Notes

- Each mode has a non-negative `weight`. Each draw picks one mode with probability proportional to the weights, applies all its rules and fails the union of their selections.
- At least one mode must have `weight > 0`; a policy whose modes all have zero weight is refused where the policy is built, in Python and YAML. Modes with zero weight are never selected.
- Condition syntax uses the same operators as link/demand selectors. See [Conditions](#conditions) for the full reference.

### `workflow` - Analysis Steps

The ordered list of analysis steps:

<!-- example: unprepared -->

```yaml
workflow:
  - type: NetworkStats
    name: network_statistics
  - type: MaximumSupportedDemand
    name: msd_baseline
    demand_set: baseline_traffic_matrix
  - type: TrafficMatrixPlacement
    name: tm_placement
    demand_set: baseline_traffic_matrix
    failure_policy: weighted_modes
    iterations: 1000
```

**Built-in steps:**

- `BuildGraph`: Export graph to JSON (node-link) for external analysis
- `NetworkStats`: Node, link, capacity and degree statistics
- `MaxFlow`: Capacity between node sets, optionally under failure draws
- `TrafficMatrixPlacement`: Placement of a named demand set, optionally under failure draws
- `MaximumSupportedDemand`: Search for the largest tested feasible alpha (the demand multiplier) for a named demand set ([Maximum supported demand](https://networmix.github.io/NetGraph/concepts/#maximum-supported-demand))
- `CostPower`: Aggregate capex and power by network hierarchy level
- `TunnelCountAnalysis`: Rows per tunnel count for the tunnelled TE demands of a named demand set

See [Workflow Steps](#workflow-steps) for detailed configuration.

## Workflow Steps

`Scenario.from_yaml(text)` parses an ordered workflow. Python callers execute `run(prepare(scenario))`; the returned `RunResult.steps` tuple holds each step's name, type, execution order, where its seed came from, normalized question and typed result. Duplicate names refuse before execution; step names longer than 100 characters are refused.

An unnamed YAML step receives `<type>_<declaration index>`. A step seed is explicit or derived from the scenario seed and effective step name ([Seeds](#seeds)). Results are returned only after the complete workflow succeeds; `ngraph run --keys` exports selected steps after the whole workflow runs ([Filtering Results by Step Names](https://networmix.github.io/NetGraph/reference/cli/#filtering-results-by-step-names)). The domain steps are separate from the analyses: `BuildGraph` provides physical NetworkX node-link data, `NetworkStats` describes topology, and `CostPower` (with the `NetworkExplorer`) presents hardware metrics. Built-in steps are immutable records ([Records and editing](https://networmix.github.io/NetGraph/reference/api/#records-and-editing)); custom steps and result exporters: [Custom steps and exporters](https://networmix.github.io/NetGraph/reference/api/#custom-steps-and-exporters).

### Keys common to analysis steps

| Key | Steps | Default | Meaning |
|-----|-------|---------|---------|
| `failure_policy` | MaxFlow, TrafficMatrixPlacement | none | A policy name from `failures`; each distinct drawn failure set is one case ([Failures: patterns, cases and states](https://networmix.github.io/NetGraph/concepts/#failures-patterns-cases-and-states)) |
| `iterations` | MaxFlow, TrafficMatrixPlacement | 1 | The number of failure draws |
| `failure_trace` | MaxFlow, TrafficMatrixPlacement | `false` | Record the first draw that produced each failure pattern |
| `workers` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | `auto` | `auto` or a positive number of worker threads |
| `seed` | every step | derived | The step's seed ([Seeds](#seeds)) |
| `outputs` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis, MaximumSupportedDemand | all off | Optional outputs ([Output selection](#output-selection)) |

Capacity and traffic-matrix placement resolve `workers: auto` to the CPU count; explicit positive worker counts override it, and results are the same for any number of workers. MaximumSupportedDemand (MSD) searches for the largest tested feasible alpha and runs serially ([Maximum supported demand](https://networmix.github.io/NetGraph/concepts/#maximum-supported-demand)).

### BuildGraph

```yaml
workflow:
  - type: BuildGraph
    name: topology
    add_reverse: true
```

Returns `BuildGraphResult` with node and edge counts (`edge_count` is two per link with reverse edges) and physical NetworkX node-link JSON. Reverse export edges are enabled by default. This operation exports the domain network, including disabled entities and their flags.

### NetworkStats

```yaml
workflow:
  - type: NetworkStats
    name: stats
    include_disabled: false
    excluded_nodes: []
    excluded_links: []
```

Returns physical node/link counts and capacity, cost and degree statistics. The question records these effective filters. An excluded node or link name that the network does not have is refused at preparation.

### CostPower

Each level groups the nodes by the first parts of their `/`-separated names. A level deeper than the deepest node name repeats the rows of that deepest level.

```yaml
workflow:
  - type: CostPower
    name: hardware
    include_disabled: false
    aggregation_level: 2
```

Returns hardware rows grouped by hierarchy level, with platform and link-end optics capex/power. The aggregation level is a nonnegative integer. The network explorer and `inspect` validate hardware too, and all of them read one hardware inventory: an optic counts only where its endpoint node has hardware, `include_disabled: false` keeps enabled nodes and links whose two end nodes are enabled, and invalid hardware (see the DSL `components` section) is refused in either view.

### MaxFlow

<!-- example: unprepared -->

```yaml
workflow:
  - type: MaxFlow
    name: ideal_capacity
    source: ^site1/leaf/
    target: ^site2/leaf/
    mode: combine
    preset: TE_MAXFLOW_UNLIM
    failure_policy: random_link
    iterations: 100
    workers: auto
    failure_trace: false
    outputs:
      min_cut: true
      cost_distribution: true
```

| Key | Default | Meaning |
|-----|---------|---------|
| `source`, `target` | required | Selectors of the two node sets ([Selecting nodes](#selecting-nodes)) |
| `mode` | `combine` | `combine` asks one source-set/destination-set question; `pairwise` one per selector-group pair |
| `preset` or `model` | `TE_MAXFLOW_UNLIM` | The model to ask ([Presets](#presets); [Routing models and admission](https://networmix.github.io/NetGraph/concepts/#routing-models-and-admission)); the two are exclusive |
| `offer`, `design_demand` | none | Physical inputs whose applicability follows the declared model |

The default question is unrestricted optimized lossless capacity. Choose `SHORTEST_PATHS_ECMP`, `SHORTEST_PATHS_WCMP`, `SHORTEST_PATHS_MAXFLOW` or an explicit `model` for another question. The result names the question asked (`question`) and where its offer came from (`offer_source`):

| `question` | When | What it asks |
|------------|------|--------------|
| `lossless_bound` | lossless admission and no `offer` | The most the model delivers without loss |
| `fixed_offer_delivery` | an `offer` is given, or a lossy tunnelled `centralized_te` model has a `design_demand` | What the model delivers of that offer (`offer_source` `explicit` or `design`) |
| `first_hop_experiment` | lossy shortest-path routing and no `offer` | What arrives of an offer the Core derives from the sources' first hops |

In `pairwise` mode a source group and a target group that are the same single node give a zero-valued `self` row; any other overlap of source and target groups is refused.

The result holds the cases in order, each with its rows under `states.converged`; each row holds the engine's result. Cuts, edge arrays and cost reports appear only when requested ([Output selection](#output-selection); the kinds of cost report: [Results and their units](https://networmix.github.io/NetGraph/concepts/#results-and-their-units)).

### TrafficMatrixPlacement

<!-- example: unprepared -->

```yaml
workflow:
  - type: TrafficMatrixPlacement
    name: traffic
    demand_set: peak
    alpha: 1
    failure_policy: random_link
    iterations: 100
    failure_states: [converged, stale]
    interaction: ordered
    workers: auto
    outputs: {cost_distribution: true}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `demand_set` | required | The demand set to place |
| `alpha`, `alpha_from_step` | alpha 1 | The demand multiplier, or the MSD step that supplies it |
| `failure_states` | `[converged]` | The failure states each case reports: `converged`, `stale`, `repair` |
| `interaction` | `ordered` | `ordered` or `simultaneous` placement |

Places the demand set, by default in priority order, then declaration order. Each row has a stable id, its endpoints, its reference request and the engine's result; each state adds totals, and the result adds each declaration's accounting of declared, resolved and discarded units. A failure changes which nodes and links can be used, never a declared volume ([Failures: patterns, cases and states](https://networmix.github.io/NetGraph/concepts/#failures-patterns-cases-and-states)).

Each case reports the requested `failure_states`, each computed separately: `converged` computes the demands again on the failed network (declared group shares stay fixed caps, and dead caps are listed), `stale` forwards each baseline program unchanged and lossy, and `repair` re-splits the baseline programs over the surviving routes. A state whose bounded forwarding calculation cycles or reaches its round limit reports a forwarding failure with no rows. Group scope refuses `converged` and `repair` under a failure policy when it programs a router inside the IGP domain. The full rules: [Failures: patterns, cases and states](https://networmix.github.io/NetGraph/concepts/#failures-patterns-cases-and-states).

`interaction: simultaneous` forwards every demand at once, sharing losses on common links, as a lossy question on fixed programs; its rows are not comparable with the default `ordered` rows. A simultaneous step that takes its alpha from an MSD step cannot have pool demands. The full rules: [Ordered and simultaneous placement](https://networmix.github.io/NetGraph/concepts/#ordered-and-simultaneous-placement).

Use either `alpha` or `alpha_from_step`, never both. Omitting both uses 1. `alpha_from_step` names an earlier MSD step and places at its largest tested feasible alpha. Preparation refuses a name that is not an earlier MSD step; the placement refuses, when it runs, an MSD result with no feasible alpha. The placement records the MSD step's name and the alpha it used (`alpha_source`, `alpha`).

### MaximumSupportedDemand

<!-- example: unprepared -->

```yaml
workflow:
  - type: MaximumSupportedDemand
    name: supported_load
    demand_set: peak
    alpha_start: 1
    growth_factor: 2
    alpha_min: 0.000001
    alpha_max: 1000000000
    alpha_tolerance: 0.01
    max_bracket_iters: 32
    max_bisect_iters: 32
  - type: TrafficMatrixPlacement
    name: tested_load
    demand_set: peak
    alpha_from_step: supported_load
```

Searches for the largest tested alpha at which the demand set is placed in full, keeping every probe ([Maximum supported demand](https://networmix.github.io/NetGraph/concepts/#maximum-supported-demand)). `alpha_start`, `growth_factor`, `alpha_min` and `alpha_max` bound the search, `alpha_tolerance` ends it, and `max_bracket_iters` and `max_bisect_iters` cap its two phases; the example shows the defaults. `alpha_feasible` is null if no probe was feasible. `search_status` and `stop_reason` say how and why the search ended (each value: [Maximum supported demand](https://networmix.github.io/NetGraph/concepts/#maximum-supported-demand)). MSD takes no failure input: the step refuses `failure_policy`, `iterations` and `failure_states`, and its probes place the set without failures. To place the alpha it finds under failures, give a later placement `alpha_from_step` and a `failure_policy`, as the [Tutorial](https://networmix.github.io/NetGraph/getting-started/tutorial/) does.

When a demand set offers no traffic because all declared volumes are zero or every positive volume is discarded, MSD makes one probe at `alpha_max`. If that probe succeeds, it reports `trivial`, with `proof` and `stop_reason` both `nothing_offered`, and retains discard accounting. If scaling the discarded volume exceeds the native integer-unit range or binary64, the probe is refused and MSD reports `range` with `stop_reason` `offer_range`. A positive demand that merely rounds to zero is still searched as `below_resolution`.

An MSD probe is `below_resolution` if any resolved leaf of a positive declaration requests zero units after scaling and expansion, even when the declaration's rounded total is positive. It is never an accepted feasible probe or certificate endpoint; search moves upward from it. Before stopping on tolerance with no feasible probe and a below-resolution lower bracket end, MSD tests the first alpha where every such leaf receives at least one unit, found from rounding alone; an already tested endpoint is reused. It continues if feasible. If no feasible probe is found this way, it reports `none_feasible` with stop reason `unit_resolution`; iteration limits keep `bracket_limit` or `bisect_limit`.

### TunnelCountAnalysis

```yaml
units: {resolution: 1}
network:
  nodes: {S: {}, a: {}, b: {}, T: {}}
  links:
    - {source: S, target: T, capacity: 1, cost: 1}
    - {source: S, target: T, capacity: 100, cost: 2}
    - {source: a, target: T, capacity: 2, cost: 1}
    - {source: b, target: T, capacity: 10, cost: 1}
demands:
  te:
    - {id: pooled, source: '^S$', target: '^T$', volume: 0, preset: TE_ECMP_16_LSP}
    - id: heads
      source: '^(a|b)$'
      target: '^T$'
      volume: 0
      model:
        routing: {type: centralized_te, source_allocation: equal, tunnel_count: {per_head: 1}}
        admission: lossless
workflow:
  - type: TunnelCountAnalysis
    name: counts
    demand_set: te
    counts: [2]
    up_to: 3
    design_demand: 2
    offer: 1000
    workers: auto
    outputs: {details: false}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `demand_set` | required | A set of tunnelled `centralized_te` demands |
| `counts` | none | Distinct tunnel counts per head, each from 1 to 10000 |
| `up_to` | none | The limit of the "up to" row |
| `design_demand`, `offer` | required | The physical design and offer for every demand of the set |

Evaluates every demand of the set once per listed tunnel count, then once "up to" the `up_to` limit, each row a fresh native evaluation of the demand's centralized-TE model with that count, lossy at `offer` and planned for `design_demand`. Every demand of the set uses the same `design_demand` and `offer`; the rows read no declared volume. The set must hold tunnelled centralized-TE demands only (`centralized_te` with a `tunnel_count`, or the `TE_ECMP_16_LSP` and `TE_ECMP_UP_TO_256_LSP` presets); any other model is refused at preparation. Self pairs and same-label group pairs do not create demands; empty selections and entirely excluded declarations have no tunnel-count rows.

Rows follow the set's demands, then the listed counts in order, then the `up_to` row. A row's `count` is the requested count per head (for the `up_to` row, its limit); the chosen count is `plan.tunnels_per_head`. The `plan` (fluid and whole-unit tunnel size, planned bandwidth, tunnel cost, headroom penalty, the largest lossless offer and `insufficient_resolution`) is written in every row; `result` holds what the offer delivers and loses. `lossless_at_design_units` is the lossless delivery at the design, min(design, largest lossless offer). Rows are not monotone in the count, and "up to" picks the smallest count that carries the live heads' design shares, not the count that delivers most of the offer.

The example fixes `q` to 1; its report has `limited_by: declared` and the input/count budget exceeds the default target ([Precision and the choice of q](https://networmix.github.io/NetGraph/concepts/#precision-and-the-choice-of-q)). In it, the pooled demand delivers 1 + 100 of its offer of 1000 with two tunnels (one per link) and its up-to row chooses one tunnel, on the wide link; the two heads deliver 2 + 10 with two tunnels each and choose one. A pool row's `plan.total_tunnel_cost` is on the analysis graph: its `pool` section's `synthetic_ingress_cost` of 1 is paid once per tunnel, which `physical_tunnel_cost` leaves out (3 and 2 here).

The step's offer is a known lossy offer for the TE ingress pools of its set, and it and the design take part in choosing the bandwidth unit `q` ([Units and the resolution q](https://networmix.github.io/NetGraph/concepts/#units-and-the-resolution-q); [Tunnels and TE ingress pools](https://networmix.github.io/NetGraph/concepts/#tunnels-and-te-ingress-pools)). Naming the set makes it part of the run's prepared traffic like any step's set: its declared volumes and models still take part in choosing `q` and are validated at preparation.

### Output selection

| `outputs` key | Steps | Adds to each row |
| --- | --- | --- |
| `edge_flows` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | the units each directed link carries |
| `residual` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | each directed link's residual capacity after the row; under simultaneous placement, the one final residual every row shares |
| `edge_reservations` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | each directed link's tunnel holds |
| `saturated_boundary_edges` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | the saturated links at the sources' reachable boundary |
| `min_cut` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis | the minimum cut closest to the sources, where defined (unrestricted optimized maximum flow); null otherwise |
| `cost_distribution` | MaxFlow, TrafficMatrixPlacement | the cost report: delivered units per path cost, or the native marginal cost curve |
| `details` | MaxFlow, TrafficMatrixPlacement, TunnelCountAnalysis, MaximumSupportedDemand | native per-source, per-tunnel, plan and call fields |

All are false by default. Every row field is described in the [Results](https://networmix.github.io/NetGraph/reference/results/) reference.

Each output is selected on its own: `outputs: {details: false, min_cut: true}` gives compact rows with a cut, and `outputs: {details: true}` gives the detail fields without a cost report or cut. Omitted outputs, `{}` and `details: false` give compact rows; `details` accepts only a boolean. A row's `pool` is present either way, so a TE ingress pool's attachment cost stays identifiable. `MaximumSupportedDemand` accepts only `details`, which applies to its best rows; its probe history stays compact. Python spells the detail selector `export_details` (refused in YAML), and only Python can export every probe's rows (`MSDQuery.export_probe_rows`). `details` shapes only the JSON: Python results always hold the detail fields. Every other output exists only when requested, in Python as in JSON.

The results schema enforces each row's applicable detail fields: they are absent with `details: false` and present with `details: true`. A native result's `plan` is null when no tunnel plan applies; a tunnel-count row keeps `plan` at row level rather than inside `result`. Compact rows keep their drop totals: `edge_drop_units` sums losses on physical links and TE ingress pool attachments.
