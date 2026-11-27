package com.corebanking.transfer;

import java.time.Duration;
import java.util.Optional;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/** Redis idempotency keys: SET NX with a 24 h TTL, later overwritten with the result JSON. */
@Component
class IdempotencyStore {

    static final String IN_PROGRESS = "IN_PROGRESS";
    private static final Duration TTL = Duration.ofHours(24);

    private final StringRedisTemplate redis;

    IdempotencyStore(StringRedisTemplate redis) {
        this.redis = redis;
    }

    boolean tryAcquire(String key) {
        return Boolean.TRUE.equals(redis.opsForValue().setIfAbsent(redisKey(key), IN_PROGRESS, TTL));
    }

    Optional<String> find(String key) {
        return Optional.ofNullable(redis.opsForValue().get(redisKey(key)));
    }

    void complete(String key, String resultJson) {
        redis.opsForValue().set(redisKey(key), resultJson, TTL);
    }

    void release(String key) {
        redis.delete(redisKey(key));
    }

    private static String redisKey(String key) {
        return "idem:" + key;
    }
}
