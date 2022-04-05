#include <chrono>
#include <iostream>

struct RunningMean {
    double count = 0;
    double mean = 0;
    double m2 = 0;

    struct Stats {
        double mean;
        double variance;
        double sample_variance;
    };

    void update(double value) {
        count += 1;

        double delta = value - mean;
        mean += delta / count;

        double delta2 = value - mean;
        m2 += delta * delta2;
    }

    Stats getStats() {
        return {
            mean,
            sqrt(m2 / count),
            sqrt(m2 / (count - 1)),
        };
    }
};

struct timer final {
    timer() : start_time{std::chrono::system_clock::now()} {}

    void start() {
        start_time = std::chrono::system_clock::now();
    }

    void end(uint64_t count) {
        auto now = std::chrono::system_clock::now();
        std::chrono::duration delta = (now - start_time);

        double total_delta = std::chrono::duration_cast<std::chrono::duration<double, std::milli>>(delta).count();
        double iter_delta = std::chrono::duration_cast<std::chrono::duration<double, std::nano>>(delta).count() / (double)count;

        total_sum_ms += total_delta;
        iter_sum_ns += iter_delta;

        total.update(total_delta);
        iter.update(iter_delta);

        this->count += 1;

        printf("    %.2fms (%.2fns)\n", total_delta, iter_delta);
    }

    void printAvgStats() {
        // printf("  %.2fms (%.2fns)\n", total_sum_ms / count, iter_sum_ns / count);
        auto total_stats = total.getStats();
        auto iter_stats = iter.getStats();
        printf("  Total: %.2fms (%.2f, %.2f)\n", total_stats.mean, total_stats.variance, total_stats.sample_variance);
        printf("  Iter:  %.2fns (%.2f, %.2f)\n\n", iter_stats.mean, iter_stats.variance, iter_stats.sample_variance);
    }

private:
    std::chrono::time_point<std::chrono::system_clock> start_time;
    double total_sum_ms = 0;
    double iter_sum_ns = 0;
    double count = 0;

    RunningMean total;
    RunningMean iter;
};