package com.corebanking.audit

import jakarta.annotation.PostConstruct
import java.math.BigDecimal
import java.net.URI
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.stereotype.Repository
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.dynamodb.DynamoDbClient
import software.amazon.awssdk.services.dynamodb.model.AttributeDefinition
import software.amazon.awssdk.services.dynamodb.model.AttributeValue
import software.amazon.awssdk.services.dynamodb.model.BillingMode
import software.amazon.awssdk.services.dynamodb.model.CreateTableRequest
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement
import software.amazon.awssdk.services.dynamodb.model.KeyType
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest
import software.amazon.awssdk.services.dynamodb.model.QueryRequest
import software.amazon.awssdk.services.dynamodb.model.ResourceInUseException
import software.amazon.awssdk.services.dynamodb.model.ScalarAttributeType

@Configuration
class DynamoConfig {
    @Bean
    fun dynamoDbClient(
        @Value("\${audit.dynamodb.endpoint:}") endpoint: String,
        @Value("\${audit.dynamodb.region:ap-southeast-2}") region: String,
    ): DynamoDbClient {
        val builder = DynamoDbClient.builder()
            .region(Region.of(region))
            .httpClient(UrlConnectionHttpClient.create())
        if (endpoint.isNotBlank()) builder.endpointOverride(URI.create(endpoint))
        return builder.build()
    }
}

@Repository
class AuditRepository(
    private val dynamo: DynamoDbClient,
    @Value("\${audit.dynamodb.table:audit_events}") private val table: String,
    @Value("\${audit.dynamodb.create-table:false}") private val createTable: Boolean,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @PostConstruct
    fun ensureTable() {
        if (!createTable) return
        try {
            dynamo.createTable(
                CreateTableRequest.builder()
                    .tableName(table)
                    .billingMode(BillingMode.PAY_PER_REQUEST)
                    .attributeDefinitions(
                        AttributeDefinition.builder().attributeName("PK").attributeType(ScalarAttributeType.S).build(),
                        AttributeDefinition.builder().attributeName("SK").attributeType(ScalarAttributeType.S).build(),
                    )
                    .keySchema(
                        KeySchemaElement.builder().attributeName("PK").keyType(KeyType.HASH).build(),
                        KeySchemaElement.builder().attributeName("SK").keyType(KeyType.RANGE).build(),
                    )
                    .build(),
            )
            log.info("created DynamoDB table {}", table)
        } catch (_: ResourceInUseException) {
            log.info("DynamoDB table {} already exists", table)
        }
    }

    /** PutItem on a deterministic key, so re-delivered events overwrite themselves. */
    fun save(item: AuditItem) {
        dynamo.putItem(
            PutItemRequest.builder().tableName(table).item(
                mapOf(
                    "PK" to s(item.pk),
                    "SK" to s(item.sk),
                    "type" to s(item.type),
                    "amount" to AttributeValue.builder().n(item.amount.toPlainString()).build(),
                    "counterparty" to s(item.counterparty),
                    "transferId" to s(item.transferId),
                ),
            ).build(),
        )
    }

    /** Newest first: one Query on the partition key, sort key descending. */
    fun findByAccount(accountId: String, limit: Int = 50): List<AuditItem> =
        dynamo.query(
            QueryRequest.builder()
                .tableName(table)
                .keyConditionExpression("PK = :pk")
                .expressionAttributeValues(mapOf(":pk" to s("ACCOUNT#$accountId")))
                .scanIndexForward(false)
                .limit(limit)
                .build(),
        ).items().map {
            AuditItem(
                pk = it["PK"]!!.s(),
                sk = it["SK"]!!.s(),
                type = it["type"]!!.s(),
                amount = BigDecimal(it["amount"]!!.n()),
                counterparty = it["counterparty"]!!.s(),
                transferId = it["transferId"]!!.s(),
            )
        }

    private fun s(value: String) = AttributeValue.builder().s(value).build()
}
