# NetGraph DSL Examples

Complete working examples for common use cases.

> For quick patterns and pitfalls, see the main [SKILL.md](../SKILL.md).
> For detailed field reference, see [REFERENCE.md](REFERENCE.md).

## Example 1: Simple Data Center

A basic leaf-spine topology with traffic analysis.

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
    - source: "^leaf/.*"
      target: "^leaf/.*"
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

**Result**: 6 nodes (4 leaf + 2 spine), 8 links (4x2 mesh)

## Example 2: Multi-Pod with Blueprint

Two pods sharing a blueprint, connected via spine layer.

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

**Result**: 12 nodes (2 pods x 6 nodes), 20 links (16 internal + 4 inter-pod)

## Example 3: Backbone with Risk Groups

Wide-area network with shared-risk link groups.

```yaml
network:
  nodes:
    NewYork: {attrs: {site_type: core}}
    Chicago: {attrs: {site_type: core}}
    LosAngeles: {attrs: {site_type: core}}

  links:
    # Parallel diverse paths
    - source: NewYork
      target: Chicago
      capacity: 100
      cost: 10
      risk_groups: [RG_NY_CHI]
    - source: NewYork
      target: Chicago
      capacity: 100
      cost: 10
    # Single path
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
```

**Result**: 3 nodes, 3 links, 2 risk groups

## Example 4: Variable Expansion at Scale

Large fabric using variable expansion.

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

**Result**: 1540 nodes (4x8x48 compute + 4 spine), 6144 links

## Example 5: Full Mesh Topology

Simple 4-node full mesh for testing.

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
      cost: 1.0
    - source: N1
      target: N3
      capacity: 1.0
      cost: 1.0
    - source: N1
      target: N4
      capacity: 2.0
      cost: 1.0
    - source: N2
      target: N3
      capacity: 2.0
      cost: 1.0
    - source: N2
      target: N4
      capacity: 1.0
      cost: 1.0
    - source: N3
      target: N4
      capacity: 2.0
      cost: 1.0

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
    acceptance_rule: hard
    alpha_start: 1.0
    resolution: 0.05

  - type: MaxFlow
    name: capacity_matrix
    source: "^(N[1-4])$"
    target: "^(N[1-4])$"
    mode: pairwise
    failure_policy: single_link_failure
    iterations: 1000
    seed: 42
```

## Example 6: Attribute-Based Selectors

Using match conditions to filter nodes.

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

**Result**: 8 nodes, 8 links (only rack-1 servers connect to switches)

## Example 7: Blueprint with Parameter Overrides

Customizing blueprint instances.

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

**Result**: Node `Main/leaf/leaf1` has `attrs.some_field.nested_key = 999`

## Example 8: Node and Link Rules

Modifying topology after creation.

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

**Result**: Switches 1 and 3 disabled, specific link upgraded to 200 capacity

## Example 9: Complete Traffic Analysis

Full workflow with MSD and placement analysis.

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

demands:
  baseline:
    - source: "^metro1/pop1/.*"
      target: "^metro1/pop2/.*"
      volume: 15000.0
      mode: pairwise
      flow_policy: TE_WCMP_UNLIM

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
    acceptance_rule: hard
    alpha_start: 1.0
    growth_factor: 2.0
    resolution: 0.05

  - type: TrafficMatrixPlacement
    name: tm_placement
    seed: 42
    demand_set: baseline
    failure_policy: single_link
    iterations: 1000
    parallelism: 7
    include_flow_details: true
    alpha_from_step: msd_baseline
    alpha_from_field: data.alpha_star
```

## Example 10: Group-By Selectors

Grouping nodes by attribute for demand generation.

```yaml
network:
  nodes:
    dc1_srv1: {attrs: {dc: dc1, role: server}}
    dc1_srv2: {attrs: {dc: dc1, role: server}}
    dc2_srv1: {attrs: {dc: dc2, role: server}}
    dc2_srv2: {attrs: {dc: dc2, role: server}}
  links:
    - source: dc1_srv1
      target: dc2_srv1
      capacity: 100
    - source: dc1_srv2
      target: dc2_srv2
      capacity: 100

demands:
  inter_dc:
    - source:
        group_by: dc
      target:
        group_by: dc
      volume: 100
      mode: pairwise
```

**Result**: Traffic flows grouped by datacenter attribute

## Example 11: Advanced Failure Policies

Multiple weighted failure modes with conditions and weighted sampling.

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
    expand_groups: true          # Expand to shared-risk entities
    expand_children: false
    modes:
      # 40% chance: fail 1 edge node weighted by capacity
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

      # 35% chance: fail 1 risk group weighted by distance
      - weight: 0.35
        attrs: {scenario: srlg_failure}
        rules:
          - scope: risk_group
            mode: choice
            count: 1
            weight_by: distance_km

      # 15% chance: fail all west-region nodes
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

      # 10% chance: random link failures (5% each)
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

**Result**: 5 nodes, 4 links, 3 risk groups, failure policy with 4 weighted modes

## Example 12: Hardware Components and Cost Analysis

Using the components library for cost/power modeling.

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
            exclusive: true          # Dedicated optics (rounds up count)

workflow:
  - type: NetworkStats
    name: stats

  - type: CostPower
    name: cost_analysis
    include_disabled: false
    aggregation_level: 1               # Aggregate by top-level group
```

**Result**: 6 nodes, 16 links (4x2x2), component-based cost/power analysis

## Example 13: YAML Anchors for Reuse

Using `vars` section for DRY configuration.

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
        <<: *spine_attrs             # Merge anchor
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
      <<: *link_cfg                # Reuse link config
      attrs:
        link_type: fabric
```

**Result**: Anchors resolved during YAML parsing; cleaner, less repetitive config

## Example 14: One-to-One Pattern and Zip Expansion

Demonstrating pairwise connectivity patterns.

```yaml
network:
  nodes:
    # 4 servers, 2 switches - compatible for one_to_one (4 is multiple of 2)
    server[1-4]:
      count: 1
      template: "srv"
    switch[1-2]:
      count: 1
      template: "sw"

  links:
    # one_to_one: server1->switch1, server2->switch2, server3->switch1, server4->switch2
    - source: /server
      target: /switch
      pattern: one_to_one
      capacity: 100

    # zip expansion: pairs variables by index (equal-length lists required)
    - source: "server${idx}"
      target: "switch${sw}"
      expand:
        vars:
          idx: [1, 2]
          sw: [1, 2]
        mode: zip            # server1->switch1, server2->switch2
      pattern: one_to_one
      capacity: 50
      cost: 2
```

**Result**: Demonstrates one_to_one modulo wrap and zip expansion mode

## Example 15: Traffic Demands with Variable Expansion and Group Modes

Advanced demand configuration.

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
  # Variable expansion in demands
  inter_dc:
    - source: "^${src}/.*"
      target: "^${dst}/.*"
      volume: 50
      expand:
        vars:
          src: [dc1, dc2]
          dst: [dc2, dc3]
        mode: zip            # dc1->dc2, dc2->dc3

  # Group modes with group_by
  grouped:
    - source:
        group_by: dc
      target:
        group_by: dc
      volume: 100
      mode: pairwise
      group_mode: per_group          # Separate demand per group pair
      priority: 1
      flow_policy: SHORTEST_PATHS_WCMP
```

**Result**: Shows variable expansion in demands, group_mode, and priority

## Example 16: Hierarchical Risk Groups

Nested risk group structure with children.

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
  - name: Rack1
    attrs: {location: "DC1-Row1"}
    children:
      - name: Rack1_Card1
        attrs: {slot: 1}
      - name: Rack1_Card2
        attrs: {slot: 2}
  - name: Rack2
    disabled: false
    attrs: {location: "DC1-Row2"}

failures:
  hierarchical:
    expand_groups: true
    expand_children: true   # Failing Rack1 also fails Card1, Card2
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            mode: choice
            count: 1
            match:
              conditions:
                - attr: location
                  op: contains    # String contains
                  value: "DC1"
```

**Result**: Hierarchical risk groups with recursive child failure expansion

## Example 17: Risk Group Membership Rules

Dynamically assign entities based on attributes.

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
        route_type: backbone
        path_id: primary
    - source: core1
      target: edge1
      capacity: 400

risk_groups:
  # Assign all core tier-3 nodes
  - name: CoreTier3
    membership:
      scope: node
      match:
        logic: and              # Must match ALL conditions
        conditions:
          - attr: role
            op: "=="
            value: core
          - attr: tier
            op: "=="
            value: 3

  # Assign links by route type
  - name: BackboneLinks
    membership:
      scope: link
      match:
        logic: and
        conditions:
          - attr: route_type      # Dot-notation for nested attrs
            op: "=="
            value: backbone

  # String shorthand for simple groups
  - "ManualGroup1"
```

**Result**: Nodes and links automatically assigned to risk groups based on attributes

## Example 18: Generated Risk Groups

Create risk groups from unique attribute values.

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
  # Generate risk group per datacenter (from nodes)
  - generate:
      scope: node
      group_by: datacenter
      name: "DC_${value}"
      attrs:
        generated: true
        type: location

  # Generate risk group per rack (from nodes)
  - generate:
      scope: node
      group_by: rack
      name: "Rack_${value}"

  # Generate risk group per connection type (from links)
  - generate:
      scope: link
      group_by: connection_type
      name: "Links_${value}"
```

**Result**: Creates 6 risk groups:

- `DC_dc1` (srv1, srv2)
- `DC_dc2` (srv3)
- `Rack_r1` (srv1, srv3)
- `Rack_r2` (srv2)
- `Links_intra_dc` (link srv1→srv2)
- `Links_inter_dc` (link srv2→srv3)

## Example 19: Additional Selector Operators

Demonstrating all condition operators.

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
    # Tier comparison operators
    - source:
        match:
          conditions:
            - attr: tier
              op: ">="
              value: 2
      target:
        match:
          conditions:
            - attr: tier
              op: "<"
              value: 3
      volume: 50
      mode: pairwise

    # List membership operators
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
              op: contains     # List contains value
              value: prod
      volume: 25
      mode: combine

    # Existence operators
    - source:
        match:
          conditions:
            - attr: region
              op: exists       # Attribute exists and not null
      target:
        match:
          conditions:
            - attr: region
              op: not_exists   # Attribute missing or null
      volume: 10
      mode: pairwise
```

**Result**: Demonstrates `>=`, `<`, `in`, `contains`, `exists`, `not_exists` operators

## Example 20: link_match and Rule Expansion

Using `link_match` to filter link rules by the link's own attributes, and `expand` for variable-based rule application.

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

  # Update only high-capacity fiber links
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

  # Apply node rules using variable expansion
  node_rules:
    - path: "${dc}_srv"
      expand:
        vars:
          dc: [dc1, dc2]
        mode: cartesian
      attrs:
        tagged: true
```

**Result**: Only the 500-capacity fiber link (dc1_srv -> dc2_srv) gets cost 99. Nodes dc1_srv and dc2_srv are tagged.

## Example 21: Nested Inline Nodes (No Blueprint)

Creating hierarchical topology structure without using blueprints.

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
    # Connect servers to their TOR switch in each rack
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
    # Connect TOR switches
    - source: datacenter/rack1/tor/sw1
      target: datacenter/rack2/tor/sw1
      capacity: 100
```

**Result**: Creates 10 nodes (2 switches + 8 servers) in a two-rack hierarchy. All nodes inherit `region: west` and `tier: 1` from the datacenter parent. Each rack's nodes get the appropriate `rack_id`.

## Example 22: path Filter in Generate Blocks

Using `path` to narrow entities before generating risk groups.

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
  # Generate env-based risk groups only for production nodes
  - generate:
      scope: node
      path: "^prod_.*"
      group_by: env
      name: "Env_${value}"
      attrs:
        generated: true
        critical: true

  # Generate service-based risk groups for all nodes
  - generate:
      scope: node
      group_by: service
      name: "Service_${value}"

  # Generate link risk groups only for production links
  - generate:
      scope: link
      path: ".*prod.*"
      group_by: link_type
      name: "ProdLinks_${value}"

demands:
  baseline:
    - source: "^prod_web.*"
      target: "^prod_db.*"
      volume: 50
      mode: pairwise
      flow_policy: SHORTEST_PATHS_ECMP

failures:
  production_failure:
    expand_groups: true
    modes:
      - weight: 1.0
        rules:
          - scope: risk_group
            path: "^Env_.*"
            mode: choice
            count: 1
```

**Result**: Creates the following risk groups:

- `Env_production` (only production nodes due to path filter)
- `Service_web` (prod_web1, prod_web2, dev_web1)
- `Service_database` (prod_db1, dev_db1)
- `ProdLinks_internal` (only production links due to path filter)

Note: `Env_development` is NOT created because dev nodes don't match `^prod_.*`.
