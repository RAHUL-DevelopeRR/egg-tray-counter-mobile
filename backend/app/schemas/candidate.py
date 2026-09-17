"""Local spatial_3d_beam_v1 contract. Ground truth is never an inference input."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, FiniteFloat, StrictBool, model_validator

View = Literal["left", "straight", "right"]


class StrictRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")


class DetectionEvidence(StrictRecord):
    bbox: tuple[FiniteFloat, FiniteFloat, FiniteFloat, FiniteFloat]
    confidence: FiniteFloat = Field(ge=0, le=1)
    class_name: Literal["egg_tray"] = Field(default="egg_tray", alias="class")


class VisibilityEvidence(StrictRecord):
    shared_corner_visible: StrictBool | None = None
    rear_rows_visible: StrictBool | None = None
    occluded_stack_ids: list[str] = Field(default_factory=list, max_length=200)


class ViewEvidence(StrictRecord):
    image_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    coordinate_frame: Literal["exif_transposed_pixels"]
    detections: list[DetectionEvidence] = Field(max_length=2000)
    visibility: VisibilityEvidence = Field(default_factory=VisibilityEvidence)


class SOPProfile(StrictRecord):
    profile_id: Literal["orthogonal_stacks_v1"] = "orthogonal_stacks_v1"
    vertical_stacks: StrictBool | None = None
    orthogonal_layout: StrictBool | None = None
    all_positions_observed: StrictBool | None = None
    top_base_visible: StrictBool | None = None
    stable_arrangement: StrictBool | None = None
    boundaries_identifiable: StrictBool | None = None
    front_side_separation: StrictBool | None = None


class CandidateEvidence(StrictRecord):
    views: dict[View, ViewEvidence]
    sop: SOPProfile = Field(default_factory=SOPProfile)

    @model_validator(mode="after")
    def all_views(self):
        if set(self.views) != {"left", "straight", "right"}:
            raise ValueError("All three views required")
        return self


class Recommendation(StrictRecord):
    code: Literal[
        "BOTTOM_DARK",
        "REGION_DARK",
        "TOP_CROPPED",
        "BASE_CROPPED",
        "MOTION_BLUR",
        "STACK_OCCLUDED",
        "SHARED_CORNER_MISSING",
        "REAR_ROW_NOT_VISIBLE",
        "OCCUPANCY_UNCLEAR",
        "RIM_CONTRAST_LOW",
        "STACK_LOCALIZATION_INCOMPLETE",
        "SOP_VIOLATION",
        "IMAGE_QUALITY",
    ]
    view: View
    stack: str | None
    region: str
    cause: str
    action: str
    evidence_source: Literal["measured_image", "operator_declared", "unresolved_evidence"]


class Rescan(StrictRecord):
    reason: str
    recommendations: list[Recommendation]


class Geometry(StrictRecord):
    x_columns: int | None = Field(default=None, ge=1)
    y_rows: int | None = Field(default=None, ge=1)
    status: Literal["unresolved"] = "unresolved"


class CandidateResponse(StrictRecord):
    scan_contract: Literal["spatial_3d_beam_v1"] = "spatial_3d_beam_v1"
    contract_revision: Literal["candidate-20260917"] = "candidate-20260917"
    status: Literal["recapture_required", "out_of_operating_envelope"]
    verified: Literal[False] = False
    ground_truth_status: Literal["GROUND_TRUTH_UNKNOWN"] = "GROUND_TRUTH_UNKNOWN"
    evidence_source: str = "client_supplied_hash_bound_predictions_not_independently_authenticated"
    geometry: Geometry = Field(default_factory=Geometry)
    cells: list[dict] = Field(default_factory=list)
    physical_trays: None = None
    eligible_egg_trays: None = None
    empty_trays: None = None
    unknown_trays: None = None
    views: dict[View, dict]
    stacks: list[dict]
    view_correspondence: list[dict]
    beam_evidence: list[dict]
    rf_evidence: dict[View, list[dict]]
    assumptions_used: list[str]
    sop_violations: list[str]
    sop_unverified: list[str]
    rescan: Rescan
