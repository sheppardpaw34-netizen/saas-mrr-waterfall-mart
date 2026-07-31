{% docs mrt_mrr_waterfall_docs %}

### Model Overview
Reconciles Monthly Recurring Revenue (MRR) movements (**New, Expansion, Contraction, Churn**) at the whole-company monthly snapshot grain.

* **Data Layer:** Marts (Financial Analysis)
* **Business Domain:** Subscription Revenue & Executive Reporting
* **Granularity:** One record per calendar month (`month_end_date`)
* **Primary Key:** `month_end_date`
* **Dependencies:** `ref('fct_subscriptions')`

{% enddocs %}A