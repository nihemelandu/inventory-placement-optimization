# Inventory Placement Optimization

**Live dashboard: [inventory-placement-optimization.streamlit.app](https://inventory-placement-optimization.streamlit.app)**

> How much stock should each location hold before a seasonal sale, and which location should fulfill each order, when demand is uncertain and nothing can be restocked mid-sale?

## The problem

A regional manager must determine how to allocate inventory across multiple locations before a fixed-length seasonal sale, when demand at each location is uncertain and replenishment is not possible. The manager must also develop a fulfillment policy to determine which location should serve each customer's demand, allowing inventory to be shared across locations when appropriate. The objective is to minimize the expected total cost of leftover inventory, unmet demand, and transportation while balancing the risks of overstocking and stockouts.

The three costs are:

- **Leftover inventory:** stock left over at the end of the sale.
- **Unmet demand:** customers who cannot be served.
- **Transportation:** shipping from a location farther from the customer.

The obvious approach is to let each location stock for its own customers. That leaves some locations with surplus while others run out, even though a surplus unit could often serve a neighbouring region at a modest transportation cost. The question is how much of that sharing is worth doing, and how much stock to place where, before anyone knows what demand will be.

## Why it matters

- **Stock is committed before demand is seen.** A wrong placement cannot be fixed during the sale.
- **Errors are costly in both directions.** Too much stock is paid for and unsold; too little means lost sales.
- **Sharing stock is a trade-off, not a free win.** Extra transportation has to be weighed against the leftover inventory and shortage costs it avoids.

## Approach

A fulfillment policy is developed using a two-stage stochastic programming model, solved with sample average approximation.

1. **Stage 1** chooses the stock to hold at each location, before demand is known.
2. **Stage 2** decides which location ships to which customer region, once demand is known. Any location with stock can serve any region (virtual pooling).

The objective is the average total cost (leftover inventory + unmet demand + transportation) across the demand scenarios. The model is written in Python with Pyomo and solved with the open-source HiGHS solver.

**Baseline:** each location stocks only for its own customers, at the level that minimizes that location's own cost.

## Result

**Pooling stock cuts cost per unit of demand from 8.87 to 4.98, a 43.9% saving over the independent-location baseline, and lands within 9% of the best cost achievable with perfect knowledge of demand (4.57).**

Success targets, set before the runs: at least 30% below the independent-location baseline out of sample, and within 20% of perfect information.

| | Model plan | Baseline |
|---|---|---|
| Cost per unit of demand | **4.98** | 8.87 |
| Total stock held (units) | 78 | 91 |
| Leftover inventory cost | 2.10 | 4.35 |
| Unmet demand cost | 1.10 | 3.62 |
| Transportation cost | 1.78 | 0.90 |

The plan costs less because sharing stock cuts leftover inventory and unmet-demand costs by more than the extra transportation adds.

| Location | Stock to hold (model) | Stock to hold (baseline) |
|---|---|---|
| Location 1 | 20 | 29 |
| Location 2 | 28 | 30 |
| Location 3 | 30 | 32 |

All figures above are **in-sample**: the plan was fitted on the same 30 past periods it is scored on, so they are optimistic. Out-of-sample results are below.

### Out-of-sample and ablation results

| Plan | Cost per unit of demand (held-out periods) |
|---|---|
| Stochastic plan with pooling | 5.34 |
| Deterministic mean-demand plan with pooling | 6.71 |
| Independent locations (baseline) | 9.45 |
| Perfect information (lower bound) | 4.62 |

The deterministic row separates two effects the baseline mixes together: the value of pooling, and the value of modelling uncertainty. Of the 4.11 reduction from the baseline, pooling accounts for 2.74 and modelling uncertainty for the other 1.37. Out of sample the stochastic plan is 43.5% below the baseline and within 16% of perfect information, which meets both targets.

## How we tested it

- **Data:** Olist Brazilian e-commerce orders (public), for the most frequently ordered product, aggregated to three customer regions and 30 two-week periods. Each period is treated as one possible sale.
- **Split:** the plan is fitted on 24 periods and scored on 6 held-out periods.
- **Baselines:** independent locations; deterministic mean-demand plan; perfect information as a lower bound.
- **Repeats:** 20 random 24/6 splits (seeds 0 to 19). Reported figures are means over the splits.

## Scenarios and scenario reduction

- **Scenario set:** the 24 training periods, used as observed. No demand distribution is fitted.
- **Reduction:** demand vectors are clustered with k-means, and each cluster is replaced by its mean demand, weighted by the number of periods in the cluster. This keeps solve time low as the network grows.

| Scenarios used | Cost per unit of demand (held-out periods) | Solve time (seconds) |
|---|---|---|
| 24 (all) | 5.34 | 0.04 |
| 12 | 5.36 | 0.03 |
| 8 | 5.41 | 0.02 |
| 4 | 5.68 | 0.02 |

Eight scenarios give a plan within 1.3% of the full-set cost. Four scenarios give up 6.4%.

## Assumptions

| Input | Value |
|---|---|
| Locations | 3 |
| Past sales periods used | 30 |
| Cost of one unit of leftover inventory | 1.00 |
| Cost of one unit not delivered | 9.00 (implies a 90% service target) |
| Cost to transport one unit | 1.00 to 5.00, by distance |

## Limits of these results

- The network is small (3 locations, 30 periods), so results show the mechanism, not how a full network would behave.
- The model only knows demand levels seen in past periods. A spike larger than anything in the history is not represented.
- Only demand is uncertain. Supply and lead-time uncertainty are not modelled.
- One product at a time, with no capacity limits at any location.
- The baseline is a location-by-location policy, not an existing company policy.
- The held-out test scores 6 periods per split, and all 20 splits are drawn from the same 30-period history, so the splits overlap and are not independent. Read the spread across splits as indicative, not as a confidence interval.

## Next steps

- Fixed pooling, to compare against virtual pooling.
- Multiple products with shared capacity limits.
- Supply and lead-time uncertainty.
- A full-size network with real facility locations.
- Demand drivers such as promotions.

## Repository

```
src/         Model code
data/        Input data
docs/        Design notes
dashboard/   Streamlit app, metrics.json, requirements.txt
```

## Run it

Python 3.11. Package versions are pinned in `requirements.txt`. A full run over all 20 splits takes under a minute.

```bash
pip install -r requirements.txt
python src/run_model.py --seed 0
streamlit run dashboard/app.py
```

Re-running the model rewrites `dashboard/metrics.json`. Commit it and the deployed dashboard refreshes from the repository.

## Where this departs from the paper

This project applies the paper's formulation to new data and extends it. The departures are:

- Public Olist data is used in place of the paper's RiRiShun data, so the paper's company-policy benchmark is not reproduced.
- A single sale window is solved with no replenishment, where the paper reapplies one fixed stock target across many periods.
- Only virtual pooling is implemented. Fixed pooling is not.
- Scenario reduction is added, following Abouelrous et al. (2022). The paper solves on every historical period.
- A deterministic mean-demand comparison is added. The paper does not include one.

## How the work is run

CRISP-DM in Agile sprints; backlog and milestones are tracked in GitHub Issues and Projects.

## Reference

Wang, Y., & Minner, S. (2025). Data-driven multi-location inventory placement in digital commerce. *Computers & Industrial Engineering*, 200, 110842.
