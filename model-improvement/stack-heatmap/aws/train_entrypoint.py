"""SageMaker custom-container entrypoint using its File channels and checkpoint path."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(os.environ.get("STACK_DATA_ROOT", "/opt/ml/input/data/training"))
parameters_path = Path("/opt/ml/input/config/hyperparameters.json")
parameters = json.loads(parameters_path.read_text()) if parameters_path.exists() else {}
command = [sys.executable, "/opt/project/model-improvement/stack-heatmap/train_heatmap.py",
           "--manifest", str(root / os.environ.get("DATASET_MANIFEST", "faces.json")),
           "--output", "/opt/ml/model", "--device", "cuda",
           "--epochs", str(parameters.get("epochs", 20)), "--mode", parameters.get("mode", "loco")]
subprocess.run(command, check=True)
