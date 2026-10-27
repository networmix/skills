---
name: netgraph-dsl
description: >
  NetGraph scenario DSL for defining network topologies, traffic demands, failure policies,
  and analysis workflows in YAML. Use when: creating or editing .yaml/.yml network scenarios,
  defining nodes/links/groups, writing link rules with patterns, configuring selectors or blueprints,
  setting up traffic demands or failure policies, running scenarios and interpreting results,
  debugging DSL syntax or validation errors, or asking about NetGraph scenario structure.
---

# NetGraph scenarios

NetGraph analyzes how traffic flows through a network. A scenario is one YAML file that holds:

- the **network**: nodes (routers, sites) and the links between them;
- the **demands**: traffic from some nodes to others;
- the **failure policies**: what can fail, and how failures are drawn;
- the **workflow**: the questions to ask, in order, such as "how much can flow from A to B?"

`ngraph inspect` checks a scenario; `ngraph run` answers its questions and writes the results as
JSON.

More detail:

- [references/REFERENCE.md](references/REFERENCE.md): every key, copied from NetGraph's
  Scenario YAML and Workflow Steps pages.
- [references/EXAMPLES.md](references/EXAMPLES.md): complete scenarios.
- How the numbers are computed: https://networmix.github.io/NetGraph/concepts/

## How to work

1. Start from the smallest scenario below and add one section at a time.
2. Run `ngraph inspect scenario.yaml` after each change and fix what it reports.
3. Run `ngraph run scenario.yaml` and read `scenario.results.json`.
4. If something fails or surprises you, see [Common mistakes](#common-mistakes) and
   [Errors and their fixes](#errors-and-their-fixes).

## The smallest useful scenario

Two sites, one link, a demand of 50, and two questions: how far the demand can grow, and how it
is placed.

```yaml
network:
  nodes:
    A: {}
    B: {}
  links:
    - source: A
      target: B
      capacity: 100
      cost: 1

demands:
  peak:
    - source: "^A$"
      target: "^B$"
      volume: 50

workflow:
  - type: MaximumSupportedDemand
    name: msd
    demand_set: peak
  - type: TrafficMatrixPlacement
    name: placement
    demand_set: peak
```

## Top-level sections

All sections are optional. An unknown key is refused, anywhere in the file.

| Key | What it holds |
|-----|---------------|
| `network` | Nodes, links, and rules that change them |
| `blueprints` | Reusable pieces of topology |
| `components` | Hardware (cost, power) for the `CostPower` step |
| `risk_groups` | Sets of nodes and links that fail together |
| `vars` | YAML anchors to reuse values; NetGraph ignores the section itself |
| `demands` | Named demand sets |
| `failures` | Named failure policies |
| `workflow` | The ordered analysis steps |
| `seed` | An integer that makes random failure draws repeatable |
| `units` | The bandwidth unit `q` and the precision target ([Units](#units-and-results)) |
| `routes`, `supports`, `weights` | Named explicit routes, route graphs and link weights for `pinned` models |
| `routing`, `wcmp_controller`, `forwarding_groups` | A routing domain, a WCMP controller and its fixed group shares |

The last two rows are for special routing models; see REFERENCE.md when you need them.

## Network

### Nodes and links

```yaml
network:
  nodes:
    Seattle:
      attrs:                 # your own data goes under attrs
        role: core
      risk_groups: ["RG1"]   # every risk group named here must be declared
    Portland:
      attrs:
        role: edge
  links:
    - source: Seattle
      target: Portland
      capacity: 100          # default 1
      cost: 10               # an integer from 1; default 1
      count: 2               # two parallel links
      attrs:
        distance_km: 280

risk_groups:
  - "RG1"
```

- Basic node fields are `attrs`, `risk_groups` and `disabled`. Basic link fields are `source`,
  `target`, `capacity`, `cost`, `count`, `attrs`, `risk_groups` and `disabled`. Groups,
  patterns and expansion add the fields described below. Put your own data under `attrs`.
- A link carries traffic both ways, with its full capacity in each direction.
- A link's id is `source|target|n`, where `n` counts the links between that pair from 0. The
  example makes `Seattle|Portland|0` and `Seattle|Portland|1`.
- A link is usable only when it and both of its end nodes are enabled.

### Node groups and names

A group creates `count` nodes under the group's name. `{n}` in `template` counts from 1:

```yaml
network:
  nodes:
    leaf:
      count: 4
      template: "leaf-{n}"
      attrs:
        role: leaf
    spine:
      count: 2              # no template: names are spine/spine-1, spine/spine-2
```

This creates `leaf/leaf-1` to `leaf/leaf-4`, `spine/spine-1` and `spine/spine-2`. Names are
paths: each level is separated by `/`. A group can also hold its own `nodes`, to build a deeper
hierarchy without a blueprint ([Example 21](references/EXAMPLES.md#example-21-nested-nodes-without-a-blueprint)).

### Three kinds of templates

Each works in its own place only:

| Syntax | Example | Where | Effect |
|--------|---------|-------|--------|
| `[1-3]` | `dc[1-3]/rack[a,b]` | Node and risk group names | One definition per value |
| `$var`, `${var}` | `pod${p}/leaf` | Links, rules, demands with an `expand` block | Replaced by each value of `var` |
| `{n}` | `srv-{n}` | A group's `template` | 1, 2, ... up to `count` |

Brackets expand only in node names, risk group names, and the risk group lists of nodes, links
and rules. Elsewhere, such as in a link's `source`, `[...]` is a regular-expression character
class. Several brackets give every combination: `dc[1-3]/rack[a,b]` makes `dc1/racka`,
`dc1/rackb`, `dc2/racka` and so on. A range takes integers only: `[01-03]` gives `1, 2, 3`;
write `[01,02,03]` to keep zeros.

### Links between groups

A link's `source` and `target` are regular expressions over node names. `pattern` decides which
of the matched nodes are joined:

- `mesh` (the default): every source node to every target node.
- `one_to_one`: pairs in order, wrapping around the smaller set. The larger size must be a
  multiple of the smaller (4 to 2 works, 3 to 2 is refused). A node is never joined to itself.

```yaml
network:
  nodes:
    leaf: {count: 4}
    spine: {count: 2}
  links:
    - source: /leaf
      target: /spine
      pattern: mesh         # 8 links
      capacity: 100
```

A link whose source or target matches no node is refused. A leading `/` is ignored; inside a
blueprint, names are relative to where the blueprint is placed.

### Repeating a definition with `expand`

An `expand` block repeats a link, rule or demand for each value of its variables:

<!-- example: fragment #/properties/network -->

```yaml
links:
  - source: "plane${p}/rack"
    target: "spine${s}"
    expand:
      vars:
        p: [1, 2]
        s: [1, 2, 3]
      mode: cartesian       # every combination (default); zip pairs values by position
    pattern: mesh
```

`zip` needs lists of equal length. A block that would make more than 10,000 copies is refused.
A value that is only a placeholder (`"${t}"`) keeps its type, so a number stays a number.

### Blueprints

A blueprint is a piece of topology you can place many times. Each placement prefixes its names:

```yaml
blueprints:
  clos_pod:
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
        capacity: 100

network:
  nodes:
    pod[1-2]:
      blueprint: clos_pod
      params:
        leaf.count: 6       # change one field of one group, for this placement
```

This creates `pod1/leaf/leaf-1` and so on. A `params` key is `<group>.<field>`, with a group
name from the blueprint; any other key is refused.

### Node and link rules

Rules change nodes and links after they are created: disable them, change capacity or cost, add
attributes.

```yaml
network:
  nodes:
    pod1: {nodes: {spine: {count: 2}, leaf: {count: 2, attrs: {role: compute}}}}
    pod2: {nodes: {spine: {count: 2}}}
  links:
    - {source: pod1/leaf, target: pod1/spine, capacity: 400}
    - {source: pod1/spine, target: pod2/spine, capacity: 100}
  node_rules:
    - path: "^pod1/leaf/"
      match:                         # optional: only nodes whose attributes match
        conditions:
          - {attr: role, op: "==", value: compute}
      attrs: {maintenance: true}
  link_rules:
    - source: "^pod1/"
      target: "^pod1/"
      link_match:                    # optional: filter by the link's own attributes
        conditions:
          - {attr: capacity, op: ">=", value: 400}
      cost: 5
```

- Node rules run before links are created; link rules run after.
- A link rule matches links in both directions unless `bidirectional: false`.
- A rule that matches nothing changes nothing and is not an error.
- A rule's `risk_groups` replaces the node's or link's list; it does not add to it.

## Selecting nodes

Links, demands, workflow steps and node rules pick nodes with a **selector**. It can be a
string or an object.

A string is a regular expression matched from the **start** of the name (Python `re.match`):

| Pattern | Matches |
|---------|---------|
| `leaf` | `leaf`, `leaf-1`, and also `leafy` |
| `^leaf$` | only `leaf` |
| `.*leaf` | any name containing `leaf` |
| `^dc1/(spine\|leaf)/` | spines and leaves of dc1 |

**Groups.** A selection is divided into groups, and demands and capacity questions work group
by group. Each capture group `(...)` adds to a node's group label; several captures are joined
with `|`. Without a capture, all matched nodes form one group, labelled by the pattern.

An object can combine `path` (the expression), `match` (attribute conditions), `group_by` (an
attribute that labels the groups instead) and `active_only` (whether disabled nodes count). It
needs at least one of `path`, `group_by` and `match`.

<!-- example: fragment #/properties/demands/additionalProperties/items -->

```yaml
- source:
    path: "^dc1/"
    group_by: role          # one group per value of attrs.role
    match:
      logic: and            # every condition must hold; "or": any one
      conditions:
        - {attr: role, op: "!=", value: spare}
        - {attr: tier, op: ">=", value: 2}
```

**Conditions.** `attr` names a field (a node's `name`, `disabled`, `risk_groups`; a link's
`id`, `source`, `target`, `capacity`, `cost`, `disabled`, `risk_groups`) or a key under
`attrs`, with dots for nested keys (`hardware.vendor`). Operators: `==`, `!=`, `<`, `<=`, `>`,
`>=`, `contains`, `not_contains`, `in`, `not_in` (a list value), `exists`, `not_exists`.

- `==` never converts types: `"10" == 10` is false.
- A missing or null attribute makes every operator false, `!=` and `not_in` included, except
  `not_exists`.

**Defaults differ by place:**

| Place | `match.logic` | `active_only` |
|-------|---------------|---------------|
| Links | `or` | `false`: links to disabled nodes are created |
| Node rules | `or` | `false` |
| Demands | `or` | `true`: disabled nodes take no traffic |
| Workflow steps | `or` | `true` |
| Risk group membership rules | `and` | not used |
| Failure rules | `or` | not used |

Failure rules and risk group rules select differently: they scan nodes, links or risk groups
(`scope`), may filter names with `path`, and filter by `match` (generate blocks group by an
attribute instead). They have no capture groups and no `$var` templates. A link's name for
`path` is `source|target`.

## Risk groups

A risk group is a set of nodes and links that fail together, such as the fibers in one conduit
or the routers on one power feed. There are three ways to fill one.

**Name it, and list it on nodes and links:**

```yaml
risk_groups:
  - name: Conduit_1
  - "Conduit_2"             # a plain name works too
  - name: Region_West
    children:               # a failed parent fails its children
      - name: Site_SEA

network:
  nodes:
    SEA: {risk_groups: [Site_SEA]}
    PDX: {}
  links:
    - {source: SEA, target: PDX, risk_groups: [Conduit_1]}
```

**A membership rule** adds every node or link whose attributes match:

<!-- example: fragment # -->

```yaml
risk_groups:
  - name: HighCapacityLinks
    membership:
      scope: link           # node, link or risk_group
      match:
        conditions:
          - {attr: capacity, op: ">=", value: 1000}
```

**A generate block** makes one group per distinct value of an attribute:

<!-- example: fragment # -->

```yaml
risk_groups:
  - generate:
      scope: node           # node or link
      path: "^prod_"        # optional name filter
      group_by: region
      name: "Region_${value}"
```

A name that is used but not declared is refused, and so is a loop of parents and children.
`membership`, `generate` and `disabled` work only on top-level entries.

## Demands

A demand is traffic from a set of source nodes to a set of target nodes. Demands live in named
sets; a workflow step places one set.

```yaml
network:
  nodes:
    dc1: {nodes: {leaf: {count: 2}}}
    dc2: {nodes: {leaf: {count: 2}}}
  links:
    - {source: dc1/leaf, target: dc2/leaf, capacity: 100}

demands:
  production:
    - source: "^dc1/"
      target: "^dc2/"
      volume: 100           # the total for this declaration, shared by its pairs
      mode: pairwise        # one demand per source-target node pair; default combine
      priority: 0           # lower is placed first
      preset: SHORTEST_PATHS_ECMP

workflow:
  - {type: TrafficMatrixPlacement, name: placement, demand_set: production}
```

- `volume` is the total of the declaration. Here the 4 node pairs share 100, 25 each. Each
  `expand` copy gets the whole volume.
- `mode: combine` (the default) makes one demand from all sources to all targets.
  `mode: pairwise` makes one per node pair.
- With `group_by` selectors, `group_mode` says how groups make demands: `flatten` (the default)
  merges them; `per_group` makes demands per source group; `group_pairwise` makes them per
  ordered pair of groups with different labels.
- Unless you give an `id`, a declaration is `<set>|<n>` (its position in the set), an `expand`
  copy adds `|<copy>`, and each demand it makes adds `|<k>`: `production|0|0`, `production|0|1`.

**Traffic matrices over one set of nodes.** When sources and targets share nodes, each shared
node must be a group of its own on both sides, so that a node is never asked to send to itself
inside one group. Capture each name:

```yaml
network:
  nodes: {A: {}, B: {}, C: {}}
  links:
    - {source: A, target: B, capacity: 20}
    - {source: B, target: C, capacity: 20}
demands:
  matrix:
    - {source: "^(A|B|C)$", target: "^(A|B|C)$", volume: 60, mode: pairwise}   # 6 pairs, 10 each
workflow:
  - {type: TrafficMatrixPlacement, name: matrix, demand_set: matrix}
```

Without the capture, the same demand is refused:

<!-- example: refusal non-diagonal source/target overlap: ['A', 'B', 'C'] -->

```yaml
network:
  nodes: {A: {}, B: {}, C: {}}
demands:
  matrix:
    - {source: "^[ABC]$", target: "^[ABC]$", volume: 60, mode: pairwise}
workflow:
  - {type: TrafficMatrixPlacement, name: matrix, demand_set: matrix}
```

**A selection that matches nothing is not an error.** Its volume is reported as discarded, with
reason `empty_selection`, in the step's `accounting`. Check it after changing node names.

### Presets: how demands are routed

A preset names a routing model. A demand without `preset` or `model` uses
`SHORTEST_PATHS_ECMP`.

| Preset | What it models |
|--------|----------------|
| `SHORTEST_PATHS_ECMP` | IP routing: each router splits traffic equally over its lowest-cost next hops (ECMP). What does not fit is not admitted. |
| `SHORTEST_PATHS_ECMP_LOSSY` | The same routing, but everything is sent and what does not fit is dropped on the way |
| `SHORTEST_PATHS_WCMP` | Lowest-cost routes, each next hop weighted by its link capacity (WCMP) |
| `SHORTEST_PATHS_MAXFLOW` | The most that fits on the lowest-cost routes |
| `TE_MAXFLOW_UNLIM` | Traffic engineering: the most that fits on any routes, the cheapest way |

For these two presets, each demand's sources share a **TE ingress pool**: one private point from
which its tunnels start. The counts below apply to that pool.

| Preset | What it models |
|--------|----------------|
| `TE_ECMP_16_LSP` | A controller provides 16 equal single-path tunnels from the pool |
| `TE_ECMP_UP_TO_256_LSP` | The same, with up to 256 tunnels |

Instead of a preset, a demand can declare `model: {routing: {type: ...}, admission: lossless |
lossy}`, with `type` one of `shortest_paths`, `distributed_te`, `centralized_te` and `pinned`
(explicit routes from `routes`). REFERENCE.md lists their keys. `preset` and `model` cannot be
used together.

## Failure policies

A failure policy says what can fail together. A step that names a policy draws from it
`iterations` times; each draw is a set of failed nodes and links.

<!-- example: fragment # -->

```yaml
failures:
  single_link:
    modes:                  # each draw picks one mode, by weight
      - weight: 1.0
        rules:
          - scope: link     # node, link or risk_group
            mode: choice    # all | choice (count of them) | random (each with probability)
            count: 1

  one_core_node:
    modes:
      - weight: 1.0
        rules:
          - {scope: node, mode: choice, count: 1, match: {conditions: [{attr: role, op: "==", value: core}]}}

  one_conduit:
    expand_groups: true     # also fail whatever shares a risk group with a failed element
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            mode: choice
            count: 1
            weight_by: distance_km   # chance proportional to this attribute
```

- A failed risk group fails all its members and its child groups.
- Rules choose among all declared elements, disabled ones included.
- Equal draws are computed once, as one **failure case**. Its `occurrences` counts the draws
  that gave it. The first case, `baseline`, has nothing failed and counts the draws that failed
  nothing; the `occurrences` of all cases add up to `iterations`.
- Random draws need not cover every possibility: with `n` links and one failure per draw, `n`
  draws usually miss some.
- A scenario or step `seed` makes the draws repeatable. Without one, repeatability is not
  guaranteed.

## Workflow

The workflow lists the steps to run, in order. Each step has a `type` and a `name`; an unnamed
step is called `<type>_<position>`, such as `MaxFlow_0`. Names must be unique and at most 100
characters.

| Step | Question it answers |
|------|---------------------|
| `NetworkStats` | Node, link, capacity and degree counts |
| `MaxFlow` | How much can flow between two node sets, optionally under failures |
| `TrafficMatrixPlacement` | How a demand set is placed, optionally under failures |
| `MaximumSupportedDemand` | The largest multiplier (alpha) of a demand set that still fits |
| `TunnelCountAnalysis` | Results per tunnel count for a set of tunnelled TE demands |
| `CostPower` | Hardware purchase cost and power, by level of the name hierarchy |
| `BuildGraph` | The graph as NetworkX node-link JSON |

<!-- example: unprepared -->

```yaml
workflow:
  - type: MaxFlow
    name: dc_capacity
    source: "^(dc[1-3])$"        # one group per dc: one row per pair in pairwise mode
    target: "^(dc[1-3])$"
    mode: pairwise
    failure_policy: single_link
    iterations: 1000             # failure draws (default 1)
    seed: 42
    outputs: {min_cut: true}

  - type: MaximumSupportedDemand
    name: msd
    demand_set: production

  - type: TrafficMatrixPlacement
    name: placement
    demand_set: production
    alpha_from_step: msd         # place at the multiplier the msd step found
    failure_policy: single_link
    iterations: 1000
    failure_states: [converged, stale]
    workers: auto                # worker threads; results do not depend on it
```

- `MaxFlow` without `preset` or `model` asks `TE_MAXFLOW_UNLIM`: the most that can flow on any
  routes.
- **Alpha** multiplies every volume of the set. A placement uses `alpha` (default 1) or
  `alpha_from_step` (an earlier MSD step), not both.
- `MaximumSupportedDemand` (MSD) multiplies and divides alpha by `growth_factor` (2), starting at
  `alpha_start` (1), until one probe fits and one does not, then narrows the gap to
  `alpha_tolerance` (0.01). It takes no failure policy: give the failures to a later placement
  with `alpha_from_step`.
- `failure_states` say how each failure case is reported: `converged` (routing has recomputed;
  the default), `stale` (old forwarding still in place; traffic into a failed link is lost) and
  `repair` (failed routes removed, survivors share the traffic, no new routes).
- `outputs` adds optional fields to each row, all off by default: `edge_flows`, `residual`,
  `edge_reservations`, `saturated_boundary_edges`, `min_cut`, `cost_distribution` and `details`.

## Units and results

NetGraph rounds bandwidth inputs to whole **units** of size `q`. The unit counts are exact and
repeatable. Automatic preparation chooses a power-of-two `q` and records it as
`units_report.q`. The precision target applies to local rounding and splitting; it can be
missed, so check `units_report.target_met` and `units_report.misses`. Multiply bandwidth fields
ending in `_units` by `q` for physical bandwidth. Declared inputs and `NetworkStats` capacities
stay physical.

The results file is one line of JSON (`jq .` indents it):

```json
{
  "metadata": {"netgraph_version": "...", "core_version": "...", "seed": 42},
  "units_report": {"q": 0.0078125, "target_met": true},
  "steps": [
    {"name": "placement", "step_type": "TrafficMatrixPlacement", "execution_order": 0,
     "question": {}, "result": {}}
  ]
}
```

`MaxFlow` and `TrafficMatrixPlacement` results hold `cases`, with `baseline` first. Each case
has a `case` record containing its `pattern` (failed nodes and links) and `occurrences`, plus
`states`. `MaxFlow` has `converged`; placement has exactly its requested `failure_states`,
defaulting to `[converged]`. Each state has `rows` and, for a successful placement state,
`totals`. The table and jq examples below use the default `converged` state.

| Step | Where to look | Reading |
|------|---------------|---------|
| `MaximumSupportedDemand` | `result.alpha_feasible.value`, `result.search_status` | The largest tested multiplier that fits. A value below 1 alone does not prove that the declared demand fails; check a placement at `alpha: 1`. `null` means no feasible probe was found; read `search_status` and `stop_reason`. |
| `TrafficMatrixPlacement` | `cases[].states.converged.totals`: `feasible`, `delivered_units`, `reference_shortfall_units` | `feasible: false` means some traffic was not delivered; the shortfall says how much |
| `MaxFlow` | `cases[].states.converged.rows[]` | For `kind: capacity`, read `result.delivered_units`. A `kind: self` row pairs a node with itself and has `capacity_units: 0`. |

Every result field is described at https://networmix.github.io/NetGraph/reference/results/.

```bash
# The largest multiplier that fits
jq '.steps[] | select(.step_type == "MaximumSupportedDemand") | .result.alpha_feasible.value' scenario.results.json

# Placement cases that did not deliver everything
jq '.steps[] | select(.step_type == "TrafficMatrixPlacement") | .result.cases[]
    | select(.states.converged.totals.feasible | not) | .case.id' scenario.results.json
```

## Running scenarios

Use `ngraph` from the environment where NetGraph is installed (in a NetGraph checkout,
`./venv/bin/ngraph`).

| Command | What it does |
|---------|--------------|
| `ngraph inspect file.yaml` | Loads and checks the scenario and prints its structure; runs nothing |
| `ngraph inspect --detail file.yaml` | Also prints node and link tables and step parameters |
| `ngraph run file.yaml` | Runs the workflow and writes `file.results.json` |
| `ngraph run file.yaml --stdout` | Also prints the JSON to stdout; logs go to stderr |
| `ngraph run file.yaml --keys msd placement` | Exports only the named steps (all steps still run) |
| `ngraph run file.yaml --profile` | Prints time per step and a Python profile to stderr |

Exit status: 0 on success, 1 when the scenario cannot be loaded or run, 2 for a wrong command
line. `inspect` prints `INSPECTION COMPLETE`; `run` prints `✅ Scenario execution completed`.

`inspect` does not run the workflow. It shows how many nodes each step selector matches
(`0 nodes` is a typo to fix), but an empty step selection is refused only by `run`. Use both.

## Common mistakes

**Own fields outside `attrs`.** A node or link accepts only its own keys:

<!-- example: refusal 'my_field' was unexpected -->

```yaml
network:
  nodes:
    A: {my_field: 1}        # write A: {attrs: {my_field: 1}}
```

**A wrapper around link fields.** `capacity` and `cost` go directly on the link, not under
another key such as `link_params`.

**A pattern that matches too much.** `leaf` also matches `leafy` and `leaf2/...`; anchor it with
`^...$` or end it with `/`.

**One group where you meant many.** Without a capture group, all matched nodes are one group: a
`pairwise` demand over overlapping sources and targets is refused, and a pairwise `MaxFlow`
from `^a` to `^b` gives one row instead of one per node pair.

**Exponents in YAML.** `1e6` is text to YAML, and a number field refuses it. Write `1000000` or
`1.0e+6`:

<!-- example: refusal '1e6' is not of type 'number' -->

```yaml
network:
  nodes: {A: {}, B: {}}
  links: [{source: A, target: B, capacity: 1e6}]
```

**A fractional cost.** Costs are integers from 1: `cost: 1.5` is refused.

**A demand set no step uses.** Demands are resolved only for the steps that name their set. A
selection error in a set no step uses is reported by neither `inspect` nor `run`.

## Errors and their fixes

Every load error names its place in the file, such as `network.links[0] (A->Z)` or
`workflow[0] (name 'MaxFlow_0').source`, then the problem:

| Message contains | Cause | Fix |
|-------------------|-------|-----|
| `Additional properties are not allowed ('x' was unexpected)` | A misspelled key, or your own field outside `attrs` | Fix the key, or move it under `attrs` |
| `target 'Z' matches no node` (or `source`) | A link endpoint that matches no node | Fix the name or the pattern |
| `one_to_one pattern requires sizes with a multiple factor` | Group sizes such as 3 and 2 | Use sizes where one divides the other, or `mesh` |
| `Variable '$x' not found in expand.vars` | A `$x` without a value list | Add `x` under `expand.vars` |
| `zip expansion requires equal-length lists` | `zip` lists of different lengths | Equal lengths, or `mode: cartesian` |
| `unknown risk groups 'X'` | A risk group used but not declared | Declare it under `risk_groups` |
| `unknown failure policy`, `unknown demand set` | A step names something not declared | Fix the name |
| `empty selection` (from `run`) | A step selector matches no enabled node | Fix the pattern; check `inspect`'s selection preview |
| `non-diagonal source/target overlap` | Sources and targets share nodes inside one group | One group per node: a capture group or `group_by: name` |
| `must name an earlier MSD step` | `alpha_from_step` names another step type, or a later step | Name an MSD step declared earlier |
| `no tested feasible alpha` (from `run`) | The MSD step found no multiplier that fits, so the placement has none | Check connectivity and capacity; see the MSD step's `search_status` |
