/* ===========================================================
   STAGING LAYER
   =========================================================== */

/* Customer */

CREATE OR REPLACE VIEW stg_customers AS

SELECT

    customer_id,

    LOWER(email) AS email,

    phone_number,

    signup_date,

    LOWER(subscription_plan) AS subscription_plan,

    LOWER(subscription_status) AS subscription_status,

    status_change_date

FROM customers;


/* Product Events */

CREATE OR REPLACE VIEW stg_product_events AS

SELECT

    event_id,

    customer_id,

    LOWER(event_type) AS event_type,

    event_ts,

    event_properties

FROM product_events;


/* Campaign Interactions */

CREATE OR REPLACE VIEW stg_campaign_interactions AS

SELECT

    interaction_id,

    customer_id,

    campaign_id,

    LOWER(channel) AS channel,

    LOWER(interaction_type) AS interaction_type,

    interaction_ts

FROM campaign_interactions;


/* Consent Registry */

CREATE OR REPLACE VIEW stg_consent_registry AS

SELECT

    CONCAT(
        'CUST_',
        LPAD(customer_id,6,'0')
    ) AS customer_id,

    purpose_code,

    consent_ts

FROM consent_registry;


/* Consent Purpose */

CREATE OR REPLACE VIEW stg_consent_purpose_code AS

SELECT *

FROM consent_purpose_code;


/* ===========================================================
   CUSTOMER ENGAGEMENT METRICS
   =========================================================== */

%sql
CREATE OR REPLACE VIEW customer_engagement_metrics AS

WITH latest_event_date AS (
    SELECT MAX(event_ts) AS max_event_ts
    FROM product_events
),

product_metrics AS (

    SELECT
        customer_id,

        SUM(
            CASE
                WHEN event_type = 'login'
                 AND CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),
                        14
                     )
                THEN 1
                ELSE 0
            END
        ) AS total_logins_14d,

        SUM(
            CASE
                WHEN event_type = 'login'
                 AND CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),
                        30
                     )
                THEN 1
                ELSE 0
            END
        ) AS total_logins_30d,

        COUNT(DISTINCT
            CASE
                WHEN CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),
                        14
                     )
                THEN CAST(event_ts AS DATE)
            END
        ) AS active_days_last14,

        COUNT(DISTINCT
            CASE
                WHEN CAST(event_ts AS DATE)
                     BETWEEN DATE_SUB(CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),28)
                         AND DATE_SUB(CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),15)
                THEN CAST(event_ts AS DATE)
            END
        ) AS active_days_prev14,

        COUNT(DISTINCT
            CASE
                WHEN CAST(event_ts AS DATE)
                     BETWEEN DATE_SUB(CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),60)
                         AND DATE_SUB(CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),30)
                THEN CAST(event_ts AS DATE)
            END
        ) AS active_days_30_60d,

        SUM(
            CASE
                WHEN event_type = 'support_ticket'
                 AND CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST((SELECT max_event_ts FROM latest_event_date) AS DATE),
                        90
                     )
                THEN 1
                ELSE 0
            END
        ) AS support_tickets_90d

    FROM product_events
    GROUP BY customer_id
),

campaign_metrics AS (

    SELECT

        customer_id,

        SUM(
            CASE
                WHEN interaction_type = 'delivered'
                THEN 1
                ELSE 0
            END
        ) AS delivered_cnt,

        SUM(
            CASE
                WHEN interaction_type = 'opened'
                THEN 1
                ELSE 0
            END
        ) AS opened_cnt

    FROM campaign_interactions

    GROUP BY customer_id
)

SELECT

    p.customer_id,
    p.total_logins_14d as total_logins_14d,
    p.total_logins_30d as total_logins_30d,
    p.active_days_last14 as total_active_days_14d,
    p.active_days_prev14 as active_days_prev14,
    p.active_days_30_60d as active_days_30_60d,
    p.support_tickets_90d as support_tickets_90d,

    CASE
        WHEN COALESCE(c.delivered_cnt,0) = 0
        THEN 0
        ELSE ROUND(
            c.opened_cnt * 1.0 / c.delivered_cnt,
            2
        )
    END AS campaign_open_rate

FROM product_metrics p

LEFT JOIN campaign_metrics c
ON p.customer_id = c.customer_id;


/* ===========================================================
   CUSTOMER SEGMENTS
   =========================================================== */

%sql
CREATE OR REPLACE VIEW customer_segments AS

SELECT

    c.customer_id,

    CASE

        WHEN c.subscription_plan = 'premium'
             AND m.total_logins_14d >= 5
             AND m.campaign_open_rate > 0.30
        THEN 'high_value_engaged'

        WHEN m.total_logins_14d = 0
             AND m.active_days_30_60d > 0
        THEN 'at_risk_dormant'

        WHEN c.subscription_plan IN ('basic','standard')
             AND m.total_logins_30d >= 10
             AND m.support_tickets_90d = 0
        THEN 'upgrade_candidate'

        WHEN c.subscription_status = 'churned'
             AND m.campaign_open_rate > 0.20
        THEN 'winback_target'

        WHEN m.active_days_prev14 > 0
             AND m.total_active_days_14d < (m.active_days_prev14 * 0.5)
        THEN 'engagement_declining'

        ELSE 'other'

    END AS segment_name

FROM customers c

LEFT JOIN customer_engagement_metrics m
ON c.customer_id = m.customer_id;


/* ===========================================================
   DATA QUALITY TESTS
   =========================================================== */

/* Test 1   customer_id should not be null*/

SELECT *
FROM stg_customers
WHERE customer_id IS NULL;


/* Test 2  Customer_id should be unique*/

SELECT
    customer_id,
    COUNT(*) cnt
FROM stg_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;


/* Test 3 Valid Subscription Plan */

SELECT *
FROM stg_customers
WHERE subscription_plan NOT IN
(
    'basic',
    'standard',
    'premium'
);


/* Test 4 Valid Subscription Status */

SELECT *
FROM stg_customers
WHERE subscription_status NOT IN
(
    'active',
    'paused',
    'churned'
);


/* Test 5 - Custom Business Test */

SELECT *

FROM customer_segments s

JOIN stg_customers c

ON s.customer_id = c.customer_id

WHERE s.segment_name = 'high_value_engaged'
AND c.subscription_plan <> 'premium';
