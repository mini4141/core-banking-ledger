package com.corebanking.audit

import com.fasterxml.jackson.databind.ObjectMapper
import org.slf4j.LoggerFactory
import org.springframework.kafka.annotation.KafkaListener
import org.springframework.kafka.support.Acknowledgment
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RestController
import org.springframework.stereotype.Component

@Component
class TransferEventListener(
    private val mapper: ObjectMapper,
    private val repository: AuditRepository,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    /** Manual ack: the offset is committed only after both items are in DynamoDB. */
    @KafkaListener(topics = ["\${audit.topic:banking.transfers}"], groupId = "audit-service")
    fun onTransfer(payload: String, ack: Acknowledgment) {
        val event = mapper.readValue(payload, TransferCompleted::class.java)
        AuditMapper.toItems(event).forEach(repository::save)
        ack.acknowledge()
        log.info("audit recorded transferId={} from={} to={}", event.transferId, event.fromAccountId, event.toAccountId)
    }
}

@RestController
class AuditController(private val repository: AuditRepository) {
    @GetMapping("/audit/accounts/{id}")
    fun byAccount(@PathVariable id: String): List<AuditItem> = repository.findByAccount(id)
}

@org.springframework.context.annotation.Configuration
class TopicConfig {
    /** Declared here as well so the topic always exists with 3 partitions before the consumer subscribes. */
    @org.springframework.context.annotation.Bean
    fun transfersTopic(): org.apache.kafka.clients.admin.NewTopic =
        org.springframework.kafka.config.TopicBuilder.name("banking.transfers").partitions(3).replicas(1).build()
}
