"""
==============================================================================
Google Compensation FastMCP Microservice
==============================================================================
Provides deterministic tools for equity vesting calculations and salary band
compliance auditing over Model Context Protocol (MCP) and HTTP REST.
"""

from enum import Enum
from typing import Dict, Any, List
from fastapi import FastAPI, Response, status
from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

# 1. Initialize FastMCP Server
mcp = FastMCP("Google-Compensation-MCP-Engine")

# --- TOOL 1: Equity Vesting Calculation (Largest Remainder Method) ---

class VestingScheduleType(str, Enum):
    FRONT_LOADED_33_33_22_12 = "FRONT_LOADED_33_33_22_12"
    STANDARD_EQUAL_4YR = "STANDARD_EQUAL_4YR"

class VestingRequest(BaseModel):
    total_shares: int = Field(description="Total equity grant units (e.g. 1000 GSUs)", ge=1)
    schedule_type: VestingScheduleType = Field(
        default=VestingScheduleType.FRONT_LOADED_33_33_22_12,
        description="Vesting schedule model: 'FRONT_LOADED_33_33_22_12' or 'STANDARD_EQUAL_4YR'"
    )

@mcp.tool()
def calculate_equity_vesting(req: VestingRequest) -> Dict[str, Any]:
    """
    Calculates exact annual share vesting using the Largest Remainder Method
    to guarantee zero fractional share loss across vesting tranches.
    """
    if req.schedule_type == VestingScheduleType.FRONT_LOADED_33_33_22_12:
        percentages = [0.33333333, 0.33333333, 0.22222222, 0.11111111]
    else:
        percentages = [0.25, 0.25, 0.25, 0.25]

    # Calculate exact integer allocations using Largest Remainder Method
    raw_shares = [req.total_shares * p for p in percentages]
    floored_shares = [int(s) for s in raw_shares]
    remainders = [raw - floor for raw, floor in zip(raw_shares, floored_shares)]
    
    # Distribute leftover rounding shares to highest remainder tranches
    unallocated = req.total_shares - sum(floored_shares)
    sorted_indices = sorted(range(len(remainders)), key=lambda i: remainders[i], reverse=True)
    
    for i in range(unallocated):
        floored_shares[sorted_indices[i]] += 1

    return {
        "total_granted": req.total_shares,
        "schedule_model": req.schedule_type.value,
        "tranches": {
            "year_1": floored_shares[0],
            "year_2": floored_shares[1],
            "year_3": floored_shares[2],
            "year_4": floored_shares[3],
        },
        "sum_invariant_verified": sum(floored_shares) == req.total_shares
    }

# --- TOOL 2: Salary Band Compliance & Compa-Ratio ---

class BandStatus(str, Enum):
    BELOW_MINIMUM = "BELOW_MINIMUM"
    IN_BAND = "IN_BAND"
    ABOVE_MAXIMUM = "ABOVE_MAXIMUM"
    VP_APPROVAL_REQUIRED = "VP_APPROVAL_REQUIRED"

class SalaryAuditRequest(BaseModel):
    proposed_salary: float = Field(description="Proposed annual base salary in USD", gt=0)
    job_level: str = Field(description="Google Job Level (e.g. 'L4', 'L5', 'L6', 'L7')")
    location: str = Field(description="Office location code (e.g. 'US-MTV', 'US-NYC', 'US-AUS')")

# Mock Compensation Salary Grid (Production backed by PostgreSQL)
SALARY_BANDS: Dict[tuple, Dict[str, float]] = {
    ("L6", "US-MTV"): {"min": 190000.0, "mid": 220000.0, "max": 250000.0},
    ("L5", "US-MTV"): {"min": 150000.0, "mid": 175000.0, "max": 200000.0},
    ("L4", "US-MTV"): {"min": 120000.0, "mid": 140000.0, "max": 160000.0},
    ("L6", "US-NYC"): {"min": 195000.0, "mid": 225000.0, "max": 255000.0},
    ("L5", "US-NYC"): {"min": 155000.0, "mid": 180000.0, "max": 205000.0},
}

@mcp.tool()
def audit_salary_band_compliance(req: SalaryAuditRequest) -> Dict[str, Any]:
    """
    Audits a proposed salary against official geographical pay bands,
    calculates exact Compa-Ratio, and determines compliance status.
    """
    grid_key = (req.job_level, req.location)
    band = SALARY_BANDS.get(grid_key, {"min": 150000.0, "mid": 175000.0, "max": 200000.0})
    
    compa_ratio = round(req.proposed_salary / band["mid"], 4)

    if req.proposed_salary < band["min"]:
        status_val = BandStatus.BELOW_MINIMUM
    elif req.proposed_salary > band["max"] or compa_ratio > 1.20:
        status_val = BandStatus.VP_APPROVAL_REQUIRED
    else:
        status_val = BandStatus.IN_BAND

    return {
        "job_level": req.job_level,
        "location": req.location,
        "proposed_salary": req.proposed_salary,
        "band_min": band["min"],
        "band_mid": band["mid"],
        "band_max": band["max"],
        "compa_ratio": compa_ratio,
        "compa_ratio_percentage": f"{round(compa_ratio * 100, 2)}%",
        "compliance_status": status_val.value,
        "requires_exception_workflow": status_val == BandStatus.VP_APPROVAL_REQUIRED
    }

# --- 2. FastAPI Application Wrapper for Health Checks & REST ---

app = FastAPI(
    title="Google Compensation MCP API",
    version="1.0.0",
    description="Model Context Protocol microservice for automated compensation workflows."
)

@app.get("/healthz", status_code=status.HTTP_200_OK)
async def health_check():
    """Kubernetes Liveness and Readiness Probe Endpoint."""
    return {"status": "HEALTHY", "service": "compensation-mcp-engine"}

@app.post("/api/v1/vesting")
async def api_vesting(req: VestingRequest):
    """Direct REST endpoint for equity vesting calculation."""
    return calculate_equity_vesting(req)

@app.post("/api/v1/salary-audit")
async def api_salary_audit(req: SalaryAuditRequest):
    """Direct REST endpoint for salary band compliance audit."""
    return audit_salary_band_compliance(req)
