#![allow(unused_imports)]
#![allow(unused_variables)]
#![allow(dead_code)]

use bevy_ecs::{
    component::Component,
    entity::Entity,
    system::{Command, CommandQueue, Commands, Query},
    world::World,
};

fn main() {
    println!("Benchmarking bevy");

    let entity_count = 1_000_000;
    let iterations = 10;

    create_empty_entities(iterations, entity_count);
    create_entities_add_one_comp(iterations, entity_count);
    create_entities_add_five_comps(iterations, entity_count);
    create_entities_add_five_comps_bundle(iterations, entity_count);
    create_entities_add_eight_comps(iterations, entity_count);
    create_entities_add_eight_comps_bundle(iterations, entity_count);
    add_component(iterations, entity_count);

    iter_entities_one_comp(iterations, entity_count);
}
#[derive(Component, Clone, Copy)]
struct PositionComponent {
    x: f32,
    y: f32,
}

#[derive(Component, Clone, Copy)]
struct DirectionComponent  {
    x: f32,
    y: f32,
}

#[derive(Component, Clone, Copy)]
struct ComflabulationComponent  {
    thingy: f32,
    dingy: i32,
    mingy: bool,
    stringy: &'static str,
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp1  {
    a: i64,
    b: f64,
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp2  {
    a: i64,
    b: f64,
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp3  {
    a: i64,
    b: f64,
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp4  {
    a: i64,
    b: f64,
} 

#[derive(Component, Clone, Copy, Default)]
struct TestComp5  {
    a: i64,
    b: f64,
    c: bool,
    d: [u64; 2],
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp6  {
    a: i64,
    b: f64,
    c: bool,
    d: [u64; 2],
}

#[derive(Component, Clone, Copy, Default)]
struct TestComp7  {
    a: i64,
    b: f64,
    c: bool,
    d: [u64; 2],
}

fn create_empty_entities(iterations: u64, entity_count: u64) {
    println!("  Create {} empty entities", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();
   
    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world.spawn();
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn create_entities_add_one_comp(iterations: u64, entity_count: u64) {
    println!("  Create {} entities and add PositionComponent", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world.spawn().insert(PositionComponent{x: 0.0, y: 0.0});
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn create_entities_add_five_comps(iterations: u64, entity_count: u64) {
    println!("  Create {} entities and add five small components", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world
                .spawn()
                .insert(PositionComponent{x: 0.0, y: 0.0})
                .insert(TestComp1::default())
                .insert(TestComp2::default())
                .insert(TestComp3::default())
                .insert(TestComp4::default());
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn create_entities_add_five_comps_bundle(iterations: u64, entity_count: u64) {
    println!("  Create {} entities and add five small components as bundle", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world
                .spawn()
                .insert_bundle((PositionComponent{x: 0.0, y: 0.0}, TestComp1::default(), TestComp2::default(), TestComp3::default(), TestComp4::default()));
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn create_entities_add_eight_comps(iterations: u64, entity_count: u64) {
    println!("  Create {} entities and add eight small components", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world
                .spawn()
                .insert(PositionComponent{x: 0.0, y: 0.0})
                .insert(TestComp1::default())
                .insert(TestComp2::default())
                .insert(TestComp3::default())
                .insert(TestComp4::default())
                .insert(TestComp5::default())
                .insert(TestComp6::default())
                .insert(TestComp7::default());
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn create_entities_add_eight_comps_bundle(iterations: u64, entity_count: u64) {
    println!("  Create {} entities and add eight components as bundle", entity_count);

    let mut world = World::default();

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        t.start();
        for _ in 0..entity_count {
            world
                .spawn()
                .insert_bundle((
                    PositionComponent{x: 0.0, y: 0.0},
                    TestComp1::default(),
                    TestComp2::default(),
                    TestComp3::default(),
                    TestComp4::default(),
                    TestComp5::default(),
                    TestComp6::default(),
                    TestComp7::default(),
                ));
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn add_component(iterations: u64, entity_count: u64) {
    println!("  Add one component to {} entities with 5 components", entity_count);

    let mut world = World::default();

    let mut entities = vec![];

    let mut t = Timer::new();

    for _ in 0..iterations {
        world.clear_entities();
        entities.clear();

        for _ in 0..entity_count {
            entities.push(world
                .spawn()
                .insert_bundle((
                    PositionComponent{x: 0.0, y: 0.0},
                    TestComp1::default(),
                    TestComp2::default(),
                    TestComp3::default(),
                    TestComp4::default(),
                )).id());
        }

        t.start();
        for e in &entities {
            world.entity_mut(*e).insert(TestComp7::default());
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

fn iter_entities_one_comp(iterations: u64, entity_count: u64) {
    println!("  Iterate {} entities with PositionComponent", entity_count);

    let mut world = World::default();
    for _ in 0..entity_count {
        world.spawn().insert(PositionComponent{x: 0.0, y: 0.0});
    }

    let mut t = Timer::new();

    for _ in 0..iterations {
        let mut query = world.query::<&mut PositionComponent>();
        t.start();
        for mut position in query.iter_mut(&mut world) {
            position.x *= 1.000001;
        }
        t.end(entity_count);
    }
    t.print_avg_stats();
}

// Utilities

pub fn black_box<T>(dummy: T) -> T {
    unsafe {
        let ret = std::ptr::read_volatile(&dummy);
        std::mem::forget(dummy);
        ret
    }
}

struct RunningMean {
    count: f64,
    mean: f64,
    m2: f64,
}

struct RunningMeanStats {
    mean: f64,
    variance: f64,
    sample_variance: f64,
}

impl RunningMean {
    pub fn new() -> Self {
        RunningMean { count: 0.0, mean: 0.0, m2: 0.0 }
    }

    pub fn update(&mut self, value: f64) {
        self.count += 1.0;

        let delta = value - self.mean;
        self.mean += delta / self.count;

        let delta2 = value - self.mean;
        self.m2 += delta * delta2;
    }

    pub fn get_stats(self) -> RunningMeanStats {
        return RunningMeanStats {
            mean: self.mean,
            variance: (self.m2 / self.count).sqrt(),
            sample_variance: (self.m2 / (self.count - 1.0)).sqrt(),
        };
    }
}

struct Timer {
    start_time: std::time::Instant,
    total_sum_ms: f64,
    iter_sum_ns: f64,
    count: f64,

    total: RunningMean,
    iter: RunningMean,
}

impl Timer {
    pub fn new() -> Self {
        Timer {
            start_time: std::time::Instant::now(),
            total_sum_ms: 0.0,
            iter_sum_ns: 0.0,
            count: 0.0,

            total: RunningMean::new(),
            iter: RunningMean::new(),
        }
    }

    pub fn start(&mut self) {
        self.start_time = std::time::Instant::now();
    }

    pub fn end(&mut self, count: u64) {
        let now = std::time::Instant::now();
        let delta = now - self.start_time;

        let total_delta = delta.as_secs_f64() * 1000.0;
        let iter_delta = delta.as_secs_f64() * (1_000_000_000.0 / (count as f64));

        self.total_sum_ms += total_delta;
        self.iter_sum_ns += iter_delta;

        self.total.update(total_delta);
        self.iter.update(iter_delta);

        self.count += 1.0;

        println!("    {:.2}ms ({:.2}ns)", total_delta, iter_delta);
    }

    pub fn print_avg_stats(self) {
        // println!("  {:.2}ms ({:.2}ns)",  self.total_sum_ms / self.count, self.iter_sum_ns / self.count );

        let total_result = self.total.get_stats();
        let iter_result = self.iter.get_stats();
        println!("  Total: {:.2}ms ({:.2}, {:.2})", total_result.mean, total_result.variance, total_result.sample_variance);
        println!("  Iter:  {:.2}ns ({:.2}, {:.2})\n", iter_result.mean, iter_result.variance, iter_result.sample_variance);
    }
}