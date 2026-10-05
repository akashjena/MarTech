# # Telia Martech Technical Assessment

## Overview

This solution implements a reusable audience segmentation framework for marketing activation.

## Architecture

```text
Source Files

↓

Staging Layer

↓

Customer Metrics Layer

↓

Customer Segmentation Layer

↓

Activation Ready Audience
```

## Source Datasets

- customers.csv
- product_events.csv
- campaign_interactions.csv
- consent_registry.csv
- consent_purpose_code.csv

## Staging Models

- stg_customers
- stg_product_events
- stg_campaign_interactions
- stg_consent_registry
- stg_consent_purpose_code

## Customer Metrics

- total_logins_30d
- support_tickets_90d
- days_since_last_activity
- open_rate_60d
- active_days_14d

## Audience Segments

- high_value_engaged
- at_risk_dormant
- upgrade_candidate
- winback_target
- engagement_declining

## Data Quality Tests

- customer_id not null
- customer_id unique
- valid subscription plan
- valid subscription status
- business rule validation

## Assumptions

Rolling windows are calculated using the latest available event date within the dataset because the supplied data is historical and static.

## Business Value

The solution provides a governed and reusable segmentation framework that supports personalization, retention, upsell and winback campaigns.

Git and GitHub practice branch and pull request practice





