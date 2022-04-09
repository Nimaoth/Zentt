#include <entt/entt.hpp>
#include <iostream>

#include "util.h"

void createEmptyEntities(int64_t iterations, int64_t entity_count);
void createEntitiesAddOneComp(int64_t iterations, int64_t entity_count);
void createEntitiesAddFiveComps(int64_t iterations, int64_t entity_count);
void createEntitiesAddEightComps(int64_t iterations, int64_t entity_count);
void addComponent(int64_t iterations, int64_t entity_count);
void iterEntitiesOneCompViewFor(int64_t iterations, int64_t entity_count);
void iterEntitiesOneCompViewEach(int64_t iterations, int64_t entity_count);

int main() {
    printf("Benchmarking entt\n");

    const int64_t entity_count = 1'000'000;
    const int64_t iterations = 10;

    createEmptyEntities(iterations, entity_count);
    createEntitiesAddOneComp(iterations, entity_count);
    createEntitiesAddFiveComps(iterations, entity_count);
    createEntitiesAddEightComps(iterations, entity_count);

    addComponent(iterations, entity_count);

    iterEntitiesOneCompViewFor(iterations, entity_count);
    iterEntitiesOneCompViewEach(iterations, entity_count);

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

struct TestComp1 {
    int64_t x = 0;
    double y = 0;
};

struct TestComp2 {
    int64_t x = 0;
    double y = 0;
};

struct TestComp3 {
    int64_t x = 0;
    double y = 0;
};

struct TestComp4 {
    int64_t x = 0;
    double y = 0;
};

struct TestComp5 {
    int64_t a = 0;
    double b = 0;
    bool c = 0;
    uint64_t d[2] = {0, 0};
};

struct TestComp6 {
    int64_t a = 0;
    double b = 0;
    bool c = 0;
    uint64_t d[2] = {0, 0};
};

struct TestComp7 {
    int64_t a = 0;
    double b = 0;
    bool c = 0;
    uint64_t d[2] = {0, 0};
};

void createEmptyEntities(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld empty entities\n", entity_count);
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

void createEntitiesAddOneComp(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld entities and add PositionComponent\n", entity_count);
    entt::registry registry;

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

void createEntitiesAddFiveComps(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld entities and add five small components\n", entity_count);
    entt::registry registry;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();

        t.start();
        for (int64_t k = 0; k < entity_count; k++) {
            auto e = registry.create();
            registry.emplace<PositionComponent>(e, 0.0f, 0.0f);
            registry.emplace<TestComp1>(e);
            registry.emplace<TestComp2>(e);
            registry.emplace<TestComp3>(e);
            registry.emplace<TestComp4>(e);
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void createEntitiesAddEightComps(int64_t iterations, int64_t entity_count) {
    printf("  Create %lld entities and add eight components\n", entity_count);
    entt::registry registry;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();

        t.start();
        for (int64_t k = 0; k < entity_count; k++) {
            auto e = registry.create();
            registry.emplace<PositionComponent>(e, 0.0f, 0.0f);
            registry.emplace<TestComp1>(e);
            registry.emplace<TestComp2>(e);
            registry.emplace<TestComp3>(e);
            registry.emplace<TestComp4>(e);
            registry.emplace<TestComp5>(e);
            registry.emplace<TestComp6>(e);
            registry.emplace<TestComp7>(e);
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void addComponent(int64_t iterations, int64_t entity_count) {
    printf("  Add one component to %lld entities with 5 components\n", entity_count);
    entt::registry registry;

    std::vector<entt::entity> entities;

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        registry.clear();
        entities.clear();

        for (int64_t k = 0; k < entity_count; k++) {
            auto e = registry.create();
            registry.emplace<PositionComponent>(e, 0.0f, 0.0f);
            registry.emplace<TestComp1>(e);
            registry.emplace<TestComp2>(e);
            registry.emplace<TestComp3>(e);
            registry.emplace<TestComp4>(e);
            entities.push_back(e);
        }

        t.start();
        for (entt::entity e : entities) {
            registry.emplace<TestComp5>(e);
        }
        t.end(entity_count);
    }

    t.printAvgStats();
}

void iterEntitiesOneCompViewFor(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with PositionComponent using view for\n", entity_count);
    entt::registry registry;

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
    printf("  Iterate %lld entities with PositionComponent using view each\n", entity_count);
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
