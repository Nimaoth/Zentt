#include <entt/entt.hpp>
#include <iostream>

#include "util.h"

void createEmptyEntities32(int64_t iterations, int64_t entity_count);
void createEmptyEntities64(int64_t iterations, int64_t entity_count);
void createEmptyEntitiesAddOneComp(int64_t iterations, int64_t entity_count);
void iterEntitiesOneCompViewFor(int64_t iterations, int64_t entity_count);
void iterEntitiesOneCompViewEach(int64_t iterations, int64_t entity_count);
void iterEntitiesOneCompViewEach2(int64_t iterations, int64_t entity_count);

int main() {
    printf("Benchmarking entt\n");

    const int64_t entity_count = 10'000'000;
    const int64_t iterations = 10;

    createEmptyEntities32(iterations, entity_count);
    createEmptyEntities64(iterations, entity_count);
    createEmptyEntitiesAddOneComp(iterations, entity_count);
    iterEntitiesOneCompViewFor(iterations, entity_count);
    iterEntitiesOneCompViewEach(iterations, entity_count);
    iterEntitiesOneCompViewEach2(iterations, entity_count);

    return 0;
}

struct PositionComponent {
    float x = 0;
    float y = 0;
};

struct DirectionComponent {
    float x = 0;
    float y = 0;
};

struct ComflabulationComponent {
    float thingy = 0;
    int32_t dingy = 0;
    bool mingy = false;
    const char* stringy = "";
};

void createEmptyEntities32(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld empty entities (32 bit id)\n", entity_count);
    entt::registry registry;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();

        t.start();
        for (int64_t k = 0; k < entity_count; k++) {
            registry.create();
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void createEmptyEntities64(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld empty entities (64 bit id)\n", entity_count);
    entt::basic_registry<uint64_t> registry;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();

        t.start();
        for (int64_t k = 0; k < entity_count; k++) {
            registry.create();
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void createEmptyEntitiesAddOneComp(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld entities and add PositionComponent (64 bit id)\n", entity_count);
    entt::basic_registry<uint64_t> registry;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();

        t.start();
        for (int64_t k = 0; k < entity_count; k++) {
            auto e = registry.create();
            registry.emplace<PositionComponent>(e, 0.0f, 0.0f);
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void iterEntitiesOneCompViewFor(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with PositionComponent using view for (64 bit id)\n", entity_count);
    entt::basic_registry<uint64_t> registry;

    for (int64_t k = 0; k < entity_count; k++) {
        auto entity = registry.create();
        registry.emplace<PositionComponent>(entity);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent>();
        t.start();
        for (auto entity : view) {
            view.get<PositionComponent>(entity).x *= 1.000001;
        }
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesOneCompViewEach(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with PositionComponent using view each (64 bit id)\n", entity_count);
    entt::basic_registry<uint64_t> registry;

    for (int64_t k = 0; k < entity_count; k++) {
        auto entity = registry.create();
        registry.emplace<PositionComponent>(entity);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent>();
        t.start();
        view.each([](auto& pos) {
            pos.x *= 1.000001;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesOneCompViewEach2(int64_t iterations, int64_t entity_count) {
    entity_count /= 10;

    printf("  Iterate %lld entities with PositionComponent using view each (32 bit id)\n", entity_count);
    entt::registry registry;

    for (int64_t k = 0; k < entity_count; k++) {
        auto entity = registry.create();
        registry.emplace<PositionComponent>(entity);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent>();
        t.start();
        view.each([](auto& pos) {
            pos.x *= 1.000001;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}