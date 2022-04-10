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


| Benchmark                                                                                 |                        | zentt                         | Bevy                          | EnTT                                                       |
| :---------------------------------------------------------------------------------------- | ---------------------- | ----------------------------- | ----------------------------- | ---------------------------------------------------------- |
| Create empty entity                                                                       | Avg<br>Min<br>Max      | 11 <br> 8 <br> 26             | 30 <br> 25 <br> 58            | 3.85 <br> 3.58 <br> 4.23                                   |
| Create entity, add component <br> (8 bytes)                                               | Avg<br>Min<br>Max      | 52 <br> 48 <br> 68            | 111 <br> 101 <br> 141         | 22 <br> 20 <br> 36                                         |
| Create entity, add 5 components <br> (72 bytes)                                           | Avg<br>Min<br>Max      | 371 <br> 332 <br> 458         | 548 <br> 521 <br> 608         | 136 <br> 105 <br> 155                                      |
| Create entity bundle with 5 components <br> (72 bytes)                                    | Avg<br>Min<br>Max      | 101 <br> 87 <br> 158          | 206 <br> 165 <br> 244         | -                                                          |
| Create entity, add 8 components <br> (192 bytes)                                          | Avg<br>Min<br>Max      | 722 <br> 687 <br> 847         | 1067 <br> 1037 <br> 1196      | 224 <br> 189 <br> 318                                      |
| Create entity bundle with 8 components <br> (192 bytes)                                   | Avg<br>Min<br>Max      | 172 <br> 134 <br> 318         | 280 <br> 264 <br> 401         | -                                                          |
| Create entity, add five empty components                                                  | Avg<br>Min<br>Max      | <br>  <br>                    | <br>  <br>                    | <br>  <br>                                                 |
| Create entity bundle with <br> five empty components                                      | Avg<br>Min<br>Max      | <br>  <br>                    | <br>  <br>                    | <br>  <br>                                                 |
| Add component (40 bytes) to entity <br> with 5 components (72 bytes)                      | Avg<br>Min<br>Max      | 140 <br> 119 <br> 226         | 252 <br> 241 <br> 326         | 23 <br> 20 <br> 45                                         |
| Add one component (192 bytes) to entity                                                   | Avg<br>Min<br>Max      | <br>  <br>                    | <br>  <br>                    | <br>  <br>                                                 |
|                                                                                           |                        |                               |                               |                                                            |
| Iterate entities with one component                                                       | Avg<br>Min<br>Max      | 2.18 <br> 1.84 <br> 2.87      | 2.31 <br> 1.92 <br> 3.76      | 1.79  <br> 1.54 <br> 2.79                                  |
| Iterate entities with eight components, <br> use three                                    | Avg<br>Min<br>Max      | 8.22 <br> 7.04 <br> 9.76      | 11.50 <br> 9.56 <br> 13.14    | 10.94 <br> 10.11 <br> 11.91                                |
| Iterate entities with eight components, <br> use all                                      | Avg<br>Min<br>Max      | 8.37 <br> 7.14 <br> 9.84      | 12.58 <br> 10.25 <br> 15.84   | 22.21 <br> 18.92 <br> 32.57                                |
| Iterate entities with five components, <br> different combinations, use 2                 | <br> Avg<br>Min<br>Max | <br> 2.54 <br> 1.97 <br> 3.13 | <br> 2.23 <br> 1.87 <br> 3.85 | View, Group<br> 3.28, 1.96 <br> 2.92, 1.41 <br> 3.76, 2.97 |
| Iterate entities with five components, <br> more different combinations, use 2 <br> A & B | Avg<br>Min<br>Max      | 2.21 <br> 2.91 <br> 4.08      | 3.66 <br> 3.04 <br> 4.83      | 4.02 <br> 3.28 <br> 4.92                                   |
| Iterate entities with five components, <br> more different combinations, use 2 <br> A & C | Avg<br>Min<br>Max      | 4.56 <br> 3.84 <br> 6.16      | 4.42 <br> 3.91 <br> 6.06      | 8.85 <br> 7.90 <br> 10.48                                  |
|                                                                                           |                        |                               |                               |                                                            |
| Record create entity commands                                                             | Avg<br>Min<br>Max      | 22 <br> 15 <br> 86            | -                             | -                                                          |
| Apply create entity commands                                                              | Avg<br>Min<br>Max      | 12 <br> 10 <br> 18            | -                             | -                                                          |
| Record create entity commands <br> and add 8 components <br> (192 bytes)                  | Avg<br>Min<br>Max      | 299 <br> 201 <br> 1018        | -                             | -                                                          |
| Apply create entity commands <br> and add 8 components <br> (192 bytes)                   | Avg<br>Min<br>Max      | 784 <br> 722 <br> 909         | -                             | -                                                          |
| Record create entity bundle commands <br> with 8 components <br> (192 bytes)              | Avg<br>Min<br>Max      | 100 <br> 79 <br> 234          | -                             | -                                                          |
| Apply create entity bundle commands <br> withand add 8 components <br> (192 bytes)        | Avg<br>Min<br>Max      | 263 <br> 231 <br> 383         | -                             | -                                                          |
|                                                                                           |                        |                               |                               |                                                            |
|                                                                                           | Avg<br>Min<br>Max      | <br>  <br>                    | <br>  <br>                    | <br>  <br>                                                 |

## Raw Results
[This](raw.md) contains the raw output from the benchmark programs.
