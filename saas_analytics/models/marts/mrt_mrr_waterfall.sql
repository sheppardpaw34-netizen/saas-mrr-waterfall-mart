/*
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
MODEL NAME:                             mrt_mee_waterfall
DATA LAYER:                             Marts (Financial Analysis)
BUSINESS DOAMIN:                        Subscription Revenue And Executive Reporting

DESCRIPTION:                            Reconciles Monthly Recurring Revenue (MRR) movements
                                        (New,Expansion,Contraction,Churn) at the whole-company monthly snapshot grain.

GRANULARITY:                            One record per calendar month ('month_end_date')
PRIMARY KEY:                            ('month_end_date')
DEPENDENCIES:                           ref('fct_subscription')
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
*/

-- -----------------------------------------------------------------------------------------------------------------------
-- CTE 1: Import raw subscription event and apply calendar spine normalization.
-- -----------------------------------------------------------------------------------------------------------------------
WITH monthly_spine AS (
    SELECT CAST ('2026-01-31 23:59:59 UTC' AS TIMESTAMP) AS month_end_date UNION ALL
    SELECT CAST ('2026-02-28 23:59:59 UTC' AS TIMESTAMP) AS month_end_date UNION ALL
    SELECT CAST ('2026-03-31 23:59:59 UTC' AS TIMESTAMP) AS month_end_date
    ),
-- ----------------------------------------------------------------------------------------------------------------------
-- CTE 2: Calculate active subscriber MRR per month-end snapshot date.
-- ----------------------------------------------------------------------------------------------------------------------
customer_monthly_mrr AS (
    SELECT 
        d.month_end_date, 
        s.customer_id,
        SUM(CASE
                WHEN s.start_date <= d.month_end_date
                    AND (s.end_date IS NULL OR s.end_date > d.month_end_date)
                THEN s.plan_mrr
                ELSE 0.00
            END
                    ) AS mrr
    FROM monthly_spine d
    CROSS JOIN (SELECT DISTINCT customer_id FROM {{ref('fct_subscriptions')}}) c
    LEFT JOIN  {{ref('fct_subscriptions')}} s
        ON c.customer_id = s.customer_id
    GROUP BY 1, 2
),
-- -----------------------------------------------------------------------------------------------------------------------
-- CTE 3: Compute period-over-period delta using window function LAG()
--------------------------------------------------------------------------------------------------------------------------
mrr_movements as (
    SELECT 
        month_end_date,
        customer_id,
        COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) AS previous_mrr,
        mrr AS current_mrr,
        CASE 
            WHEN COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) = 0.00
                AND mrr > 0.00 THEN 'NEW'
            WHEN COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) > 0.00
                AND mrr > LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date) THEN 'EXPANSION'
            WHEN COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) > 0.00
                AND mrr < LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date) 
                AND mrr > 0.00 THEN 'CONTRACTION'
            WHEN COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) > 0.00
                AND mrr = 0.00 THEN 'CHURN'
            ELSE 'RETAINED'
        END AS mrr_category,
        mrr - COALESCE(LAG(mrr) OVER (PARTITION BY customer_id ORDER BY month_end_date),0.00) AS mrr_change
    FROM customer_monthly_mrr
),
-- ------------------------------------------------------------------------------------------------------------------------
-- CTE 4: FInal executive aggregation for financial reconciliation
-- ------------------------------------------------------------------------------------------------------------------------
final_waterfall AS(
    SELECT 
        month_end_date,
        sum(previous_mrr) as beginning_mrr,
        sum(CASE WHEN mrr_category = 'NEW' THEN mrr_change ELSE 0.00 END) AS new_mrr,
        sum(CASE WHEN mrr_category = 'EXPANSION' THEN mrr_change ELSE 0.00 END) AS expansion_mrr,
        sum(CASE WHEN mrr_category = 'CONTRACTION' THEN mrr_change ELSE 0.00 END) AS contraction_mrr,
        sum(CASE WHEN mrr_category = 'CHURN' THEN mrr_change ELSE 0.00 END) AS churn_mrr,
        sum(current_mrr) AS ending_mrr,
        sum(current_mrr) - SUM(previous_mrr) AS net_new_mrr
    FROM mrr_movements
    GROUP BY 1
)

SELECT * FROM final_waterfall
ORDER BY month_end_date ASC