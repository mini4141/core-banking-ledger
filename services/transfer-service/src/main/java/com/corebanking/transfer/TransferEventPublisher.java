package com.corebanking.transfer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@Component
class TransferEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(TransferEventPublisher.class);

    private final KafkaTemplate<String, String> kafka;
    private final ObjectMapper mapper;
    private final String topic;

    TransferEventPublisher(KafkaTemplate<String, String> kafka, ObjectMapper mapper,
                           @Value("${ledger.topic:banking.transfers}") String topic) {
        this.kafka = kafka;
        this.mapper = mapper;
        this.topic = topic;
    }

    /** Key = transfer id, so all events of one transfer stay ordered on one partition. */
    void publish(TransferCompletedEvent event) {
        try {
            kafka.send(topic, event.transferId(), mapper.writeValueAsString(event))
                    .whenComplete((result, error) -> {
                        if (error != null) {
                            log.error("failed to publish TransferCompleted transferId={}", event.transferId(), error);
                        } else {
                            log.info("published TransferCompleted transferId={} partition={} offset={}",
                                    event.transferId(), result.getRecordMetadata().partition(),
                                    result.getRecordMetadata().offset());
                        }
                    });
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }
}
