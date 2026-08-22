from __future__ import annotations


class EggCounterError(Exception):
    code = "egg_counter_error"

    def __init__(self, message: str, *, recommended_view: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.recommended_view = recommended_view


class InvalidImageError(EggCounterError):
    code = "invalid_image"


class ImageQualityError(EggCounterError):
    code = "image_quality"


class InferenceProviderError(EggCounterError):
    code = "inference_provider"


class NoStackDetectedError(EggCounterError):
    code = "no_stack_detected"


class UnsupportedModelOutputError(InferenceProviderError):
    code = "unsupported_model_output"


class StackAssociationError(EggCounterError):
    code = "stack_association"


class ViewDisagreementError(EggCounterError):
    code = "view_disagreement"


class InsufficientEvidenceError(EggCounterError):
    code = "insufficient_evidence"
