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
void iterEntitiesEightCompsUseThree(int64_t iterations, int64_t entity_count);
void iterEntitiesEightCompsUseAll(int64_t iterations, int64_t entity_count);
void iterEntitiesFiveCompsDifferentCombsUseTwoView(int64_t iterations, int64_t entity_count);
void iterEntitiesFiveCompsDifferentCombsUseTwoGroup(int64_t iterations, int64_t entity_count);
void iterEntitiesFiveCompsDifferentCombsUseTwoGroup2(int64_t iterations, int64_t entity_count);

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
    iterEntitiesEightCompsUseThree(iterations, entity_count);
    iterEntitiesEightCompsUseAll(iterations, entity_count);
    iterEntitiesFiveCompsDifferentCombsUseTwoView(iterations, entity_count);
    iterEntitiesFiveCompsDifferentCombsUseTwoGroup(iterations, entity_count);
    iterEntitiesFiveCompsDifferentCombsUseTwoGroup2(iterations, entity_count);

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

void iterEntitiesEightCompsUseThree(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with eight components, use three\n", entity_count);
    entt::registry registry;

    for (int64_t k = 0; k < entity_count; k++) {
        auto e = registry.create();
        registry.emplace<PositionComponent>(e);
        registry.emplace<TestComp1>(e);
        registry.emplace<TestComp2>(e);
        registry.emplace<TestComp3>(e);
        registry.emplace<TestComp4>(e);
        registry.emplace<TestComp5>(e);
        registry.emplace<TestComp6>(e);
        registry.emplace<TestComp7>(e);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent, TestComp1, TestComp7>();
        t.start();
        view.each([](auto& pos, auto& comp1, auto& comp7) {
            pos.x = pos.x * 1.000001 + 1;
            comp1.x = comp1.x * 2 + 1;
            comp7.b = comp7.b * 1.000001 + 1;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesEightCompsUseAll(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with eight components, use all\n", entity_count);
    entt::registry registry;

    for (int64_t k = 0; k < entity_count; k++) {
        auto e = registry.create();
        registry.emplace<PositionComponent>(e);
        registry.emplace<TestComp1>(e);
        registry.emplace<TestComp2>(e);
        registry.emplace<TestComp3>(e);
        registry.emplace<TestComp4>(e);
        registry.emplace<TestComp5>(e);
        registry.emplace<TestComp6>(e);
        registry.emplace<TestComp7>(e);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent, TestComp1, TestComp2, TestComp3, TestComp4, TestComp5, TestComp6, TestComp7>();
        t.start();
        view.each([](auto& pos, auto& comp1, auto& comp2, auto& comp3, auto& comp4, auto& comp5, auto& comp6, auto& comp7) {
            pos.x = pos.x * 1.000001 + 1;
            comp1.x = comp1.x * 2 + 1;
            comp7.b = comp7.b * 1.000001 + 1;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesFiveCompsDifferentCombsUseTwoView(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with five components, different combinations, use 2\n", entity_count);
    entt::registry registry;

    uint64_t x = 0;
    for (int64_t i = 0; i < entity_count; i++) {
        auto e = registry.create();
        registry.emplace<PositionComponent>(e);

        if (i % 2 == 1 || i % 3 == 0) registry.emplace<DirectionComponent>(e, 1.0f, 2.0f);

        x = (x << 1) ^ (x + 1);
        if (i % 2 == 0) registry.emplace<TestComp1>(e);
        if (i % 3 == 0) registry.emplace<TestComp2>(e);
        if (i % 4 == 0) registry.emplace<TestComp3>(e);
        if (i % 5 == 0) registry.emplace<TestComp4>(e);
        if (i % 6 == 0) registry.emplace<TestComp5>(e);
        if (i % 7 == 0) registry.emplace<TestComp6>(e);
        if (i % 8 == 0) registry.emplace<TestComp7>(e);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.view<PositionComponent, DirectionComponent>();
        t.start();
        view.each([](auto& pos, auto& dir) {
            pos.x += dir.x * 2;
            pos.y += dir.y;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesFiveCompsDifferentCombsUseTwoGroup(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with five components, different combinations, use 2, groups\n", entity_count);
    entt::registry registry;

    uint64_t x = 0;
    for (int64_t i = 0; i < entity_count; i++) {
        auto e = registry.create();
        registry.emplace<PositionComponent>(e);

        if (i % 2 == 1 || i % 3 == 0) registry.emplace<DirectionComponent>(e, 1.0f, 2.0f);

        x = (x << 1) ^ (x + 1);
        if (i % 2 == 0) registry.emplace<TestComp1>(e);
        if (i % 3 == 0) registry.emplace<TestComp2>(e);
        if (i % 4 == 0) registry.emplace<TestComp3>(e);
        if (i % 5 == 0) registry.emplace<TestComp4>(e);
        if (i % 6 == 0) registry.emplace<TestComp5>(e);
        if (i % 7 == 0) registry.emplace<TestComp6>(e);
        if (i % 8 == 0) registry.emplace<TestComp7>(e);
    }

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.group<PositionComponent, DirectionComponent>();
        t.start();
        view.each([](auto& pos, auto& dir) {
            pos.x += dir.x * 2;
            pos.y += dir.y;
        });
        t.end(entity_count);
    }
    t.printAvgStats();
}

void iterEntitiesFiveCompsDifferentCombsUseTwoGroup2(int64_t iterations, int64_t entity_count) {
    printf("  Iterate %lld entities with five components, different combinations, use 2, groups\n", entity_count);
    entt::registry registry;

    uint64_t x = 0;
    for (int64_t i = 0; i < entity_count; i++) {
        auto e = registry.create();
        registry.emplace<PositionComponent>(e);

        if (i % 2 == 1 || i % 3 == 0) registry.emplace<DirectionComponent>(e, 1.0f, 2.0f);
        if (i % 2 == 0 || i % 3 != 0) registry.emplace<ComflabulationComponent>(e);

        x = (x << 1) ^ (x + 1);
        if (i % 2 == 0) registry.emplace<TestComp1>(e);
        if (i % 3 == 0) registry.emplace<TestComp2>(e);
        if (i % 4 == 0) registry.emplace<TestComp3>(e);
        if (i % 5 == 0) registry.emplace<TestComp4>(e);
        if (i % 6 == 0) registry.emplace<TestComp5>(e);
        if (i % 7 == 0) registry.emplace<TestComp6>(e);
        if (i % 8 == 0) registry.emplace<TestComp7>(e);
    }

    printf("  Iterate Position and Direction\n");

    timer t;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.group<PositionComponent>(entt::get<DirectionComponent>);

        size_t count = view.size();

        t.start();
        view.each([](auto& pos, auto& dir) {
            pos.x += dir.x * 2;
            pos.y += dir.y;
        });
        t.end(count);
    }
    t.printAvgStats();

    printf("  Iterate Position and Comflab\n");

    timer t2;
    for (int64_t i = 0; i < iterations; i++) {
        auto view = registry.group<PositionComponent>(entt::get<ComflabulationComponent>);

        size_t count = view.size();

        t2.start();
        view.each([](auto& pos, auto& com) {
            pos.x += com.thingy * 2;
            pos.y += com.dingy;
        });
        t2.end(count);
    }
    t2.printAvgStats();
}
