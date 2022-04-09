# Zentt
    Create 1000000 empty entities
      25ms (26.00ns)
      16ms (16.00ns)
      7ms (8.00ns)
      8ms (9.00ns)
      9ms (9.00ns)
      9ms (9.00ns)
      8ms (9.00ns)
      9ms (10.00ns)
      10ms (10.00ns)
      8ms (9.00ns)
    Total: 11.50ms (5.28, 5.56)
    Iter:  11.50ns (5.28, 5.56)

    Create 1000000 entities and add PositionComponent
      67ms (68.00ns)
      60ms (61.00ns)
      49ms (49.99ns)
      49ms (50.00ns)
      49ms (49.99ns)
      48ms (49.00ns)
      50ms (51.00ns)
      50ms (50.99ns)
      48ms (48.99ns)
      49ms (50.00ns)
    Total: 52.90ms (6.04, 6.37)
    Iter:  52.90ns (6.04, 6.37)

    Create 1000000 entities and add five small components
      457ms (458.00ns)
      534ms (535.00ns)
      360ms (360.02ns)
      341ms (341.03ns)
      347ms (347.51ns)
      332ms (332.02ns)
      336ms (337.00ns)
      338ms (338.00ns)
      331ms (332.00ns)
      335ms (335.51ns)
    Total: 371.61ms (65.25, 68.78)
    Iter:  371.61ns (65.25, 68.78)

    Create 1000000 entities and add five small components as bundle
      157ms (158.00ns)
      146ms (146.00ns)
      88ms (89.00ns)
      88ms (88.01ns)
      89ms (90.00ns)
      87ms (88.00ns)
      87ms (88.00ns)
      87ms (88.00ns)
      90ms (91.00ns)
      87ms (87.00ns)
    Total: 101.30ms (25.51, 26.89)
    Iter:  101.30ns (25.51, 26.89)

    Create 1000000 entities and add eight components
      847ms (847.00ns)
      838ms (838.49ns)
      693ms (693.02ns)
      692ms (692.00ns)
      688ms (689.00ns)
      697ms (697.02ns)
      689ms (689.98ns)
      696ms (697.00ns)
      687ms (687.02ns)
      692ms (692.96ns)
    Total: 722.35ms (60.30, 63.57)
    Iter:  722.35ns (60.30, 63.57)

    Create 1000000 entities and add eight components as bundle
      304ms (305.00ns)
      317ms (318.00ns)
      136ms (137.00ns)
      135ms (136.00ns)
      139ms (140.00ns)
      141ms (142.00ns)
      135ms (135.99ns)
      138ms (139.00ns)
      137ms (138.00ns)
      133ms (134.00ns)
    Total: 172.50ms (69.59, 73.36)
    Iter:  172.50ns (69.59, 73.36)

    Add one component to 1000000 entities with 5 components
      213ms (213.00ns)
      226ms (226.00ns)
      120ms (120.02ns)
      121ms (121.02ns)
      120ms (121.00ns)
      119ms (119.00ns)
      120ms (121.00ns)
      119ms (120.00ns)
      119ms (120.00ns)
      121ms (121.03ns)
    Total: 140.21ms (39.76, 41.91)
    Iter:  140.21ns (39.76, 41.91)

    Run 1000000 create entity commands. 
      Record (per entity):     84ms (84.97ns)
      Apply (per entity):      15ms (15.02ns)

      Record (per entity):     15ms (15.98ns)
      Apply (per entity):      16ms (16.02ns)

      Record (per entity):     16ms (16.02ns)
      Apply (per entity):      12ms (12.00ns)

      Record (per entity):     18ms (18.00ns)
      Apply (per entity):      12ms (13.00ns)

      Record (per entity):     17ms (17.02ns)
      Apply (per entity):      10ms (10.99ns)

      Record (per entity):     17ms (17.00ns)
      Apply (per entity):      13ms (13.00ns)

      Record (per entity):     16ms (16.00ns)
      Apply (per entity):      11ms (11.00ns)

      Record (per entity):     16ms (16.00ns)
      Apply (per entity):      12ms (12.00ns)

      Record (per entity):     16ms (16.00ns)
      Apply (per entity):      10ms (10.00ns)

      Record (per entity):     16ms (16.00ns)
      Apply (per entity):      10ms (11.00ns)

    Total: 23.30ms (20.57, 21.68)
    Iter:  23.30ns (20.57, 21.68)

    Total: 12.40ms (1.81, 1.91)
    Iter:  12.40ns (1.81, 1.91)

    Run 1000000 create entity and eight add component commands. 
      Record (per entity):     1018ms (1018.06ns)
      Apply (per entity):      909ms (909.70ns)

      Record (per entity):     201ms (201.00ns)
      Apply (per entity):      894ms (894.80ns)

      Record (per entity):     212ms (212.55ns)
      Apply (per entity):      739ms (739.67ns)

      Record (per entity):     201ms (202.00ns)
      Apply (per entity):      754ms (754.88ns)

      Record (per entity):     262ms (262.14ns)
      Apply (per entity):      768ms (768.04ns)

      Record (per entity):     257ms (257.00ns)
      Apply (per entity):      868ms (868.54ns)

      Record (per entity):     207ms (208.00ns)
      Apply (per entity):      726ms (726.77ns)

      Record (per entity):     204ms (204.01ns)
      Apply (per entity):      722ms (722.47ns)

      Record (per entity):     218ms (219.00ns)
      Apply (per entity):      739ms (739.66ns)

      Record (per entity):     207ms (207.31ns)
      Apply (per entity):      722ms (722.62ns)

    Total: 299.11ms (240.58, 253.59)
    Iter:  299.11ns (240.58, 253.59)

    Total: 784.72ms (71.47, 75.34)
    Iter:  784.72ns (71.47, 75.34)

    Run 1000000 create entity bundle commands with eight components. 
      Record (per entity):     234ms (234.00ns)
      Apply (per entity):      383ms (384.00ns)

      Record (per entity):     79ms (79.00ns)
      Apply (per entity):      377ms (377.64ns)

      Record (per entity):     87ms (88.00ns)
      Apply (per entity):      233ms (233.51ns)

      Record (per entity):     90ms (91.00ns)
      Apply (per entity):      239ms (239.00ns)

      Record (per entity):     84ms (84.61ns)
      Apply (per entity):      234ms (234.04ns)

      Record (per entity):     81ms (81.03ns)
      Apply (per entity):      233ms (234.00ns)

      Record (per entity):     81ms (82.00ns)
      Apply (per entity):      231ms (231.00ns)

      Record (per entity):     79ms (80.00ns)
      Apply (per entity):      231ms (231.10ns)

      Record (per entity):     96ms (96.00ns)
      Apply (per entity):      233ms (233.00ns)

      Record (per entity):     89ms (89.00ns)
      Apply (per entity):      233ms (234.00ns)

      Total: 100.46ms (44.81, 47.23)
      Iter:  100.46ns (44.81, 47.23)

      Total: 263.13ms (58.90, 62.08)
      Iter:  263.13ns (58.90, 62.08)

    Run 1000000 add component commands. 
      Record (per entity):     125ms (125.86ns)
      Apply (per entity):      239ms (239.99ns)

      Record (per entity):     39ms (40.00ns)
      Apply (per entity):      224ms (224.00ns)

      Record (per entity):     36ms (36.94ns)
      Apply (per entity):      129ms (129.21ns)

      Record (per entity):     37ms (37.82ns)
      Apply (per entity):      130ms (130.00ns)

      Record (per entity):     45ms (45.00ns)
      Apply (per entity):      193ms (194.00ns)

      Record (per entity):     37ms (38.00ns)
      Apply (per entity):      131ms (131.00ns)

      Record (per entity):     38ms (38.00ns)
      Apply (per entity):      131ms (131.00ns)

      Record (per entity):     37ms (38.00ns)
      Apply (per entity):      131ms (131.98ns)

      Record (per entity):     35ms (36.00ns)
      Apply (per entity):      141ms (141.00ns)

      Record (per entity):     38ms (38.00ns)
      Apply (per entity):      129ms (129.56ns)

    Total: 47.36ms (26.27, 27.69)
    Iter:  47.36ns (26.27, 27.69)

    Total: 158.18ms (41.50, 43.74)
    Iter:  158.18ns (41.50, 43.74)

    Iterate 1000000 entities with PositionComponent
      2ms (2.00ns)
      2ms (2.00ns)
      2ms (2.00ns)
      2ms (2.00ns)
      1ms (2.00ns)
      1ms (2.00ns)
      2ms (2.00ns)
      1ms (2.00ns)
      2ms (2.00ns)
      2ms (3.00ns)
    Total: 2.10ms (0.30, 0.32)
    Iter:  2.10ns (0.30, 0.32)

# entt
    Create 1000000 empty entities
      3.88ms (3.88ns)
      3.58ms (3.58ns)
      4.23ms (4.23ns)
      4.10ms (4.10ns)
      3.94ms (3.94ns)
      3.66ms (3.66ns)
      4.17ms (4.17ns)
      3.72ms (3.72ns)
      3.59ms (3.59ns)
      3.60ms (3.60ns)
    Total: 3.85ms (0.24, 0.25)
    Iter:  3.85ns (0.24, 0.25)

    Create 1000000 entities and add PositionComponent
      36.77ms (36.77ns)
      22.45ms (22.45ns)
      21.70ms (21.70ns)
      21.19ms (21.19ns)
      20.34ms (20.34ns)
      20.39ms (20.39ns)
      20.20ms (20.20ns)
      22.40ms (22.40ns)
      20.49ms (20.49ns)
      20.14ms (20.14ns)
    Total: 22.61ms (4.79, 5.05)
    Iter:  22.61ns (4.79, 5.05)

    Create 1000000 entities and add five small components
      155.99ms (155.99ns)
      105.98ms (105.98ns)
      113.49ms (113.49ns)
      107.69ms (107.69ns)
      112.86ms (112.86ns)
      220.04ms (220.04ns)
      148.57ms (148.57ns)
      137.90ms (137.90ns)
      141.21ms (141.21ns)
      118.42ms (118.42ns)
    Total: 136.21ms (32.72, 34.49)
    Iter:  136.21ns (32.72, 34.49)

    Create 1000000 entities and add eight components
      318.42ms (318.42ns)
      208.96ms (208.96ns)
      194.44ms (194.44ns)
      189.18ms (189.18ns)
      272.01ms (272.01ns)
      192.00ms (192.00ns)
      187.95ms (187.95ns)
      282.62ms (282.62ns)
      199.61ms (199.61ns)
      195.84ms (195.84ns)
    Total: 224.10ms (45.47, 47.93)
    Iter:  224.10ns (45.47, 47.93)

    Add one component to 1000000 entities with 5 components
      45.37ms (45.37ns)
      21.19ms (21.19ns)
      20.95ms (20.95ns)
      20.69ms (20.69ns)
      21.34ms (21.34ns)
      20.61ms (20.61ns)
      21.04ms (21.04ns)
      20.80ms (20.80ns)
      20.62ms (20.62ns)
      20.55ms (20.55ns)
    Total: 23.32ms (7.36, 7.75)
    Iter:  23.32ns (7.36, 7.75)

    Iterate 1000000 entities with PositionComponent using view for
      4.00ms (4.00ns)
      3.22ms (3.22ns)
      3.08ms (3.08ns)
      4.01ms (4.01ns)
      5.51ms (5.51ns)
      3.58ms (3.58ns)
      3.43ms (3.43ns)
      4.48ms (4.48ns)
      3.81ms (3.81ns)
      3.56ms (3.56ns)
    Total: 3.87ms (0.67, 0.71)
    Iter:  3.87ns (0.67, 0.71)

    Iterate 1000000 entities with PositionComponent using view each
      2.35ms (2.35ns)
      1.67ms (1.67ns)
      1.62ms (1.62ns)
      1.57ms (1.57ns)
      1.51ms (1.51ns)
      1.82ms (1.82ns)
      3.03ms (3.03ns)
      1.56ms (1.56ns)
      1.55ms (1.55ns)
      1.56ms (1.56ns)
    Total: 1.83ms (0.47, 0.49)
    Iter:  1.83ns (0.47, 0.49)

# Bevy
    Create 1000000 empty entities
      58.75ms (58.75ns)
      27.45ms (27.45ns)
      25.59ms (25.59ns)
      27.92ms (27.92ns)
      26.06ms (26.06ns)
      27.01ms (27.01ns)
      28.55ms (28.55ns)
      29.39ms (29.39ns)
      26.59ms (26.59ns)
      28.86ms (28.86ns)
    Total: 30.62ms (9.45, 9.96)
    Iter:  30.62ns (9.45, 9.96)

    Create 1000000 entities and add PositionComponent
      141.54ms (141.54ns)
      106.18ms (106.18ns)
      105.35ms (105.35ns)
      101.23ms (101.23ns)
      102.45ms (102.45ns)
      103.64ms (103.64ns)
      111.34ms (111.34ns)
      110.34ms (110.34ns)
      126.01ms (126.01ns)
      107.09ms (107.09ns)
    Total: 111.52ms (12.04, 12.69)
    Iter:  111.52ns (12.04, 12.69)

    Create 1000000 entities and add five small components
      608.04ms (608.04ns)
      530.68ms (530.68ns)
      528.49ms (528.49ns)
      541.16ms (541.16ns)
      521.04ms (521.04ns)
      545.89ms (545.89ns)
      614.19ms (614.19ns)
      537.63ms (537.63ns)
      529.31ms (529.31ns)
      528.63ms (528.63ns)
    Total: 548.51ms (32.05, 33.79)
    Iter:  548.51ns (32.05, 33.79)

    Create 1000000 entities and add five small components as bundle
      244.71ms (244.71ns)
      165.85ms (165.85ns)
      168.84ms (168.84ns)
      170.13ms (170.13ns)
      169.25ms (169.25ns)
      168.23ms (168.23ns)
      248.19ms (248.19ns)
      285.30ms (285.30ns)
      223.23ms (223.23ns)
      221.95ms (221.95ns)
    Total: 206.57ms (41.44, 43.68)
    Iter:  206.57ns (41.44, 43.68)

    Create 1000000 entities and add eight small components
      1196.86ms (1196.86ns)
      1057.69ms (1057.69ns)
      1046.76ms (1046.76ns)
      1046.64ms (1046.64ns)
      1118.68ms (1118.68ns)
      1042.30ms (1042.30ns)
      1038.61ms (1038.61ns)
      1037.74ms (1037.74ns)
      1051.41ms (1051.41ns)
      1037.65ms (1037.65ns)
    Total: 1067.43ms (48.80, 51.44)
    Iter:  1067.43ns (48.80, 51.44)

    Create 1000000 entities and add eight components as bundle
      401.59ms (401.59ns)
      264.82ms (264.82ns)
      267.67ms (267.67ns)
      267.87ms (267.87ns)
      266.80ms (266.80ns)
      267.30ms (267.30ns)
      269.26ms (269.26ns)
      264.33ms (264.33ns)
      269.68ms (269.68ns)
      267.52ms (267.52ns)
    Total: 280.68ms (40.33, 42.52)
    Iter:  280.68ns (40.33, 42.52)

    Add one component to 1000000 entities with 5 components
      326.17ms (326.17ns)
      244.36ms (244.36ns)
      242.71ms (242.71ns)
      241.05ms (241.05ns)
      243.06ms (243.06ns)
      243.72ms (243.72ns)
      246.94ms (246.94ns)
      246.70ms (246.70ns)
      244.64ms (244.64ns)
      246.76ms (246.76ns)
    Total: 252.61ms (24.59, 25.92)
    Iter:  252.61ns (24.59, 25.92)

    Iterate 1000000 entities with PositionComponent
      1.92ms (1.92ns)
      2.09ms (2.09ns)
      2.10ms (2.10ns)
      2.40ms (2.40ns)
      2.10ms (2.10ns)
      2.05ms (2.05ns)
      2.37ms (2.37ns)
      2.14ms (2.14ns)
      2.12ms (2.12ns)
      3.76ms (3.76ns)
    Total: 2.31ms (0.50, 0.53)
    Iter:  2.31ns (0.50, 0.53)