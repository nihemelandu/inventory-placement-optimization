"""Dashboard. Reads metrics.json, which the model run writes to the repo."""
import json
from pathlib import Path

import pandas as pd
import streamlit as st

st.set_page_config(page_title="Inventory plan: model vs. baseline", layout="wide")

R = json.loads((Path(__file__).parent / "metrics.json").read_text())
locs = R["locations"]


def num(v, placeholder):
    return placeholder if v is None else f"{v:,.2f}"


def plain(v):
    return "–" if v is None else f"{v:,}" if isinstance(v, int) else str(v)


model_cost, base_cost = R["model_cost"], R["baseline_cost"]
saving = None if model_cost is None or not base_cost else (base_cost - model_cost) / base_cost

st.title("Inventory plan: model vs. baseline")
st.caption("Recommended stock, shipments, and cost for the seasonal sale.")

# Headline
c1, c2, c3 = st.columns(3)
unit = R.get("cost_unit", "per unit of demand")
c1.metric(f"Model plan cost ({unit})", num(model_cost, "X"), border=True)
c2.metric(f"Baseline cost ({unit})", num(base_cost, "Y"), border=True)
c3.metric("Saving", "Z%" if saving is None else f"{saving:.1%}", border=True)

# Main chart and cost breakdown
left, right = st.columns([1.7, 1])
with left:
    with st.container(border=True):
        st.subheader("Stock to hold at each location")
        st.caption("Units of stock before the sale starts")
        stock = pd.DataFrame(
            {"Model plan": R["stock"]["model"], "Baseline": R["stock"]["baseline"]},
            index=locs, dtype=float)
        st.bar_chart(stock, color=["#0F6E6E", "#8A94A1"])
with right:
    with st.container(border=True):
        st.subheader("Why it costs less")
        st.caption("Total cost split by type")
        cb = R["cost_breakdown"]
        cost = pd.DataFrame(
            {"Holding": [cb["model"]["holding"], cb["baseline"]["holding"]],
             "Unmet demand": [cb["model"]["unmet_demand"], cb["baseline"]["unmet_demand"]],
             "Transport": [cb["model"]["transport"], cb["baseline"]["transport"]]},
            index=["Model plan", "Baseline"], dtype=float)
        st.bar_chart(cost, color=["#2F6F8F", "#C0673A", "#7C8794"])

# Shipments and basis
a, b = st.columns(2)
with a:
    with st.container(border=True):
        st.subheader("Who ships to whom")
        st.caption("Units sent from each location to each location’s customers")
        ship = pd.DataFrame(R["shipments"],
                            index=[f"From {l}" for l in locs],
                            columns=[f"To {l}" for l in locs])
        st.dataframe(ship.apply(lambda col: col.map(
            lambda v: "–" if pd.isna(v) else f"{v:,.0f}")), width="stretch")
with b:
    with st.container(border=True):
        st.subheader("What this is based on")
        A = R["assumptions"]
        st.markdown(
            f"- **Locations:** {plain(A['locations'])}\n"
            f"- **Past sales periods used:** {plain(A['past_periods'])}\n"
            f"- **Cost to hold one unit:** {plain(A['holding_cost'])}\n"
            f"- **Cost of one unit not delivered:** {plain(A['unmet_cost'])}\n"
            f"- **Cost to ship one unit:** {plain(A['transport_cost'])}")
        st.markdown(
            "**How it was derived.** The model tests each stock level against past "
            "demand and keeps the one with the lowest average total cost. It then "
            "decides which location ships to which. The baseline has every location "
            "stock only for itself.")
