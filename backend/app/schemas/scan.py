from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ViewQualitySchema(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quality: float = Field(ge=0, le=1)
    accepted: bool
    blur_score: float = Field(ge=0)
    exposure_mean: float = Field(ge=0, le=255)
    reason: str | None = None


class StackCountsSchema(BaseModel):
    left: int | None = Field(default=None, ge=0)
    right: int | None = Field(default=None, ge=0)
    straight: int | None = Field(default=None, ge=0)


class StackResultSchema(BaseModel):
    physical_stack_id: str
    counts: StackCountsSchema
    final_count: int | None = Field(default=None, ge=0)
    confidence: float = Field(ge=0, le=1)
    accepted: bool
    reason: str
    association_confidence: float = Field(ge=0, le=1)


class ProcessingSchema(BaseModel):
    mode: str
    latency_ms: int = Field(ge=0)
    model_version: str
    timings_ms: dict[str, int] = Field(default_factory=dict)


class ModelSchema(BaseModel):
    provider: str
    workspace: str
    project: str
    version: str
    model_id: str


class RescanSchema(BaseModel):
    recommended_view: Literal["left", "right", "straight"] | None = None
    reason: str


class ScanResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scan_id: str
    status: Literal["verified", "rescan_required"]
    accepted: bool
    physical_stack_count: int | None = Field(default=None, ge=0)
    total_trays: int | None = Field(default=None, ge=0)
    eggs_per_tray: int = Field(gt=0)
    total_eggs: int | None = Field(default=None, ge=0)
    model: ModelSchema
    processing: ProcessingSchema
    views: dict[Literal["left", "right", "straight"], ViewQualitySchema]
    stacks: list[StackResultSchema]
    rescan: RescanSchema | None = None

    @model_validator(mode="after")
    def protect_rejected_inventory(self) -> ScanResponse:
        if not self.accepted and any(
            value is not None for value in (self.total_trays, self.total_eggs, self.physical_stack_count)
        ):
            raise ValueError("Rejected scans must not expose inventory totals")
        if self.accepted and (self.total_trays is None or self.total_eggs is None):
            raise ValueError("Verified scans require tray and egg totals")
        return self
