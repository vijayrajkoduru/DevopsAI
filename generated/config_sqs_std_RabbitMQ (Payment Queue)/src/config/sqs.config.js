"use strict";

const { SQSClient } = require("@aws-sdk/client-sqs");

/**
 * SQS Configuration for RabbitMQ (Payment Queue)
 * Connected to: Payment Service (ECS Fargate)
 */
const sqsConfig = {
  region: process.env.AWS_REGION || "us-east-1",
  queueUrl: process.env.SQS_QUEUE_URL,
  dlqUrl: process.env.SQS_DLQ_URL,
  queueName: process.env.SQS_QUEUE_NAME || "rabbitmq-payment-queue",
  visibilityTimeout: parseInt(process.env.SQS_VISIBILITY_TIMEOUT || "30", 10),
  waitTimeSeconds: parseInt(process.env.SQS_WAIT_TIME_SECONDS || "10", 10),
  maxMessages: parseInt(process.env.SQS_MAX_MESSAGES || "10", 10),
  retryAttempts: parseInt(process.env.SQS_RETRY_ATTEMPTS || "3", 10),
  pollingInterval: parseInt(process.env.SQS_POLLING_INTERVAL || "5000", 10),
};

/**
 * Validate required SQS configuration
 */
const validateSqsConfig = () => {
  const requiredFields = ["queueUrl"];
  const missingFields = requiredFields.filter((field) => !sqsConfig[field]);

  if (missingFields.length > 0) {
    throw new Error(
      `Missing required SQS configuration fields: ${missingFields.join(", ")}`
    );
  }

  return true;
};

/**
 * Create and configure SQS client
 */
const createSqsClient = () => {
  const clientConfig = {
    region: sqsConfig.region,
  };

  if (
    process.env.AWS_ACCESS_KEY_ID &&
    process.env.AWS_SECRET_ACCESS_KEY
  ) {
    const { fromEnv } = require("@aws-sdk/credential-providers");
    clientConfig.credentials = fromEnv();
  }

  return new SQSClient(clientConfig);
};

module.exports = {
  sqsConfig,
  validateSqsConfig,
  createSqsClient,
};