package com.corebanking.accounts;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/** Redis read-through cache for balance reads: key bal:{accountId}, evicted on every write. */
@Component
class BalanceCache {

    private final StringRedisTemplate redis;
    private final ObjectMapper mapper;
    private final boolean enabled;
    private final Duration ttl;

    BalanceCache(StringRedisTemplate redis, ObjectMapper mapper,
                 @Value("${ledger.cache.enabled:true}") boolean enabled,
                 @Value("${ledger.cache.ttl:60s}") Duration ttl) {
        this.redis = redis;
        this.mapper = mapper;
        this.enabled = enabled;
        this.ttl = ttl;
    }

    Optional<AccountView> get(String id) {
        if (!enabled) {
            return Optional.empty();
        }
        String json = redis.opsForValue().get(key(id));
        if (json == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(mapper.readValue(json, AccountView.class));
        } catch (JsonProcessingException e) {
            return Optional.empty();
        }
    }

    void put(AccountView view) {
        if (!enabled) {
            return;
        }
        try {
            redis.opsForValue().set(key(view.id()), mapper.writeValueAsString(view), ttl);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    void evict(String id) {
        if (enabled) {
            redis.delete(key(id));
        }
    }

    private static String key(String id) {
        return "bal:" + id;
    }
}
