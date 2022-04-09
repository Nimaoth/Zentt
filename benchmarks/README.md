# Benchmarks

This folder contains benchmarks for zentt as well as the following ECS libraries:
- [EnTT](https://github.com/skypjack/entt)
- [Bevy](https://github.com/bevyengine/bevy)

The goal is to compare the performance in similar scenarios, although because of API and implementation differences
each ECS has some unique benchmarks aswell.

## Results

Each benchmark was run 10 times, creating/modifying/iterating 1'000'000 entities, the world/registry containing the entities was only cleared between each run (no new world/registry),
so subsequent runs were faster because memory for components and entities was already allocated in the world.

Numbers in each cell: average, fastest, slowest, all units are in nano second unless specified explicitly.


| Benchmark                                                                     |                   | zentt                  | Bevy                     | EnTT                     |
| :---------------------------------------------------------------------------- | ----------------- | ---------------------- | ------------------------ | ------------------------ |
| Create empty entity                                                           | Avg<br>Min<br>Max | 11 <br> 8 <br> 26      | 30 <br> 25 <br> 58       | 3.85 <br> 3.58 <br> 4.23 |
| Create entity, add component (8 bytes)                                        | Avg<br>Min<br>Max | 52 <br> 48 <br> 68     | 111 <br> 101 <br> 141    | 22 <br> 20 <br> 36       |
| Create entity, add 5 components (72 bytes)                                    | Avg<br>Min<br>Max | 371 <br> 332 <br> 458  | 548 <br> 521 <br> 608    | 136 <br> 105 <br> 155    |
| Create entity bundle with 5 components (72 bytes)                             | Avg<br>Min<br>Max | 101 <br> 87 <br> 158   | 206 <br> 165 <br> 244    | -                        |
| Create entity, add 8 components (192 bytes)                                   | Avg<br>Min<br>Max | 722 <br> 687 <br> 847  | 1067 <br> 1037 <br> 1196 | 224 <br> 189 <br> 318    |
| Create entity bundle with 8 components (192 bytes)                            | Avg<br>Min<br>Max | 172 <br> 134 <br> 318  | 280 <br> 264 <br> 401    | -                        |
| Add component (40 bytes) to entity <br> with 5 components (72 bytes)          | Avg<br>Min<br>Max | 140 <br> 119 <br> 226  | 252 <br> 241 <br> 326    | 23 <br> 20 <br> 45       |
|                                                                               |                   |                        |                          |                          |
| Record create entity commands                                                 | Avg<br>Min<br>Max | 22 <br> 15 <br> 86     | -                        | -                        |
| Apply create entity commands                                                  | Avg<br>Min<br>Max | 12 <br> 10 <br> 18     | -                        | -                        |
| Record create entity commands <br> and add 8 components (192 bytes)           | Avg<br>Min<br>Max | 299 <br> 201 <br> 1018 | -                        | -                        |
| Apply create entity commands <br> and add 8 components (192 bytes)            | Avg<br>Min<br>Max | 784 <br> 722 <br> 909  | -                        | -                        |
| Record create entity bundle commands <br> with 8 components (192 bytes)       | Avg<br>Min<br>Max | 100 <br> 79 <br> 234 | -                        | -                        |
| Apply create entity bundle commands <br> withand add 8 components (192 bytes) | Avg<br>Min<br>Max | 263 <br> 231 <br> 383  | -                        | -                        |
|                                                                               |                   |                        |                          |                          |
| Add component (40 bytes) to entity <br> with 5 components (72 bytes)          | Avg<br>Min<br>Max | 140 <br> 119 <br> 226  | 252 <br> 241 <br> 326    | 23 <br> 20 <br> 45       |

## Raw Results
[This](raw.md) contains the raw output from the benchmark programs.
