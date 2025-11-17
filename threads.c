#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <string.h>
#include <sys/time.h>
#include <stdint.h>
#include <signal.h>
#include <atomic>

#define MAX_THREADS 32
#define MAX_QUEUE_SIZE 1000
#define DEFAULT_NUM_THREADS 8
#define DEFAULT_NUM_TASKS 10000
#define DEFAULT_TEST_DURATION 10  // seconds

// Atomic flag for graceful shutdown
volatile sig_atomic_t shutdown_requested = 0;

// Thread-safe queue structure
typedef struct {
    void** items;
    int head;
    int tail;
    int count;
    int capacity;
    pthread_mutex_t lock;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
} ThreadSafeQueue;

// Task structure
typedef struct {
    int task_id;
    int priority;
    struct timeval start_time;
    struct timeval end_time;
} Task;

// Worker thread statistics
typedef struct {
    int thread_id;
    long tasks_completed;
    long tasks_failed;
    double total_processing_time;
    double max_processing_time;
    double min_processing_time;
} WorkerStats;

// Shared application state
typedef struct {
    ThreadSafeQueue* task_queue;
    WorkerStats* worker_stats;
    pthread_t* worker_threads;
    pthread_mutex_t stats_lock;
    pthread_mutex_t shutdown_lock;
    pthread_cond_t shutdown_cond;
    int active_workers;
    int total_tasks_completed;
    int total_tasks_failed;
    struct timeval start_time;
    struct timeval end_time;
} AppContext;

// Function prototypes
ThreadSafeQueue* queue_create(int capacity);
void queue_destroy(ThreadSafeQueue* queue);
int queue_enqueue(ThreadSafeQueue* queue, void* item);
void* queue_dequeue(ThreadSafeQueue* queue);
int queue_is_empty(ThreadSafeQueue* queue);
int queue_is_full(ThreadSafeQueue* queue);
void queue_clear(ThreadSafeQueue* queue);

void* worker_thread(void* arg);
void* task_generator_thread(void* arg);
void* monitor_thread(void* arg);
void* stress_test_thread(void* arg);

void initialize_app_context(AppContext* ctx, int num_threads);
void cleanup_app_context(AppContext* ctx);
void print_statistics(AppContext* ctx);
void signal_handler(int sig);

double get_time_diff(struct timeval* start, struct timeval* end);
void simulate_work(int task_id, int priority);
void generate_test_tasks(AppContext* ctx, int num_tasks);
void run_performance_test(AppContext* ctx, int test_duration);

// Create a thread-safe queue
ThreadSafeQueue* queue_create(int capacity) {
    ThreadSafeQueue* queue = (ThreadSafeQueue*)malloc(sizeof(ThreadSafeQueue));
    if (!queue) {
        perror("Failed to allocate queue");
        return NULL;
    }

    queue->items = (void**)malloc(capacity * sizeof(void*));
    if (!queue->items) {
        free(queue);
        perror("Failed to allocate queue items");
        return NULL;
    }

    queue->capacity = capacity;
    queue->head = 0;
    queue->tail = 0;
    queue->count = 0;

    if (pthread_mutex_init(&queue->lock, NULL) != 0) {
        free(queue->items);
        free(queue);
        perror("Failed to initialize mutex");
        return NULL;
    }

    if (pthread_cond_init(&queue->not_empty, NULL) != 0) {
        pthread_mutex_destroy(&queue->lock);
        free(queue->items);
        free(queue);
        perror("Failed to initialize not_empty condition");
        return NULL;
    }

    if (pthread_cond_init(&queue->not_full, NULL) != 0) {
        pthread_cond_destroy(&queue->not_empty);
        pthread_mutex_destroy(&queue->lock);
        free(queue->items);
        free(queue);
        perror("Failed to initialize not_full condition");
        return NULL;
    }

    return queue;
}

// Destroy the queue and free resources
void queue_destroy(ThreadSafeQueue* queue) {
    if (queue) {
        pthread_mutex_lock(&queue->lock);
        free(queue->items);
        pthread_mutex_unlock(&queue->lock);
        
        pthread_cond_destroy(&queue->not_empty);
        pthread_cond_destroy(&queue->not_full);
        pthread_mutex_destroy(&queue->lock);
        free(queue);
    }
}

// Enqueue an item (blocking if queue is full)
int queue_enqueue(ThreadSafeQueue* queue, void* item) {
    pthread_mutex_lock(&queue->lock);
    
    // Wait until queue is not full
    while (queue_is_full(queue)) {
        pthread_cond_wait(&queue->not_full, &queue->lock);
        if (shutdown_requested) {
            pthread_mutex_unlock(&queue->lock);
            return -1;
        }
    }

    queue->items[queue->tail] = item;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->count++;

    // Signal that queue is not empty
    pthread_cond_signal(&queue->not_empty);
    pthread_mutex_unlock(&queue->lock);
    
    return 0;
}

// Dequeue an item (blocking if queue is empty)
void* queue_dequeue(ThreadSafeQueue* queue) {
    void* item = NULL;
    
    pthread_mutex_lock(&queue->lock);
    
    // Wait until queue is not empty
    while (queue_is_empty(queue)) {
        if (shutdown_requested) {
            pthread_mutex_unlock(&queue->lock);
            return NULL;
        }
        pthread_cond_wait(&queue->not_empty, &queue->lock);
    }

    item = queue->items[queue->head];
    queue->items[queue->head] = NULL;  // Clear the reference
    queue->head = (queue->head + 1) % queue->capacity;
    queue->count--;

    // Signal that queue is not full
    pthread_cond_signal(&queue->not_full);
    pthread_mutex_unlock(&queue->lock);
    
    return item;
}

// Check if queue is empty
int queue_is_empty(ThreadSafeQueue* queue) {
    return queue->count == 0;
}

// Check if queue is full
int queue_is_full(ThreadSafeQueue* queue) {
    return queue->count == queue->capacity;
}

// Clear the queue (not thread-safe, should be called with lock held)
void queue_clear(ThreadSafeQueue* queue) {
    while (!queue_is_empty(queue)) {
        free(queue_dequeue(queue));
    }
}

// Get time difference in seconds
double get_time_diff(struct timeval* start, struct timeval* end) {
    return (end->tv_sec - start->tv_sec) + 
           (end->tv_usec - start->tv_usec) / 1000000.0;
}

// Simulate work with variable processing time based on priority
void simulate_work(int task_id, int priority) {
    // Higher priority = less work time
    double work_time = (10 - priority) * 0.001;  // 0.001 to 0.009 seconds
    
    // Add some random variation
    work_time += (rand() % 1000) / 1000000.0;
    
    // Simulate CPU-bound work
    volatile double result = 0.0;
    int iterations = (int)(work_time * 1000000);
    for (int i = 0; i < iterations; i++) {
        result += sin(i * 0.1) * cos(i * 0.2);
    }
    
    // Occasionally simulate I/O wait
    if (task_id % 100 == 0) {
        usleep(1000);  // 1ms sleep
    }
}

// Worker thread function
void* worker_thread(void* arg) {
    AppContext* ctx = (AppContext*)arg;
    int thread_id = -1;
    
    // Find thread ID
    pthread_mutex_lock(&ctx->stats_lock);
    for (int i = 0; i < MAX_THREADS; i++) {
        if (pthread_equal(ctx->worker_threads[i], pthread_self())) {
            thread_id = i;
            break;
        }
    }
    pthread_mutex_unlock(&ctx->stats_lock);
    
    if (thread_id == -1) {
        fprintf(stderr, "Worker thread could not find its ID\n");
        return NULL;
    }
    
    printf("Worker thread %d started\n", thread_id);
    
    while (!shutdown_requested) {
        Task* task = (Task*)queue_dequeue(ctx->task_queue);
        if (!task) {
            if (shutdown_requested) break;
            continue;
        }
        
        struct timeval task_start, task_end;
        gettimeofday(&task_start, NULL);
        
        // Simulate doing work
        simulate_work(task->task_id, task->priority);
        
        gettimeofday(&task_end, NULL);
        
        double processing_time = get_time_diff(&task_start, &task_end);
        
        // Update statistics
        pthread_mutex_lock(&ctx->stats_lock);
        
        WorkerStats* stats = &ctx->worker_stats[thread_id];
        stats->tasks_completed++;
        stats->total_processing_time += processing_time;
        
        if (processing_time > stats->max_processing_time) {
            stats->max_processing_time = processing_time;
        }
        if (stats->min_processing_time == 0 || processing_time < stats->min_processing_time) {
            stats->min_processing_time = processing_time;
        }
        
        ctx->total_tasks_completed++;
        
        pthread_mutex_unlock(&ctx->stats_lock);
        
        // Free the task
        free(task);
        
        // Occasionally yield to prevent thread starvation
        if (ctx->total_tasks_completed % 1000 == 0) {
            sched_yield();
        }
    }
    
    printf("Worker thread %d shutting down\n", thread_id);
    return NULL;
}

// Task generator thread
void* task_generator_thread(void* arg) {
    AppContext* ctx = (AppContext*)arg;
    int task_id = 0;
    
    printf("Task generator started\n");
    
    while (!shutdown_requested && task_id < DEFAULT_NUM_TASKS) {
        // Create a new task
        Task* task = (Task*)malloc(sizeof(Task));
        if (!task) {
            perror("Failed to allocate task");
            break;
        }
        
        task->task_id = task_id;
        // Random priority between 1 and 10
        task->priority = (rand() % 10) + 1;
        gettimeofday(&task->start_time, NULL);
        
        // Enqueue the task
        if (queue_enqueue(ctx->task_queue, task) == -1) {
            free(task);
            break;
        }
        
        task_id++;
        
        // Throttle task generation to prevent overwhelming the queue
        if (task_id % 100 == 0) {
            usleep(1000);  // 1ms delay every 100 tasks
        }
    }
    
    printf("Task generator completed. Generated %d tasks\n", task_id);
    return NULL;
}

// Monitor thread for real-time statistics
void* monitor_thread(void* arg) {
    AppContext* ctx = (AppContext*)arg;
    int interval = 1;  // seconds
    
    printf("Monitor thread started\n");
    
    while (!shutdown_requested) {
        sleep(interval);
        
        pthread_mutex_lock(&ctx->stats_lock);
        
        long total_completed = 0;
        long total_failed = 0;
        double total_time = 0.0;
        
        for (int i = 0; i < DEFAULT_NUM_THREADS; i++) {
            total_completed += ctx->worker_stats[i].tasks_completed;
            total_failed += ctx->worker_stats[i].tasks_failed;
            total_time += ctx->worker_stats[i].total_processing_time;
        }
        
        struct timeval current_time;
        gettimeofday(&current_time, NULL);
        double elapsed = get_time_diff(&ctx->start_time, &current_time);
        
        if (elapsed > 0) {
            double throughput = total_completed / elapsed;
            double avg_time = total_completed > 0 ? total_time / total_completed : 0.0;
            
            printf("\n=== Monitor Report (Elapsed: %.2f seconds) ===\n", elapsed);
            printf("Total Tasks Completed: %ld\n", total_completed);
            printf("Total Tasks Failed: %ld\n", total_failed);
            printf("Throughput: %.2f tasks/second\n", throughput);
            printf("Average Processing Time: %.6f seconds\n", avg_time);
            printf("Queue Size: %d/%d\n", ctx->task_queue->count, ctx->task_queue->capacity);
            printf("Active Workers: %d\n", ctx->active_workers);
            printf("========================================\n\n");
        }
        
        pthread_mutex_unlock(&ctx->stats_lock);
        
        if (total_completed >= DEFAULT_NUM_TASKS) {
            printf("All tasks completed. Monitor shutting down.\n");
            break;
        }
    }
    
    return NULL;
}

// Stress test thread that creates additional load
void* stress_test_thread(void* arg) {
    AppContext* ctx = (AppContext*)arg;
    int stress_level = 5;  // Number of additional tasks to enqueue rapidly
    
    printf("Stress test thread started\n");
    
    while (!shutdown_requested) {
        sleep(5);  // Run stress test every 5 seconds
        
        printf("=== Starting Stress Test ===\n");
        
        for (int i = 0; i < stress_level * 100; i++) {
            if (shutdown_requested) break;
            
            Task* task = (Task*)malloc(sizeof(Task));
            if (!task) continue;
            
            task->task_id = DEFAULT_NUM_TASKS + i;
            task->priority = 1;  // Lowest priority for stress tasks
            gettimeofday(&task->start_time, NULL);
            
            if (queue_enqueue(ctx->task_queue, task) == -1) {
                free(task);
                break;
            }
        }
        
        printf("=== Stress Test Completed ===\n");
    }
    
    return NULL;
}

// Initialize application context
void initialize_app_context(AppContext* ctx, int num_threads) {
    memset(ctx, 0, sizeof(AppContext));
    
    ctx->task_queue = queue_create(MAX_QUEUE_SIZE);
    if (!ctx->task_queue) {
        exit(EXIT_FAILURE);
    }
    
    ctx->worker_stats = (WorkerStats*)calloc(num_threads, sizeof(WorkerStats));
    if (!ctx->worker_stats) {
        perror("Failed to allocate worker stats");
        exit(EXIT_FAILURE);
    }
    
    ctx->worker_threads = (pthread_t*)calloc(num_threads, sizeof(pthread_t));
    if (!ctx->worker_threads) {
        perror("Failed to allocate worker threads");
        exit(EXIT_FAILURE);
    }
    
    if (pthread_mutex_init(&ctx->stats_lock, NULL) != 0) {
        perror("Failed to initialize stats mutex");
        exit(EXIT_FAILURE);
    }
    
    if (pthread_mutex_init(&ctx->shutdown_lock, NULL) != 0) {
        perror("Failed to initialize shutdown mutex");
        exit(EXIT_FAILURE);
    }
    
    if (pthread_cond_init(&ctx->shutdown_cond, NULL) != 0) {
        perror("Failed to initialize shutdown condition");
        exit(EXIT_FAILURE);
    }
    
    ctx->active_workers = num_threads;
    gettimeofday(&ctx->start_time, NULL);
    
    // Initialize worker statistics
    for (int i = 0; i < num_threads; i++) {
        ctx->worker_stats[i].thread_id = i;
        ctx->worker_stats[i].min_processing_time = 1000.0;  // High initial value
    }
}

// Cleanup application context
void cleanup_app_context(AppContext* ctx) {
    if (ctx->task_queue) {
        queue_destroy(ctx->task_queue);
    }
    
    free(ctx->worker_stats);
    free(ctx->worker_threads);
    
    pthread_mutex_destroy(&ctx->stats_lock);
    pthread_mutex_destroy(&ctx->shutdown_lock);
    pthread_cond_destroy(&ctx->shutdown_cond);
}

// Print final statistics
void print_statistics(AppContext* ctx) {
    gettimeofday(&ctx->end_time, NULL);
    double total_time = get_time_diff(&ctx->start_time, &ctx->end_time);
    
    printf("\n");
    printf("========================================\n");
    printf("           FINAL STATISTICS\n");
    printf("========================================\n");
    printf("Total Execution Time: %.4f seconds\n", total_time);
    printf("Total Tasks Completed: %d\n", ctx->total_tasks_completed);
    printf("Total Tasks Failed: %d\n", ctx->total_tasks_failed);
    printf("Overall Throughput: %.2f tasks/second\n", 
           total_time > 0 ? ctx->total_tasks_completed / total_time : 0);
    
    printf("\nPer-Thread Statistics:\n");
    printf("========================================\n");
    printf("%-8s %-15s %-15s %-15s %-15s %-15s\n", 
           "Thread", "Tasks", "Failed", "Total Time", "Avg Time", "Max Time");
    printf("========================================\n");
    
    for (int i = 0; i < DEFAULT_NUM_THREADS; i++) {
        WorkerStats* stats = &ctx->worker_stats[i];
        double avg_time = stats->tasks_completed > 0 ? 
                         stats->total_processing_time / stats->tasks_completed : 0.0;
        
        printf("%-8d %-15ld %-15ld %-15.6f %-15.6f %-15.6f\n",
               stats->thread_id,
               stats->tasks_completed,
               stats->tasks_failed,
               stats->total_processing_time,
               avg_time,
               stats->max_processing_time);
    }
    
    printf("========================================\n");
}

// Signal handler for graceful shutdown
void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        printf("\nShutdown signal received. Cleaning up...\n");
        shutdown_requested = 1;
    }
}

// Main function
int main(int argc, char* argv[]) {
    AppContext ctx;
    pthread_t generator_thread, monitor_thread_id, stress_thread;
    int num_threads = DEFAULT_NUM_THREADS;
    int run_duration = DEFAULT_TEST_DURATION;
    
    // Setup signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    // Seed random number generator
    srand(time(NULL));
    
    printf("========================================\n");
    printf("       THREADING TEST APPLICATION\n");
    printf("========================================\n");
    printf("System Configuration:\n");
    printf("- Max Threads: %d\n", MAX_THREADS);
    printf("- Queue Capacity: %d\n", MAX_QUEUE_SIZE);
    printf("- Default Tasks: %d\n", DEFAULT_NUM_TASKS);
    printf("- Test Duration: %d seconds\n", DEFAULT_TEST_DURATION);
    printf("========================================\n\n");
    
    // Initialize application context
    initialize_app_context(&ctx, num_threads);
    
    // Create worker threads
    printf("Creating %d worker threads...\n", num_threads);
    for (int i = 0; i < num_threads; i++) {
        if (pthread_create(&ctx.worker_threads[i], NULL, worker_thread, &ctx) != 0) {
            perror("Failed to create worker thread");
            exit(EXIT_FAILURE);
        }
    }
    
    // Create task generator thread
    printf("Creating task generator thread...\n");
    if (pthread_create(&generator_thread, NULL, task_generator_thread, &ctx) != 0) {
        perror("Failed to create task generator thread");
        exit(EXIT_FAILURE);
    }
    
    // Create monitor thread
    printf("Creating monitor thread...\n");
    if (pthread_create(&monitor_thread_id, NULL, monitor_thread, &ctx) != 0) {
        perror("Failed to create monitor thread");
        exit(EXIT_FAILURE);
    }
    
    // Create stress test thread
    printf("Creating stress test thread...\n");
    if (pthread_create(&stress_thread, NULL, stress_test_thread, &ctx) != 0) {
        perror("Failed to create stress test thread");
        exit(EXIT_FAILURE);
    }
    
    printf("\nApplication running. Press Ctrl+C to stop gracefully...\n");
    
    // Main thread waits for completion or shutdown signal
    while (!shutdown_requested) {
        sleep(1);
        
        // Check if all tasks are completed
        pthread_mutex_lock(&ctx.stats_lock);
        if (ctx.total_tasks_completed >= DEFAULT_NUM_TASKS && 
            queue_is_empty(ctx.task_queue)) {
            pthread_mutex_unlock(&ctx.stats_lock);
            printf("\nAll tasks completed. Initiating shutdown...\n");
            shutdown_requested = 1;
            break;
        }
        pthread_mutex_unlock(&ctx.stats_lock);
        
        // Check if we've reached the time limit
        struct timeval current_time;
        gettimeofday(&current_time, NULL);
        double elapsed = get_time_diff(&ctx.start_time, &current_time);
        if (elapsed >= run_duration) {
            printf("\nTest duration reached. Initiating shutdown...\n");
            shutdown_requested = 1;
            break;
        }
    }
    
    // Wait for all threads to complete
    printf("\nWaiting for threads to shutdown...\n");
    
    // Join worker threads
    for (int i = 0; i < num_threads; i++) {
        pthread_join(ctx.worker_threads[i], NULL);
    }
    
    // Join other threads
    pthread_join(generator_thread, NULL);
    pthread_join(monitor_thread_id, NULL);
    pthread_join(stress_thread, NULL);
    
    // Print final statistics
    print_statistics(&ctx);
    
    // Cleanup
    cleanup_app_context(&ctx);
    
    printf("\n========================================\n");
    printf("        THREADING TEST COMPLETED\n");
    printf("========================================\n");
    
    return 0;
}
