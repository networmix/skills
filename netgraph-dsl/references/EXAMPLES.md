# NetGraph Scenario Examples

Complete scenarios, from small to larger. Each one loads as written; the **Result** line says
what it builds.

> For the rules and common mistakes, see [SKILL.md](../SKILL.md).
> For every key, see [REFERENCE.md](REFERENCE.md).

## Example 1: Leaf-spine fabric with a traffic matrix

Four leaves, two spines, traffic between every pair of leaves, one link failure per draw.

```yaml
network:
  nodes:
    leaf:
      count: 4
      template: "leaf{n}"
      attrs:
        role: leaf
    spine:
      count: 2
      template: "spine{n}"
      attrs:
        role: spine
  links:
    - source: /leaf
      target: /spine
      pattern: mesh
      capacity: 100
      cost: 1

demands:
  default:
    - source: "^(leaf/leaf[0-9]+)$"   # one group per leaf, so a leaf never sends to itself
      target: "^(leaf/leaf[0-9]+)$"
      volume: 50
      mode: pairwise

failures:
  single_link:
    modes:
      - weight: 1.0
        rules:
          - scope: link
            mode: choice
            count: 1

workflow:
  - type: TrafficMatrixPlacement
    name: placement
    demand_set: default
    failure_policy: single_link
    iterations: 100
```

**Result**: 6 nodes (`leaf/leaf1` to `leaf/leaf4`, `spine/spine1`, `spine/spine2`) and 8 links.
The 12 ordered pairs of distinct leaves share the declared volume of 50.

## Example 2: Two pods from one blueprint

A blueprint is a reusable piece of topology. Here it is used twice, and the two pods are joined
at their spines.

```yaml
blueprints:
  clos_pod:
    nodes:
      leaf:
        count: 4
        template: "leaf{n}"
        attrs:
          role: leaf
      spine:
        count: 2
        template: "spine{n}"
        attrs:
          role: spine
    links:
      - source: /leaf
        target: /spine
        pattern: mesh
        capacity: 100

network:
  nodes:
    pod[1-2]:
      blueprint: clos_pod

  links:
    - source:
        path: "pod1/spine"
        match:
          conditions:
            - attr: role
              op: "=="
              value: spine
      target:
        path: "pod2/spine"
      pattern: mesh
      capacity: 400
```

**Result**: 12 nodes (6 per pod, for example `pod1/leaf/leaf1`) and 20 links: 8 inside each pod
and 4 between the pods' spines.

## Example 3: Backbone with shared-risk link groups

A risk group is a set of nodes and links that fail together, such as the fibers in one conduit.
The capacity step asks how much New York can send to Los Angeles when one risk group fails.

```yaml
network:
  nodes:
    NewYork: {attrs: {site_type: core}}
    Chicago: {attrs: {site_type: core}}
    LosAngeles: {attrs: {site_type: core}}

  links:
    # Two parallel New York-Chicago links; only the first is in the corridor group
    - source: NewYork
      target: Chicago
      capacity: 100
      cost: 10
      risk_groups: [RG_NY_CHI]
    - source: NewYork
      target: Chicago
      capacity: 100
      cost: 10
    - source: Chicago
      target: LosAngeles
      capacity: 100
      cost: 15
      risk_groups: [RG_CHI_LA]

risk_groups:
  - name: RG_NY_CHI
    attrs:
      corridor: NYC-Chicago
      distance_km: 1200
  - name: RG_CHI_LA
    attrs:
      corridor: Chicago-LA
      distance_km: 2800

failures:
  srlg_failure:
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            mode: choice
            count: 1

workflow:
  - type: MaxFlow
    name: ny_to_la
    source: "^NewYork$"
    target: "^LosAngeles$"
    failure_policy: srlg_failure
    iterations: 10
    seed: 1
```

**Result**: 3 nodes, 3 links (`NewYork|Chicago|0`, `NewYork|Chicago|1`, `Chicago|LosAngeles|0`)
and 2 risk groups. Without failures 100 can flow; losing `RG_NY_CHI` still leaves 100, losing
`RG_CHI_LA` leaves 0.

## Example 4: Variable expansion at scale

An `expand` block repeats one link definition for every combination of its variables.

```yaml
network:
  nodes:
    plane[1-4]/rack[1-8]:
      count: 48
      template: "server{n}"
      attrs:
        role: compute

    fabric/spine[1-4]:
      count: 1
      template: "spine"
      attrs:
        role: spine

  links:
    - source: "plane${p}/rack${r}"
      target: "fabric/spine${s}"
      expand:
        vars:
          p: [1, 2, 3, 4]
          r: [1, 2, 3, 4, 5, 6, 7, 8]
          s: [1, 2, 3, 4]
        mode: cartesian
      pattern: mesh
      capacity: 100
```

**Result**: 1,540 nodes (4 × 8 × 48 servers and 4 spines, such as `fabric/spine1/spine`) and
6,144 links: 128 combinations, each joining 48 servers to one spine.

## Example 5: Four-node full mesh

The largest scale of a traffic matrix that fits, and the capacity between every pair of nodes
under single link failures.

```yaml
seed: 42

network:
  nodes:
    N1: {}
    N2: {}
    N3: {}
    N4: {}

  links:
    - source: N1
      target: N2
      capacity: 2.0
      cost: 1
    - source: N1
      target: N3
      capacity: 1.0
      cost: 1
    - source: N1
      target: N4
      capacity: 2.0
      cost: 1
    - source: N2
      target: N3
      capacity: 2.0
      cost: 1
    - source: N2
      target: N4
      capacity: 1.0
      cost: 1
    - source: N3
      target: N4
      capacity: 2.0
      cost: 1

failures:
  single_link_failure:
    modes:
      - weight: 1.0
        rules:
          - scope: link
            mode: choice
            count: 1

demands:
  baseline:
    - source: "^N([1-4])$"
      target: "^N([1-4])$"
      volume: 12.0
      mode: pairwise

workflow:
  - type: MaximumSupportedDemand
    name: msd
    demand_set: baseline
    alpha_start: 1.0
    alpha_tolerance: 0.05

  - type: MaxFlow
    name: capacity_matrix
    source: "^(N[1-4])$"
    target: "^(N[1-4])$"
    mode: pairwise
    failure_policy: single_link_failure
    iterations: 1000
    seed: 42
```

**Result**: 4 nodes and 6 links. The 12 ordered pairs of distinct nodes share the volume of 12,
1 each; the capacity step reports one row per ordered pair in each failure case.

## Example 6: Selecting nodes by attribute

A selector's `path` is matched from the start of the name, so `/servers` also matches
`servers_b/...`. The `match` conditions keep only the rack-1 servers.

```yaml
network:
  nodes:
    servers:
      count: 4
      template: "srv{n}"
      attrs:
        role: compute
        rack: "rack-1"
    servers_b:
      count: 2
      template: "srvb{n}"
      attrs:
        role: compute
        rack: "rack-9"
    switches:
      count: 2
      template: "sw{n}"
      attrs:
        tier: spine

  links:
    - source:
        path: "/servers"
        match:
          logic: and
          conditions:
            - attr: role
              op: "=="
              value: compute
            - attr: rack
              op: "!="
              value: "rack-9"
      target:
        path: "/switches"
        match:
          conditions:
            - attr: tier
              op: "=="
              value: spine
      pattern: mesh
      capacity: 10
      cost: 1
```

**Result**: 8 nodes and 8 links: each of the four `servers/srv*` nodes to both switches. The
`servers_b` nodes get no links.

## Example 7: Overriding blueprint parameters

`params` changes one instance of a blueprint, here a nested attribute.

```yaml
blueprints:
  bp1:
    nodes:
      leaf:
        count: 1
        attrs:
          some_field:
            nested_key: 111

network:
  nodes:
    Main:
      blueprint: bp1
      params:
        leaf.attrs.some_field.nested_key: 999
```

**Result**: one node, `Main/leaf/leaf-1` (without a `template`, names are `<group>-{n}`), with
`attrs.some_field.nested_key` 999.

## Example 8: Node and link rules

Rules change nodes and links after they are created.

```yaml
blueprints:
  test_bp:
    nodes:
      switches:
        count: 3
        template: "switch{n}"

network:
  nodes:
    group1:
      count: 2
      template: "node{n}"
    group2:
      count: 2
      template: "node{n}"
    my_clos1:
      blueprint: test_bp

  links:
    - source: /group1
      target: /group2
      pattern: mesh
      capacity: 100
      cost: 10

  node_rules:
    - path: "^my_clos1/switches/switch(1|3)$"
      disabled: true
      attrs:
        maintenance_mode: active
        hw_type: newer_model

  link_rules:
    - source: "^group1/node1$"
      target: "^group2/node1$"
      capacity: 200
      cost: 5
```

**Result**: 7 nodes and 4 links. `my_clos1/switches/switch1` and `switch3` are disabled; the link
`group1/node1|group2/node1|0` has capacity 200 and cost 5.

## Example 9: Supported demand, then placement under failures

The MSD step (maximum supported demand) finds the largest multiplier of the demand set that
still fits; the placement step then places the set at that multiplier under link failures.

```yaml
seed: 42

blueprints:
  Clos_L16_S4:
    nodes:
      spine:
        count: 4
        template: spine{n}
        attrs:
          role: spine
      leaf:
        count: 16
        template: leaf{n}
        attrs:
          role: leaf
    links:
      - source: /leaf
        target: /spine
        pattern: mesh
        capacity: 3200
        cost: 1

network:
  nodes:
    metro1/pop[1-2]:
      blueprint: Clos_L16_S4
      attrs:
        metro_name: new-york
        node_type: pop
  links:
    - source: metro1/pop1/spine
      target: metro1/pop2/spine
      pattern: mesh
      capacity: 3200
      cost: 10

demands:
  baseline:
    - source: "^metro1/pop1/leaf/"
      target: "^metro1/pop2/leaf/"
      volume: 15000.0
      mode: pairwise

failures:
  single_link:
    modes:
      - weight: 1.0
        rules:
          - scope: link
            mode: choice
            count: 1

workflow:
  - type: NetworkStats
    name: network_statistics

  - type: MaximumSupportedDemand
    name: msd_baseline
    demand_set: baseline
    alpha_start: 1.0
    growth_factor: 2.0
    alpha_tolerance: 0.05

  - type: TrafficMatrixPlacement
    name: tm_placement
    demand_set: baseline
    failure_policy: single_link
    iterations: 200
    outputs: {cost_distribution: true}
    alpha_from_step: msd_baseline
```

**Result**: 40 nodes and 144 links: 64 inside each pop and 16 between the pops' spines. The
256 leaf pairs share 15,000. The placement runs at the multiplier the MSD step found.

## Example 10: Grouping nodes by attribute

`group_by` makes one group per value of an attribute. With `group_mode: group_pairwise`, traffic
goes only between groups with different values: here from dc1 to dc2 and from dc2 to dc1.

```yaml
network:
  nodes:
    dc1_srv1: {attrs: {dc: dc1, role: server}}
    dc1_srv2: {attrs: {dc: dc1, role: server}}
    dc2_srv1: {attrs: {dc: dc2, role: server}}
    dc2_srv2: {attrs: {dc: dc2, role: server}}
  links:
    - source: "^dc1_"
      target: "^dc2_"
      pattern: mesh
      capacity: 100

demands:
  inter_dc:
    - source:
        group_by: dc
      target:
        group_by: dc
      volume: 100
      mode: pairwise
      group_mode: group_pairwise

workflow:
  - type: TrafficMatrixPlacement
    name: inter_dc
    demand_set: inter_dc
```

**Result**: 8 demands, one per server pair between different data centers. The volume of 100 is
split between the two group pairs, then over their four server pairs.

## Example 11: A failure policy with several modes

Each draw picks one mode by weight, then applies that mode's rules.

```yaml
network:
  nodes:
    core1: {attrs: {role: core, capacity_gbps: 1000}}
    core2: {attrs: {role: core, capacity_gbps: 1000}}
    edge1: {attrs: {role: edge, capacity_gbps: 400, region: west}}
    edge2: {attrs: {role: edge, capacity_gbps: 400, region: east}}
    edge3: {attrs: {role: edge, capacity_gbps: 200, region: west}}
  links:
    - source: core1
      target: core2
      capacity: 1000
      risk_groups: [RG_core]
    - source: core1
      target: edge1
      capacity: 400
      risk_groups: [RG_west]
    - source: core1
      target: edge3
      capacity: 200
      risk_groups: [RG_west]
    - source: core2
      target: edge2
      capacity: 400
      risk_groups: [RG_east]

risk_groups:
  - name: RG_core
    attrs: {tier: core, distance_km: 50}
  - name: RG_west
    attrs: {tier: edge, distance_km: 500}
  - name: RG_east
    attrs: {tier: edge, distance_km: 800}

failures:
  mixed_failures:
    expand_groups: true          # also fail whatever shares a risk group with a failed element
    modes:
      # 40% of draws: one edge node, chosen with chance proportional to capacity_gbps
      - weight: 0.4
        attrs: {scenario: edge_failure}
        rules:
          - scope: node
            mode: choice
            count: 1
            match:
              logic: and
              conditions:
                - attr: role
                  op: "=="
                  value: edge
            weight_by: capacity_gbps

      # 35%: one risk group, chosen with chance proportional to distance_km
      - weight: 0.35
        attrs: {scenario: srlg_failure}
        rules:
          - scope: risk_group
            mode: choice
            count: 1
            weight_by: distance_km

      # 15%: every west-region node
      - weight: 0.15
        attrs: {scenario: regional_outage}
        rules:
          - scope: node
            mode: all
            match:
              conditions:
                - attr: region
                  op: "=="
                  value: west

      # 10%: each link fails on its own with chance 5%
      - weight: 0.1
        attrs: {scenario: random_link}
        rules:
          - scope: link
            mode: random
            probability: 0.05

workflow:
  - type: MaxFlow
    name: failure_analysis
    source: "^(edge[1-3])$"
    target: "^(edge[1-3])$"
    mode: pairwise
    failure_policy: mixed_failures
    iterations: 1000
    seed: 42
```

**Result**: 5 nodes, 4 links, 3 risk groups and a policy with 4 weighted modes.

## Example 12: Hardware cost and power

The `components` library describes hardware; nodes and link ends name it under `attrs.hardware`.
The `CostPower` step adds up hardware purchase cost and power use.

```yaml
components:
  SpineRouter:
    component_type: chassis
    description: "64-port spine switch"
    capex: 55000.0
    power_watts: 2000.0
    power_watts_max: 3000.0
    capacity: 102400.0
    ports: 64

  LeafRouter:
    component_type: chassis
    description: "48-port leaf switch"
    capex: 25000.0
    power_watts: 800.0
    power_watts_max: 1200.0
    capacity: 38400.0
    ports: 48

  Optic400G:
    component_type: optic
    description: "400G DR4 pluggable"
    capex: 3000.0
    power_watts: 16.0
    capacity: 400.0

network:
  name: "datacenter-fabric"
  version: "2.0"

  nodes:
    spine:
      count: 2
      template: "spine{n}"
      attrs:
        hardware:
          component: SpineRouter
          count: 1
    leaf:
      count: 4
      template: "leaf{n}"
      attrs:
        hardware:
          component: LeafRouter
          count: 1

  links:
    - source: /leaf
      target: /spine
      pattern: mesh
      count: 2                    # 2 parallel links per pair
      capacity: 800
      cost: 1
      attrs:
        hardware:
          source:
            component: Optic400G
            count: 2
          target:
            component: Optic400G
            count: 2
            exclusive: true          # not shared with other links

workflow:
  - type: NetworkStats
    name: stats

  - type: CostPower
    name: cost_analysis
    include_disabled: false
    aggregation_level: 1             # group by the first part of each name (leaf, spine)
```

**Result**: 6 nodes and 16 links (4 leaves × 2 spines × 2 parallel links), with capex and power
per level.

## Example 13: YAML anchors

YAML anchors (`&name`) and aliases (`*name`) reuse values; `<<:` merges a mapping.

```yaml
vars:
  default_link: &link_cfg
    capacity: 100
    cost: 1
  spine_attrs: &spine_attrs
    role: spine
    tier: 2
  leaf_attrs: &leaf_attrs
    role: leaf
    tier: 1

network:
  nodes:
    spine:
      count: 2
      template: "spine{n}"
      attrs:
        <<: *spine_attrs
        region: east

    leaf:
      count: 4
      template: "leaf{n}"
      attrs:
        <<: *leaf_attrs
        region: east

  links:
    - source: /leaf
      target: /spine
      pattern: mesh
      <<: *link_cfg
      attrs:
        link_type: fabric
```

**Result**: 6 nodes and 8 links of capacity 100 and cost 1. The anchors are resolved when the
YAML is read.

## Example 14: one_to_one links and zip expansion

`one_to_one` pairs the nodes of two sets in order, wrapping around the smaller set. `zip` pairs
the values of the `expand` variables by position.

```yaml
network:
  nodes:
    # 4 servers and 2 switches: 4 is a multiple of 2, so one_to_one works
    server[1-4]:
      count: 1
      template: "srv"
    switch[1-2]:
      count: 1
      template: "sw"

  links:
    # server1-switch1, server2-switch2, server3-switch1, server4-switch2
    - source: /server
      target: /switch
      pattern: one_to_one
      capacity: 100

    # zip: server1-switch1 and server2-switch2
    - source: "server${idx}"
      target: "switch${sw}"
      expand:
        vars:
          idx: [1, 2]
          sw: [1, 2]
        mode: zip
      pattern: one_to_one
      capacity: 50
      cost: 2
```

**Result**: 6 nodes (`server1/srv` and so on) and 6 links: four of capacity 100, and a second,
parallel link of capacity 50 on `server1/srv|switch1/sw` and `server2/srv|switch2/sw`.

## Example 15: Demands from variables, groups and priorities

```yaml
network:
  nodes:
    dc1_leaf1: {attrs: {dc: dc1, role: leaf}}
    dc1_leaf2: {attrs: {dc: dc1, role: leaf}}
    dc2_leaf1: {attrs: {dc: dc2, role: leaf}}
    dc2_leaf2: {attrs: {dc: dc2, role: leaf}}
    dc3_leaf1: {attrs: {dc: dc3, role: leaf}}
  links:
    - {source: dc1_leaf1, target: dc2_leaf1, capacity: 100}
    - {source: dc1_leaf2, target: dc2_leaf2, capacity: 100}
    - {source: dc2_leaf1, target: dc3_leaf1, capacity: 100}

demands:
  # One demand per zip pair: dc1 to dc2, dc2 to dc3
  inter_dc:
    - source: "^${src}_"
      target: "^${dst}_"
      volume: 50
      expand:
        vars:
          src: [dc1, dc2]
          dst: [dc2, dc3]
        mode: zip

  # One demand per source group (dc1, dc2), each to dc3; placed before priority 1
  to_dc3:
    - source:
        path: "^dc[12]_"
        group_by: dc
      target: "^dc3_"
      volume: 100
      group_mode: per_group
      priority: 0
      preset: SHORTEST_PATHS_WCMP
    - source: "^dc1_"
      target: "^dc2_"
      volume: 10
      priority: 1

workflow:
  - type: TrafficMatrixPlacement
    name: inter_dc
    demand_set: inter_dc
  - type: TrafficMatrixPlacement
    name: to_dc3
    demand_set: to_dc3
```

**Result**: `inter_dc` has two demands of 50 each (every `expand` combination has the whole
volume). `to_dc3` has a demand from dc1 and one from dc2 to dc3, sharing 100, then a dc1 to dc2
demand of 10.

## Example 16: Nested risk groups

A child risk group fails with its parent.

```yaml
network:
  nodes:
    rack1_srv1: {risk_groups: [Rack1_Card1]}
    rack1_srv2: {risk_groups: [Rack1_Card1]}
    rack1_srv3: {risk_groups: [Rack1_Card2]}
    rack2_srv1: {risk_groups: [Rack2]}
  links:
    - {source: rack1_srv1, target: rack2_srv1, capacity: 100}
    - {source: rack1_srv2, target: rack2_srv1, capacity: 100}
    - {source: rack1_srv3, target: rack2_srv1, capacity: 100}

risk_groups:
  # Each card and rack declared at top level, with its attributes
  - name: Rack1_Card1
    attrs: {slot: 1, parent: Rack1}
  - name: Rack1_Card2
    attrs: {slot: 2, parent: Rack1}
  - name: Rack2
    disabled: false
    attrs: {location: "DC1-Row2"}
  # The parent names the cards as its children
  - name: Rack1
    attrs: {location: "DC1-Row1"}
    children:
      - name: Rack1_Card1
      - name: Rack1_Card2

failures:
  hierarchical:
    expand_groups: true
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            mode: choice
            count: 1
            match:
              conditions:
                - attr: location
                  op: contains
                  value: "DC1"
```

**Result**: 4 risk groups. The failure rule chooses between `Rack1` and `Rack2` (the groups with
a `location`). Failing `Rack1` fails its cards too, and with them the three `rack1_*` servers.

## Example 17: Risk group membership rules

A membership rule puts every node or link whose attributes match into the group.

```yaml
network:
  nodes:
    core1: {attrs: {role: core, tier: 3, datacenter: dc1}}
    core2: {attrs: {role: core, tier: 3, datacenter: dc2}}
    edge1: {attrs: {role: edge, tier: 1, datacenter: dc1}}
    edge2: {attrs: {role: edge, tier: 1, datacenter: dc2}}
  links:
    - source: core1
      target: core2
      capacity: 1000
      attrs:
        route:
          type: backbone
    - source: core1
      target: edge1
      capacity: 400

risk_groups:
  # Every node with role core and tier 3
  - name: CoreTier3
    membership:
      scope: node
      match:
        logic: and              # every condition must hold (the default for membership)
        conditions:
          - attr: role
            op: "=="
            value: core
          - attr: tier
            op: "=="
            value: 3

  # Links by a nested attribute, written with a dot
  - name: BackboneLinks
    membership:
      scope: link
      match:
        conditions:
          - attr: route.type
            op: "=="
            value: backbone

  # A plain name defines a group with no rule
  - "ManualGroup1"
```

**Result**: `CoreTier3` holds `core1` and `core2`; `BackboneLinks` holds the link
`core1|core2|0`; `ManualGroup1` is empty.

## Example 18: Generated risk groups

A `generate` block makes one risk group per distinct value of an attribute.

```yaml
network:
  nodes:
    srv1: {attrs: {datacenter: dc1, rack: r1}}
    srv2: {attrs: {datacenter: dc1, rack: r2}}
    srv3: {attrs: {datacenter: dc2, rack: r1}}
  links:
    - source: srv1
      target: srv2
      capacity: 100
      attrs:
        connection_type: intra_dc
    - source: srv2
      target: srv3
      capacity: 100
      attrs:
        connection_type: inter_dc

risk_groups:
  # One group per datacenter value
  - generate:
      scope: node
      group_by: datacenter
      name: "DC_${value}"
      attrs:
        generated: true
        type: location

  # One group per rack value
  - generate:
      scope: node
      group_by: rack
      name: "Rack_${value}"

  # One group per link connection_type
  - generate:
      scope: link
      group_by: connection_type
      name: "Links_${value}"
```

**Result**: 6 risk groups:

- `DC_dc1` (srv1, srv2)
- `DC_dc2` (srv3)
- `Rack_r1` (srv1, srv3)
- `Rack_r2` (srv2)
- `Links_intra_dc` (link `srv1|srv2|0`)
- `Links_inter_dc` (link `srv2|srv3|0`)

## Example 19: Condition operators

Demands whose sources and targets are chosen by attribute conditions.

```yaml
network:
  nodes:
    srv1: {attrs: {tier: 1, tags: [prod, web], region: null}}
    srv2: {attrs: {tier: 2, tags: [prod, db], region: east}}
    srv3: {attrs: {tier: 3, tags: [dev], region: west}}
    srv4: {attrs: {tier: 2}}
  links:
    - {source: srv1, target: srv2, capacity: 100}
    - {source: srv2, target: srv3, capacity: 100}
    - {source: srv3, target: srv4, capacity: 100}

demands:
  filtered:
    # Comparison: tier 3 and above to tier below 2 (srv3 to srv1)
    - source:
        match:
          conditions:
            - attr: tier
              op: ">="
              value: 3
      target:
        match:
          conditions:
            - attr: tier
              op: "<"
              value: 2
      volume: 50

    # Lists: region east or west (srv2, srv3) to nodes tagged web (srv1)
    - source:
        match:
          conditions:
            - attr: region
              op: in
              value: [east, west]
      target:
        match:
          conditions:
            - attr: tags
              op: contains
              value: web
      volume: 25

    # Presence: a region that is set (srv2, srv3) to none or null (srv1, srv4)
    - source:
        match:
          conditions:
            - attr: region
              op: exists
      target:
        match:
          conditions:
            - attr: region
              op: not_exists
      volume: 10
      mode: pairwise

workflow:
  - type: TrafficMatrixPlacement
    name: filtered
    demand_set: filtered
```

**Result**: the operators `>=`, `<`, `in`, `contains`, `exists` and `not_exists`. The last
demand splits its 10 over the four pairs from srv2 and srv3 to srv1 and srv4.

## Example 20: link_match and rule expansion

`link_match` filters a link rule by the link's own attributes; `expand` repeats a rule.

```yaml
network:
  nodes:
    dc1_srv: {}
    dc2_srv: {}
    dc3_srv: {}
  links:
    - {source: dc1_srv, target: dc2_srv, capacity: 100, cost: 1, attrs: {type: fiber}}
    - {source: dc1_srv, target: dc2_srv, capacity: 500, cost: 1, attrs: {type: fiber}}
    - {source: dc2_srv, target: dc3_srv, capacity: 500, cost: 1, attrs: {type: copper}}

  # Only high-capacity fiber links
  link_rules:
    - source: ".*"
      target: ".*"
      link_match:
        logic: and
        conditions:
          - {attr: capacity, op: ">=", value: 400}
          - {attr: type, op: "==", value: fiber}
      cost: 99
      attrs:
        priority: high

  # One node rule per value of dc
  node_rules:
    - path: "${dc}_srv"
      expand:
        vars:
          dc: [dc1, dc2]
        mode: cartesian
      attrs:
        tagged: true
```

**Result**: only `dc1_srv|dc2_srv|1` (capacity 500, fiber) gets cost 99. `dc1_srv` and `dc2_srv`
get `tagged: true`.

## Example 21: Nested nodes without a blueprint

```yaml
network:
  nodes:
    datacenter:
      attrs:
        region: west
        tier: 1
      nodes:
        rack1:
          attrs:
            rack_id: 1
          nodes:
            tor:
              count: 1
              template: "sw{n}"
              attrs:
                role: switch
            servers:
              count: 4
              template: "srv{n}"
              attrs:
                role: compute
        rack2:
          attrs:
            rack_id: 2
          nodes:
            tor:
              count: 1
              template: "sw{n}"
              attrs:
                role: switch
            servers:
              count: 4
              template: "srv{n}"
              attrs:
                role: compute

  links:
    # Each rack's servers to its top-of-rack switch
    - source:
        path: "datacenter/rack1/servers"
      target:
        path: "datacenter/rack1/tor"
      pattern: mesh
      capacity: 25
    - source:
        path: "datacenter/rack2/servers"
      target:
        path: "datacenter/rack2/tor"
      pattern: mesh
      capacity: 25
    # The two switches
    - source: datacenter/rack1/tor/sw1
      target: datacenter/rack2/tor/sw1
      capacity: 100
```

**Result**: 10 nodes (2 switches and 8 servers, such as `datacenter/rack1/servers/srv1`) and 9
links. Every node gets the parents' attributes: `region: west`, `tier: 1` and its rack's
`rack_id`.

## Example 22: A path filter in generate blocks

`path` narrows the nodes or links before groups are made. A link's name for `path` is
`source|target`.

```yaml
network:
  nodes:
    prod_web1: {attrs: {env: production, service: web}}
    prod_web2: {attrs: {env: production, service: web}}
    prod_db1: {attrs: {env: production, service: database}}
    dev_web1: {attrs: {env: development, service: web}}
    dev_db1: {attrs: {env: development, service: database}}
  links:
    - {source: prod_web1, target: prod_db1, capacity: 100, attrs: {link_type: internal}}
    - {source: prod_web2, target: prod_db1, capacity: 100, attrs: {link_type: internal}}
    - {source: dev_web1, target: dev_db1, capacity: 50, attrs: {link_type: internal}}

risk_groups:
  # Environment groups, production nodes only
  - generate:
      scope: node
      path: "^prod_"
      group_by: env
      name: "Env_${value}"
      attrs:
        generated: true
        critical: true

  # Service groups, all nodes
  - generate:
      scope: node
      group_by: service
      name: "Service_${value}"

  # Link groups, production links only
  - generate:
      scope: link
      path: ".*prod.*"
      group_by: link_type
      name: "ProdLinks_${value}"

demands:
  baseline:
    - source: "^prod_web"
      target: "^prod_db"
      volume: 50
      mode: pairwise
      preset: SHORTEST_PATHS_ECMP

failures:
  production_failure:
    expand_groups: true
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            path: "^Env_"
            mode: choice
            count: 1
```

**Result**: 4 risk groups:

- `Env_production` (the three `prod_*` nodes; no `Env_development`, since the path filter
  leaves out the dev nodes)
- `Service_web` (prod_web1, prod_web2, dev_web1)
- `Service_database` (prod_db1, dev_db1)
- `ProdLinks_internal` (the two production links)
