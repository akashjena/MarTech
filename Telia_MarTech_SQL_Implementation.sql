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

CREATE OR REPLACE VIEW customer_engagement_metrics AS

WITH latest_event_date AS (

    SELECT
        MAX(event_ts) AS max_event_ts
    FROM stg_product_events

),

latest_campaign_date AS (

    SELECT
        MAX(interaction_ts) AS max_interaction_ts
    FROM stg_campaign_interactions

),

product_metrics AS (

    SELECT

        customer_id,

        COUNT(

            CASE

                WHEN event_type = 'login'
                 AND CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST(
                            (SELECT max_event_ts
                             FROM latest_event_date)
                        AS DATE),
                        30
                     )

                THEN 1

            END

        ) AS total_logins_30d,

        COUNT(

            CASE

                WHEN event_type = 'support_ticket'
                 AND CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST(
                            (SELECT max_event_ts
                             FROM latest_event_date)
                        AS DATE),
                        90
                     )

                THEN 1

            END

        ) AS support_tickets_90d,

        MAX(event_ts) AS last_activity_ts,

        COUNT(

            DISTINCT

            CASE

                WHEN CAST(event_ts AS DATE) >= DATE_SUB(
                        CAST(
                            (SELECT max_event_ts
                             FROM latest_event_date)
                        AS DATE),
                        14
                     )

                THEN CAST(event_ts AS DATE)

            END

        ) AS active_days

    FROM stg_product_events

    GROUP BY customer_id

),

campaign_metrics AS (

    SELECT

        customer_id,

        COUNT(

            CASE

                WHEN interaction_type = 'opened'
                 AND CAST(interaction_ts AS DATE) >= DATE_SUB(
                        CAST(
                            (SELECT max_interaction_ts
                             FROM latest_campaign_date)
                        AS DATE),
                        60
                     )

                THEN 1

            END

        ) AS opened_cnt,

        COUNT(

            CASE

                WHEN interaction_type = 'delivered'
                 AND CAST(interaction_ts AS DATE) >= DATE_SUB(
                        CAST(
                            (SELECT max_interaction_ts
                             FROM latest_campaign_date)
                        AS DATE),
                        60
                     )

                THEN 1

            END

        ) AS delivered_cnt

    FROM stg_campaign_interactions

    GROUP BY customer_id

)

SELECT

    c.customer_id,

    COALESCE(p.total_logins_30d,0) AS total_logins_30d,

    COALESCE(p.support_tickets_90d,0) AS support_tickets_90d,

    DATEDIFF(

        CAST(
            (SELECT max_event_ts
             FROM latest_event_date)
        AS DATE),

        CAST(p.last_activity_ts AS DATE)

    ) AS days_since_last_activity,

    COALESCE(p.active_days,0) AS active_days,

    CASE

        WHEN COALESCE(cm.delivered_cnt,0) = 0
        THEN 0

        ELSE ROUND(
            cm.opened_cnt * 1.0 / cm.delivered_cnt,
            2
        )

    END AS Campaign_open_rate

FROM stg_customers c

LEFT JOIN product_metrics p
    ON c.customer_id = p.customer_id

LEFT JOIN campaign_metrics cm
    ON c.customer_id = cm.customer_id;


/* ===========================================================
   CUSTOMER SEGMENTS
   =========================================================== */

CREATE OR REPLACE VIEW customer_segments AS

SELECT

    c.customer_id,

    CASE

        WHEN
            c.subscription_plan = 'premium'
            AND m.active_days >= 5
            AND m.Campaign_open_rate > 0.30

        THEN 'high_value_engaged'

        WHEN
            c.subscription_plan IN ('basic','standard')
            AND m.total_logins_30d >= 10
            AND m.support_tickets_90d = 0

        THEN 'upgrade_candidate'

        WHEN
            m.active_days = 0

        THEN 'at_risk_dormant'

        WHEN
            c.subscription_status = 'churned'
            AND m.Campaign_open_rate > 0.20

        THEN 'winback_target'

        ELSE 'engagement_declining'

    END AS segment_name

FROM stg_customers c

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
